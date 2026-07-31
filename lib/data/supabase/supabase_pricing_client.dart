import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../pricing/monte_carlo.dart';
import '../../pricing/pricing_job.dart';
import '../../services/advanced_pricer.dart';

/// Sends very large Monte Carlo runs to the `price-heavy` Edge Function
/// (DEPLOY.md 1d).
///
/// WHAT CROSSES THE WIRE, and what does not. Only the contract's numbers go
/// up — spot, strike, volatility, path count — and only three numbers come
/// back. No username, no progress, nothing identifying, and no result is
/// stored server-side. A learner playing with a hypothetical option is not
/// telling us anything about themselves, and the request is built so that it
/// cannot start doing so by accident (CLAUDE.md rule 6: collect the minimum).
///
/// WHY THE CLOSED FORMS STAY HERE. The function returns a simulated price, a
/// standard error and a path count — nothing else. The exact price and the
/// caveats are computed on the device by [describeSimulation], so a server
/// running an older deployment can never serve a stale disclaimer or a
/// missing one. It also keeps the Edge Function small: the less of the
/// pricing library exists twice in two languages, the less there is to
/// silently disagree.
///
/// The function requires an authenticated caller, so anonymous traffic cannot
/// use the project as free compute.
class SupabasePricingClient implements RemotePricingClient {
  const SupabasePricingClient(this._client);

  final sb.SupabaseClient _client;

  /// The deployed function name.
  static const String functionName = 'price-heavy';

  @override
  bool get isAvailable => _client.auth.currentSession != null;

  @override
  Future<PricingJobResult> run(PricingJob job) async {
    final sb.FunctionResponse response = await _client.functions.invoke(
      functionName,
      body: job.toJson(),
    );

    if (response.status != 200) {
      throw RemotePricingException(
        'The pricing server answered with status ${response.status}.',
      );
    }

    final Object? data = response.data;
    if (data is! Map) {
      throw const RemotePricingException(
        'The pricing server sent something that was not a result.',
      );
    }
    final Map<String, dynamic> body = data.cast<String, dynamic>();

    final Object? price = body['price'];
    final Object? standardError = body['standard_error'];
    final Object? paths = body['paths'];
    if (price is! num || standardError is! num || paths is! num) {
      throw const RemotePricingException(
        'The pricing server sent an incomplete result.',
      );
    }
    if (!price.toDouble().isFinite || !standardError.toDouble().isFinite) {
      throw const RemotePricingException(
        'The pricing server sent a number that is not finite.',
      );
    }
    if (standardError < 0) {
      throw const RemotePricingException(
        'The pricing server reported a negative error, which is impossible.',
      );
    }

    // The estimate is the server's; the exact reference and the caveats are
    // added here, from this build's own pricing library.
    return describeSimulation(
      job,
      McEstimate(
        price: price.toDouble(),
        standardError: standardError.toDouble(),
        paths: paths.toInt(),
      ),
    );
  }
}

/// A remote run that could not be trusted or completed.
///
/// Always caught by [AdvancedPricer], which falls back to an on-device
/// isolate — the same engine, just slower.
class RemotePricingException implements Exception {
  const RemotePricingException(this.message);

  final String message;

  @override
  String toString() => 'RemotePricingException: $message';
}
