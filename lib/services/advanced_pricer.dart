import 'package:flutter/foundation.dart';

import '../pricing/pricing_job.dart';

/// Where a pricing job actually ran.
///
/// Surfaced to the learner rather than hidden, because "this took four
/// seconds on your phone" and "this was computed on a server" are different
/// facts about the same number, and the second one means data left the device
/// (CLAUDE.md rule 6 — collect and transmit the minimum).
enum PricingVenue {
  /// Small enough to run between two frames without anyone noticing.
  inline,

  /// A background isolate via `compute()`. The UI keeps animating.
  isolate,

  /// A Supabase Edge Function (`price-heavy`, DEPLOY.md 1d).
  server,
}

extension PricingVenueLabel on PricingVenue {
  String get label => switch (this) {
    PricingVenue.inline => 'on this device',
    PricingVenue.isolate => 'on this device, in the background',
    PricingVenue.server => 'on the server',
  };
}

/// A completed run: the numbers, and an honest account of how they were got.
class PricingRun {
  const PricingRun({
    required this.result,
    required this.venue,
    required this.elapsed,
    this.serverFallbackReason,
  });

  final PricingJobResult result;
  final PricingVenue venue;
  final Duration elapsed;

  /// Set when the job was meant for the server and ran on the device instead.
  /// The answer is still correct — it is the same code — but it took longer,
  /// and the learner is told rather than left wondering.
  final String? serverFallbackReason;
}

/// Somewhere a very large job can be sent.
///
/// An interface rather than a direct Supabase call so the Sandbox has no
/// opinion about whether a backend exists — matching how every other
/// repository in this app is wired, and keeping `lib/pricing` free of both
/// Flutter and network code.
abstract interface class RemotePricingClient {
  /// True when a backend is configured and reachable enough to try.
  bool get isAvailable;

  /// Runs [job] remotely. Throws on any failure; [AdvancedPricer] catches and
  /// falls back to the device, because a slow correct answer beats an error.
  Future<PricingJobResult> run(PricingJob job);
}

/// A stand-in for when there is no backend: never available, never called.
class UnavailableRemotePricingClient implements RemotePricingClient {
  const UnavailableRemotePricingClient();

  @override
  bool get isAvailable => false;

  @override
  Future<PricingJobResult> run(PricingJob job) =>
      throw StateError('No pricing backend is configured.');
}

/// Runs pricing jobs in the cheapest place that will not make the app stutter.
///
/// THE THRESHOLDS, and why they are where they are. A phone renders a frame
/// every 16 milliseconds. Anything that blocks the main thread for longer
/// than that drops frames, and a slider that stutters while a learner drags
/// it teaches them that the app is broken rather than that volatility matters.
/// So:
///
///   * below [inlineWorkload] draws — a few milliseconds — run inline, since
///     hopping to an isolate costs more than the work itself;
///   * up to [serverWorkload] — where a phone still finishes in seconds — go
///     to a background isolate, so the UI keeps moving;
///   * beyond that, offer it to the server if one is configured.
///
/// The numbers are deliberately conservative. Being wrong in the direction of
/// "used an isolate when it was not strictly needed" costs a millisecond;
/// being wrong the other way costs a visibly frozen app.
class AdvancedPricer {
  const AdvancedPricer({
    this.remote = const UnavailableRemotePricingClient(),
  });

  final RemotePricingClient remote;

  /// Draws below which a job runs on the main thread.
  static const int inlineWorkload = 200000;

  /// Draws above which the server is preferred, if there is one.
  static const int serverWorkload = 20000000;

  /// The largest job the UI will accept at all.
  ///
  /// Not a technical limit — the engine would keep going — but a limit on
  /// what is reasonable to ask a learner's phone and battery to do for a
  /// teaching illustration. A run this size adds precision far below the
  /// modelling error that already dominates the answer.
  static const int maximumWorkload = 400000000;

  PricingVenue venueFor(PricingJob job) {
    if (job.workload <= inlineWorkload) return PricingVenue.inline;
    if (job.workload <= serverWorkload || !remote.isAvailable) {
      return PricingVenue.isolate;
    }
    return PricingVenue.server;
  }

  /// Prices [job], choosing where to run it.
  ///
  /// A server failure is never fatal: the job falls back to an isolate, since
  /// the same pure-Dart engine is on the device anyway. An app that cannot
  /// price an option because a network call failed would be a worse app than
  /// one that takes a few seconds longer.
  Future<PricingRun> price(PricingJob job) async {
    if (job.workload > maximumWorkload) {
      throw ArgumentError(
        'That run is larger than this tool will attempt. Reduce the paths or '
        'the steps — beyond this point the extra precision is far smaller '
        'than the error in the model itself.',
      );
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final PricingVenue venue = venueFor(job);

    if (venue == PricingVenue.server) {
      try {
        final PricingJobResult result = await remote.run(job);
        stopwatch.stop();
        return PricingRun(
          result: result,
          venue: PricingVenue.server,
          elapsed: stopwatch.elapsed,
        );
      } on Object catch (error, stackTrace) {
        // Swallowed for the learner, not for the developer: the run still
        // succeeds on the device, but a backend that is quietly failing every
        // request should not be invisible while debugging.
        debugPrint('price-heavy failed, falling back to an isolate: $error');
        assert(() {
          debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
          return true;
        }());

        final PricingJobResult result = await _onIsolate(job);
        stopwatch.stop();
        return PricingRun(
          result: result,
          venue: PricingVenue.isolate,
          elapsed: stopwatch.elapsed,
          serverFallbackReason: serverFallbackMessage,
        );
      }
    }

    final PricingJobResult result = venue == PricingVenue.inline
        ? runPricingJob(job)
        : await _onIsolate(job);
    stopwatch.stop();

    return PricingRun(
      result: result,
      venue: venue,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Hands the job to a background isolate.
  ///
  /// The payload crosses as JSON rather than as a Dart object, so the same
  /// encoding the server path depends on is exercised on every on-device run
  /// and cannot rot unnoticed. See `pricing_job.dart`.
  Future<PricingJobResult> _onIsolate(PricingJob job) async {
    final Map<String, dynamic> raw = await compute(
      runPricingJobJson,
      job.toJson(),
    );
    return PricingJobResult.fromJson(raw);
  }

  /// Shown when a server run fell back to the device.
  ///
  /// Deliberately says nothing about WHY. The underlying error is a detail of
  /// our infrastructure, not something a learner can act on, and error text
  /// from a backend is exactly the kind of thing that leaks more than it
  /// should. The developer-facing detail goes to the debug log instead.
  static const String serverFallbackMessage =
      'The server could not be reached, so this ran on your device instead. '
      'The answer is the same; it just took longer.';
}
