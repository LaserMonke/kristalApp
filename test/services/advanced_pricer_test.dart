import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/monte_carlo.dart';
import 'package:optionsschool/pricing/pricing_job.dart';
import 'package:optionsschool/services/advanced_pricer.dart';

/// [AdvancedPricer] decides WHERE a pricing job runs. The decision matters
/// for one reason above all: a run that blocks the main thread for longer
/// than a frame makes the app stutter, and an app that stutters while a
/// learner drags a slider has taught them something other than finance.
void main() {
  const BsmInputs market = BsmInputs(
    spot: 100,
    strike: 100,
    rate: 0.04,
    volatility: 0.25,
    timeToExpiry: 1,
  );

  PricingJob jobWith({required int paths, required int steps}) =>
      BarrierPricingJob(
        spec: const BarrierSpec(
          type: OptionType.call,
          direction: BarrierDirection.down,
          style: BarrierStyle.knockOut,
          barrier: 80,
        ),
        inputs: market,
        settings: McSettings(paths: paths, steps: steps, seed: 21),
      );

  group('choosing a venue', () {
    const AdvancedPricer offline = AdvancedPricer();

    test('a small job runs inline', () {
      expect(
        offline.venueFor(jobWith(paths: 1000, steps: 10)),
        PricingVenue.inline,
      );
    });

    test('a medium job goes to an isolate', () {
      expect(
        offline.venueFor(jobWith(paths: 50000, steps: 200)),
        PricingVenue.isolate,
      );
    });

    test('a huge job stays on the device when there is no backend', () {
      // No server configured, so the only honest options are "isolate" or
      // "refuse". Taking longer beats refusing.
      expect(
        offline.venueFor(jobWith(paths: 400000, steps: 200)),
        PricingVenue.isolate,
      );
    });

    test('a huge job goes to the server when there is one', () {
      final AdvancedPricer online = AdvancedPricer(
        remote: _FakeRemote(price: 12.5),
      );
      expect(
        online.venueFor(jobWith(paths: 400000, steps: 200)),
        PricingVenue.server,
      );
    });

    test('a small job stays inline even when a server is available', () {
      // Round-tripping a millisecond of work to a server would be slower and
      // would send data off the device for no reason (CLAUDE.md rule 6).
      final AdvancedPricer online = AdvancedPricer(
        remote: _FakeRemote(price: 1),
      );
      expect(
        online.venueFor(jobWith(paths: 500, steps: 5)),
        PricingVenue.inline,
      );
    });

    test('the thresholds are ordered sensibly', () {
      expect(
        AdvancedPricer.inlineWorkload,
        lessThan(AdvancedPricer.serverWorkload),
      );
      expect(
        AdvancedPricer.serverWorkload,
        lessThan(AdvancedPricer.maximumWorkload),
      );
    });
  });

  group('running', () {
    test('an inline job returns the same answer as the engine directly', () async {
      const AdvancedPricer pricer = AdvancedPricer();
      final PricingJob job = jobWith(paths: 2000, steps: 20);

      final PricingRun run = await pricer.price(job);

      expect(run.venue, PricingVenue.inline);
      expect(run.result.price, runPricingJob(job).price);
      expect(run.serverFallbackReason, isNull);
    });

    test('an isolate job survives the JSON round trip intact', () async {
      // The real point of this test: `compute` sends the job as JSON, so a
      // serialisation fault would show up here as a different price rather
      // than as an exception.
      const AdvancedPricer pricer = AdvancedPricer();
      final PricingJob job = jobWith(paths: 20000, steps: 60);

      final PricingRun run = await pricer.price(job);

      expect(run.venue, PricingVenue.isolate);
      expect(run.result.price, closeTo(runPricingJob(job).price, 1e-9));
      expect(run.result.analyticReference, isNotNull);
      expect(run.result.notes, isNotEmpty);
    });

    test('a server job is used when one is offered', () async {
      final _FakeRemote remote = _FakeRemote(price: 7.25);
      final AdvancedPricer pricer = AdvancedPricer(remote: remote);

      final PricingRun run = await pricer.price(
        jobWith(paths: 400000, steps: 200),
      );

      expect(run.venue, PricingVenue.server);
      expect(run.result.price, 7.25);
      expect(remote.calls, 1);
    });

    /// The failure that must not become the learner's problem. The same pure
    /// Dart engine is already on the device, so a backend outage should cost
    /// seconds, not the feature.
    test('a server failure falls back to the device and says so', () async {
      final _FakeRemote remote = _FakeRemote.failing();
      final AdvancedPricer pricer = AdvancedPricer(remote: remote);
      final PricingJob job = jobWith(paths: 400000, steps: 200);

      final PricingRun run = await pricer.price(job);

      expect(remote.calls, 1);
      expect(run.venue, PricingVenue.isolate);
      expect(run.result.price, closeTo(runPricingJob(job).price, 1e-9));
      expect(run.serverFallbackReason, AdvancedPricer.serverFallbackMessage);
      // It explains the consequence without leaking the backend's error text.
      expect(run.serverFallbackReason, contains('answer is the same'));
    });

    test('an absurd job is refused rather than attempted', () async {
      const AdvancedPricer pricer = AdvancedPricer();
      expect(
        () => pricer.price(jobWith(paths: 40000000, steps: 20000)),
        throwsArgumentError,
      );
    });

    test('the elapsed time is measured', () async {
      const AdvancedPricer pricer = AdvancedPricer();
      final PricingRun run = await pricer.price(jobWith(paths: 1000, steps: 5));
      expect(run.elapsed, greaterThanOrEqualTo(Duration.zero));
    });
  });

  group('venue labels', () {
    test('describe where the work happened in plain words', () {
      expect(PricingVenue.inline.label, 'on this device');
      expect(PricingVenue.isolate.label, contains('this device'));
      // A learner should be able to tell that this one left the phone.
      expect(PricingVenue.server.label, 'on the server');
    });
  });

  group('UnavailableRemotePricingClient', () {
    test('is never available and throws if called anyway', () {
      const UnavailableRemotePricingClient client =
          UnavailableRemotePricingClient();
      expect(client.isAvailable, isFalse);
      expect(
        () => client.run(
          const EuropeanPricingJob(type: OptionType.call, inputs: market),
        ),
        throwsStateError,
      );
    });
  });
}

class _FakeRemote implements RemotePricingClient {
  _FakeRemote({required this.price}) : _fails = false;
  _FakeRemote.failing() : price = 0, _fails = true;

  final double price;
  final bool _fails;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PricingJobResult> run(PricingJob job) async {
    calls++;
    if (_fails) throw Exception('backend unreachable');
    return PricingJobResult(
      price: price,
      standardError: 0.01,
      paths: job.settings.paths,
    );
  }
}
