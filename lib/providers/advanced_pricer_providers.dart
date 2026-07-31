import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../data/supabase/supabase_pricing_client.dart';
import '../pricing/barrier.dart';
import '../pricing/basket.dart';
import '../pricing/black_scholes.dart';
import '../pricing/heston.dart';
import '../pricing/monte_carlo.dart';
import '../pricing/priced_leg.dart';
import '../pricing/pricing_job.dart';
import '../pricing/structured.dart';
import '../services/advanced_pricer.dart';
import 'pricer_providers.dart';
import 'repository_providers.dart';

/// State for the Phase 8 "Advanced" pricer tab.
///
/// The advanced instruments share the Phase 4 [marketEnvironmentProvider], so
/// a learner who has just built an intuition for spot and volatility on the
/// simple tabs carries it straight across rather than starting again.

/// Which instrument the Advanced tab is showing.
enum AdvancedInstrument { barrier, asian, basket, heston, structured }

extension AdvancedInstrumentInfo on AdvancedInstrument {
  String get label => switch (this) {
    AdvancedInstrument.barrier => 'Barrier',
    AdvancedInstrument.asian => 'Asian',
    AdvancedInstrument.basket => 'Basket',
    AdvancedInstrument.heston => 'Heston',
    AdvancedInstrument.structured => 'Structured',
  };

  /// One line on what the instrument is, in plain words.
  String get blurb => switch (this) {
    AdvancedInstrument.barrier =>
      'An option that dies — or only comes alive — if the price touches a '
          'level. Cheaper than a plain option, because it pays in fewer '
          'situations.',
    AdvancedInstrument.asian =>
      'Pays on the AVERAGE price over the option\'s life instead of the final '
          'price. Averaging damps the extremes, so it costs less.',
    AdvancedInstrument.basket =>
      'One option on a blend of several underlyings. Assets that move '
          'together make it dear; assets that move independently make it '
          'cheap.',
    AdvancedInstrument.heston =>
      'Volatility as a second random process rather than a fixed number. It '
          'is what lets a model reproduce the volatility smile real markets '
          'show.',
    AdvancedInstrument.structured =>
      'Retail products — a bond bundled with options and sold as one '
          'certificate. Taking the wrapper off is the whole exercise.',
  };

  /// True when this instrument is priced by simulation rather than a formula.
  bool get needsSimulation => this != AdvancedInstrument.structured;
}

class AdvancedInstrumentController extends Notifier<AdvancedInstrument> {
  @override
  AdvancedInstrument build() => AdvancedInstrument.barrier;

  void select(AdvancedInstrument instrument) => state = instrument;
}

final NotifierProvider<AdvancedInstrumentController, AdvancedInstrument>
advancedInstrumentProvider =
    NotifierProvider<AdvancedInstrumentController, AdvancedInstrument>(
      AdvancedInstrumentController.new,
    );

/// ── Instrument settings ──────────────────────────────────────────────────

/// Everything the Advanced tab lets a learner change, beyond the shared
/// market inputs.
class AdvancedSettings {
  const AdvancedSettings({
    this.optionType = OptionType.call,
    this.strike = 100,
    this.barrierRatio = 0.85,
    this.barrierDirection = BarrierDirection.down,
    this.barrierStyle = BarrierStyle.knockOut,
    this.continuityCorrection = false,
    this.asianAverage = AsianAverage.arithmetic,
    this.basketSize = 3,
    this.basketCorrelation = 0.35,
    this.heston = HestonParams.equityLike,
    this.product = StructuredProductKind.capitalProtected,
    this.paths = 50000,
    this.steps = 100,
  });

  final OptionType optionType;
  final double strike;

  /// Barrier as a multiple of spot, so it stays sensible when spot moves.
  final double barrierRatio;
  final BarrierDirection barrierDirection;
  final BarrierStyle barrierStyle;
  final bool continuityCorrection;

  final AsianAverage asianAverage;

  final int basketSize;
  final double basketCorrelation;

  final HestonParams heston;

  final StructuredProductKind product;

  final int paths;
  final int steps;

  AdvancedSettings copyWith({
    OptionType? optionType,
    double? strike,
    double? barrierRatio,
    BarrierDirection? barrierDirection,
    BarrierStyle? barrierStyle,
    bool? continuityCorrection,
    AsianAverage? asianAverage,
    int? basketSize,
    double? basketCorrelation,
    HestonParams? heston,
    StructuredProductKind? product,
    int? paths,
    int? steps,
  }) => AdvancedSettings(
    optionType: optionType ?? this.optionType,
    strike: strike ?? this.strike,
    barrierRatio: barrierRatio ?? this.barrierRatio,
    barrierDirection: barrierDirection ?? this.barrierDirection,
    barrierStyle: barrierStyle ?? this.barrierStyle,
    continuityCorrection: continuityCorrection ?? this.continuityCorrection,
    asianAverage: asianAverage ?? this.asianAverage,
    basketSize: basketSize ?? this.basketSize,
    basketCorrelation: basketCorrelation ?? this.basketCorrelation,
    heston: heston ?? this.heston,
    product: product ?? this.product,
    paths: paths ?? this.paths,
    steps: steps ?? this.steps,
  );
}

/// Which structured product the Structured panel is taking apart.
enum StructuredProductKind {
  capitalProtected,
  reverseConvertible,
  barrierReverseConvertible,
  discountCertificate,
}

extension StructuredProductKindInfo on StructuredProductKind {
  String get label => switch (this) {
    StructuredProductKind.capitalProtected => 'Capital-protected note',
    StructuredProductKind.reverseConvertible => 'Reverse convertible',
    StructuredProductKind.barrierReverseConvertible =>
      'Barrier reverse convertible',
    StructuredProductKind.discountCertificate => 'Discount certificate',
  };

  StructuredProduct build() => switch (this) {
    StructuredProductKind.capitalProtected => const CapitalProtectedNote(),
    StructuredProductKind.reverseConvertible => const ReverseConvertible(),
    StructuredProductKind.barrierReverseConvertible =>
      const BarrierReverseConvertible(),
    StructuredProductKind.discountCertificate => const DiscountCertificate(),
  };
}

class AdvancedSettingsController extends Notifier<AdvancedSettings> {
  @override
  AdvancedSettings build() {
    final double spot = ref.watch(marketEnvironmentProvider).spot;
    return AdvancedSettings(strike: spot.roundToDouble());
  }

  void update(AdvancedSettings Function(AdvancedSettings) change) =>
      state = change(state);

  void reset() => state = build();
}

final NotifierProvider<AdvancedSettingsController, AdvancedSettings>
advancedSettingsProvider =
    NotifierProvider<AdvancedSettingsController, AdvancedSettings>(
      AdvancedSettingsController.new,
    );

/// ── Building the job ─────────────────────────────────────────────────────

/// The market inputs as Black-Scholes needs them.
BsmInputs _bsmInputs(MarketEnvironment env, double strike) => BsmInputs(
  spot: env.spot,
  strike: strike,
  rate: env.rate,
  volatility: env.volatility,
  timeToExpiry: env.timeToExpiry,
);

/// The job the Run button will submit, or null for an instrument that is
/// priced by formula and needs no simulation.
final Provider<PricingJob?> advancedJobProvider = Provider<PricingJob?>((
  Ref ref,
) {
  final AdvancedInstrument instrument = ref.watch(advancedInstrumentProvider);
  final AdvancedSettings settings = ref.watch(advancedSettingsProvider);
  final MarketEnvironment env = ref.watch(marketEnvironmentProvider);

  // The seed is fixed rather than randomised per run. Pressing Run twice
  // without changing anything gives the same answer, so a learner can tell a
  // change they made from noise in the dice — which is the difference between
  // an experiment and a slot machine.
  final McSettings mc = McSettings(
    paths: settings.paths,
    steps: settings.steps,
    seed: 20260731,
  );

  return switch (instrument) {
    AdvancedInstrument.barrier => BarrierPricingJob(
      spec: BarrierSpec(
        type: settings.optionType,
        direction: settings.barrierDirection,
        style: settings.barrierStyle,
        barrier: env.spot * settings.barrierRatio,
      ),
      inputs: _bsmInputs(env, settings.strike),
      continuityCorrection: settings.continuityCorrection,
      settings: mc,
    ),

    AdvancedInstrument.asian => AsianPricingJob(
      type: settings.optionType,
      inputs: _bsmInputs(env, settings.strike),
      average: settings.asianAverage,
      settings: mc,
    ),

    AdvancedInstrument.basket => BasketPricingJob(
      spec: BasketSpec(
        assets: _basketAssets(env, settings.basketSize),
        correlation: uniformCorrelation(
          settings.basketSize,
          settings.basketCorrelation,
        ),
        strike: settings.strike,
        type: settings.optionType,
        rate: env.rate,
        timeToExpiry: env.timeToExpiry,
      ),
      // A basket's payoff depends only on where the assets finish, so one
      // jump to expiry is all that is needed. Forcing 100 steps would burn a
      // hundred times the work for an identical answer.
      settings: mc.copyWith(steps: 1),
    ),

    AdvancedInstrument.heston => HestonPricingJob(
      type: settings.optionType,
      params: settings.heston,
      spot: env.spot,
      strike: settings.strike,
      rate: env.rate,
      timeToExpiry: env.timeToExpiry,
      settings: mc,
    ),

    AdvancedInstrument.structured => null,
  };
});

/// The members of a demonstration basket.
///
/// Deliberately generic ("Asset A"): naming real companies in a teaching tool
/// would imply a view about them, which this app does not have and must not
/// appear to (CLAUDE.md rule 1). Volatilities are spread out so that
/// diversification has something visible to do.
List<BasketAsset> _basketAssets(MarketEnvironment env, int size) {
  const List<String> names = <String>[
    'Asset A',
    'Asset B',
    'Asset C',
    'Asset D',
  ];
  const List<double> volatilityScale = <double>[0.85, 1.2, 1.0, 1.35];

  return <BasketAsset>[
    for (int i = 0; i < size; i++)
      BasketAsset(
        spot: env.spot,
        volatility: env.volatility * volatilityScale[i],
        weight: 1,
        name: names[i],
      ),
  ];
}

/// ── Running ──────────────────────────────────────────────────────────────

/// Sends very large runs to `price-heavy` when a signed-in backend exists.
///
/// Without one this is the unavailable stand-in, and every job runs on the
/// device — which is slower for the biggest runs and otherwise identical.
final Provider<RemotePricingClient> remotePricingClientProvider =
    Provider<RemotePricingClient>((Ref ref) {
      final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return const UnavailableRemotePricingClient();
      return SupabasePricingClient(client);
    });

final Provider<AdvancedPricer> advancedPricerProvider = Provider<AdvancedPricer>(
  (Ref ref) => AdvancedPricer(remote: ref.watch(remotePricingClientProvider)),
);

/// The most recent run, or null before the first one.
///
/// Runs are triggered by a button rather than recomputed on every slider
/// tick, unlike the Phase 4 tabs. That is not laziness: a Monte Carlo run
/// takes seconds, and starting a fresh one on every pixel of slider movement
/// would queue up dozens of stale jobs and heat the phone. Making the run
/// explicit also makes its COST visible, which is itself part of what these
/// models teach.
class AdvancedRunController extends AsyncNotifier<PricingRun?> {
  @override
  Future<PricingRun?> build() async => null;

  Future<void> run() async {
    final PricingJob? job = ref.read(advancedJobProvider);
    if (job == null) return;

    state = const AsyncValue<PricingRun?>.loading();
    state = await AsyncValue.guard<PricingRun?>(
      () => ref.read(advancedPricerProvider).price(job),
    );
  }

  /// Clears the result — used when the inputs change, so a number from the
  /// previous set of inputs is never left on screen looking current.
  void clear() => state = const AsyncValue<PricingRun?>.data(null);
}

final AsyncNotifierProvider<AdvancedRunController, PricingRun?>
advancedRunProvider =
    AsyncNotifierProvider<AdvancedRunController, PricingRun?>(
      AdvancedRunController.new,
    );

/// The structured product currently selected, valued under the shared market.
final Provider<StructuredValuation> structuredValuationProvider =
    Provider<StructuredValuation>((Ref ref) {
      final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
      final AdvancedSettings settings = ref.watch(advancedSettingsProvider);

      return settings.product.build().value(
        ProductMarket(
          spot: env.spot,
          volatility: env.volatility,
          rate: env.rate,
          // A structured product's economics turn on the dividends the issuer
          // keeps, so a demonstration with none would hide the point. 2% is a
          // plausible broad-equity yield.
          dividendYield: 0.02,
        ),
      );
    });
