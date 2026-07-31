/// A heavy pricing request as a plain, serialisable value (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHY JOBS ARE DATA. A Monte Carlo run has to be able to leave the widget
/// that asked for it — onto a background isolate so the UI keeps animating,
/// and for very large runs off the device entirely to a Supabase Edge Function
/// (DEPLOY.md 1d, `price-heavy`). Neither boundary can carry a closure. So a
/// job is a value that can be turned into JSON and back, and
/// [runPricingJobJson] is a top-level function with no captured state, which
/// is what an isolate entry point must be.
///
/// ONE SERIALISATION, EXERCISED CONSTANTLY. The isolate path could have sent
/// Dart objects directly — Dart can copy most objects between isolates — and
/// deliberately does not. Sending JSON means the same encode/decode the
/// remote path depends on runs on every single on-device job, so it cannot
/// quietly rot while nobody is looking at the server route. A serialisation
/// bug shows up immediately on the common path instead of the rare one.
///
/// WHAT COMES BACK. [PricingJobResult] carries the estimate, its standard
/// error, and — where the contract also has a closed form — the exact price
/// beside it. Showing both is the point: a learner who watches a simulation
/// land on the formula's answer has been given a reason to trust it on the
/// contracts where no formula exists.
library;

import 'barrier.dart';
import 'basket.dart';
import 'black_scholes.dart';
import 'heston.dart';
import 'monte_carlo.dart';

/// Thrown when a job cannot be decoded — a malformed payload from the network,
/// or a version of the app sending something this build does not know about.
class PricingJobFormatException implements Exception {
  const PricingJobFormatException(this.message);

  final String message;

  @override
  String toString() => 'PricingJobFormatException: $message';
}

/// A pricing request that can cross an isolate or network boundary.
sealed class PricingJob {
  const PricingJob({required this.settings});

  final McSettings settings;

  /// Discriminator written into the JSON so the payload can be decoded
  /// without guessing.
  String get kind;

  /// Human-readable name of the contract being priced.
  String get label;

  /// Roughly how many random draws this will consume. The UI uses it to
  /// decide between running inline, on an isolate, or on a server.
  int get workload => settings.workload;

  Map<String, dynamic> toJson();

  /// Rebuilds a job from a decoded JSON map.
  static PricingJob fromJson(Map<String, dynamic> json) {
    final Object? kind = json['kind'];
    return switch (kind) {
      'barrier' => BarrierPricingJob.fromJson(json),
      'basket' => BasketPricingJob.fromJson(json),
      'asian' => AsianPricingJob.fromJson(json),
      'heston' => HestonPricingJob.fromJson(json),
      'european' => EuropeanPricingJob.fromJson(json),
      _ => throw PricingJobFormatException('Unknown job kind "$kind".'),
    };
  }
}

/// The answer, with its uncertainty attached.
class PricingJobResult {
  const PricingJobResult({
    required this.price,
    required this.standardError,
    required this.paths,
    this.analyticReference,
    this.notes = const <String>[],
  });

  /// The simulated price.
  final double price;

  /// Standard error of that estimate. Zero when the answer was settled
  /// without simulation (a barrier already breached, say).
  final double standardError;

  /// Independent observations the error was computed from.
  final int paths;

  /// The exact price where the contract has a closed form, for comparison.
  /// Null where none exists — which is most of the interesting cases, and is
  /// precisely why the simulation is there.
  final double? analyticReference;

  /// Caveats specific to this run: a discretisation bias, a barrier watched
  /// discretely, a parameter outside its reliable range. Shown to the learner
  /// rather than kept in a comment.
  final List<String> notes;

  (double, double) get confidenceInterval95 => (
    price - 1.96 * standardError,
    price + 1.96 * standardError,
  );

  /// How far the simulation landed from the exact answer, in units of its own
  /// standard error. Null when there is no exact answer to compare with.
  ///
  /// A value comfortably under 3 means the simulation is behaving. A large
  /// one means something is biased — which is worth surfacing, because it is
  /// the failure a confidence interval alone will not reveal.
  double? get referenceDeviationInErrors {
    final double? reference = analyticReference;
    if (reference == null || standardError <= 0) return null;
    return (price - reference).abs() / standardError;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'price': price,
    'standard_error': standardError,
    'paths': paths,
    if (analyticReference != null) 'analytic_reference': analyticReference,
    'notes': notes,
  };

  factory PricingJobResult.fromJson(Map<String, dynamic> json) =>
      PricingJobResult(
        price: _double(json, 'price'),
        standardError: _double(json, 'standard_error'),
        paths: _int(json, 'paths'),
        analyticReference: json['analytic_reference'] == null
            ? null
            : _double(json, 'analytic_reference'),
        notes: <String>[
          for (final Object? note in (json['notes'] as List<Object?>?) ??
              const <Object?>[])
            note.toString(),
        ],
      );
}

/// ── Job types ────────────────────────────────────────────────────────────

/// A European option, priced by simulation.
///
/// Redundant by design — `bsmQuote` answers it exactly and instantly. It is
/// offered anyway because putting the simulated price next to the exact one
/// is the clearest demonstration in the app of what a Monte Carlo estimate is
/// and is not.
class EuropeanPricingJob extends PricingJob {
  const EuropeanPricingJob({
    required this.type,
    required this.inputs,
    super.settings = const McSettings(steps: 1),
  });

  final OptionType type;
  final BsmInputs inputs;

  @override
  String get kind => 'european';

  @override
  String get label =>
      'European ${type == OptionType.call ? 'call' : 'put'}, strike '
      '${inputs.strike.toStringAsFixed(0)}';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'type': type.name,
    'inputs': _inputsToJson(inputs),
    'settings': _settingsToJson(settings),
  };

  factory EuropeanPricingJob.fromJson(Map<String, dynamic> json) =>
      EuropeanPricingJob(
        type: _optionType(json['type']),
        inputs: _inputsFromJson(_map(json, 'inputs')),
        settings: _settingsFromJson(_map(json, 'settings')),
      );
}

/// A barrier option, priced by simulation with the barrier watched at each
/// step.
class BarrierPricingJob extends PricingJob {
  const BarrierPricingJob({
    required this.spec,
    required this.inputs,
    this.continuityCorrection = false,
    super.settings = const McSettings(),
  });

  final BarrierSpec spec;
  final BsmInputs inputs;

  /// Price the idealised CONTINUOUSLY monitored contract instead of the
  /// discretely monitored one the simulation naturally produces.
  final bool continuityCorrection;

  @override
  String get kind => 'barrier';

  @override
  String get label =>
      '${spec.label}, strike ${inputs.strike.toStringAsFixed(0)}, barrier '
      '${spec.barrier.toStringAsFixed(0)}';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'option_type': spec.type.name,
    'direction': spec.direction.name,
    'style': spec.style.name,
    'barrier': spec.barrier,
    'continuity_correction': continuityCorrection,
    'inputs': _inputsToJson(inputs),
    'settings': _settingsToJson(settings),
  };

  factory BarrierPricingJob.fromJson(Map<String, dynamic> json) =>
      BarrierPricingJob(
        spec: BarrierSpec(
          type: _optionType(json['option_type']),
          direction: _enumByName(
            BarrierDirection.values,
            json['direction'],
            'direction',
          ),
          style: _enumByName(BarrierStyle.values, json['style'], 'style'),
          barrier: _double(json, 'barrier'),
        ),
        continuityCorrection: json['continuity_correction'] == true,
        inputs: _inputsFromJson(_map(json, 'inputs')),
        settings: _settingsFromJson(_map(json, 'settings')),
      );
}

/// An average-price (Asian) option.
class AsianPricingJob extends PricingJob {
  const AsianPricingJob({
    required this.type,
    required this.inputs,
    this.average = AsianAverage.arithmetic,
    super.settings = const McSettings(),
  });

  final OptionType type;
  final BsmInputs inputs;
  final AsianAverage average;

  @override
  String get kind => 'asian';

  @override
  String get label =>
      'Asian ${type == OptionType.call ? 'call' : 'put'}, strike '
      '${inputs.strike.toStringAsFixed(0)}';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'type': type.name,
    'average': average.name,
    'inputs': _inputsToJson(inputs),
    'settings': _settingsToJson(settings),
  };

  factory AsianPricingJob.fromJson(Map<String, dynamic> json) =>
      AsianPricingJob(
        type: _optionType(json['type']),
        average: _enumByName(AsianAverage.values, json['average'], 'average'),
        inputs: _inputsFromJson(_map(json, 'inputs')),
        settings: _settingsFromJson(_map(json, 'settings')),
      );
}

/// An option on a weighted blend of several correlated underlyings.
class BasketPricingJob extends PricingJob {
  const BasketPricingJob({
    required this.spec,
    super.settings = const McSettings(steps: 1),
  });

  final BasketSpec spec;

  @override
  String get kind => 'basket';

  @override
  String get label =>
      '${spec.size}-asset basket '
      '${spec.type == OptionType.call ? 'call' : 'put'}, strike '
      '${spec.strike.toStringAsFixed(0)}';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'assets': <Map<String, dynamic>>[
      for (final BasketAsset a in spec.assets)
        <String, dynamic>{
          'spot': a.spot,
          'volatility': a.volatility,
          'weight': a.weight,
          'dividend_yield': a.dividendYield,
          'name': a.name,
        },
    ],
    'correlation': spec.correlation,
    'strike': spec.strike,
    'type': spec.type.name,
    'rate': spec.rate,
    'time_to_expiry': spec.timeToExpiry,
    'average': spec.average.name,
    'settings': _settingsToJson(settings),
  };

  factory BasketPricingJob.fromJson(Map<String, dynamic> json) {
    final List<Object?> rawAssets = _list(json, 'assets');
    final List<Object?> rawCorrelation = _list(json, 'correlation');

    return BasketPricingJob(
      spec: BasketSpec(
        assets: <BasketAsset>[
          for (final Object? raw in rawAssets)
            () {
              final Map<String, dynamic> a = _asMap(raw, 'asset');
              return BasketAsset(
                spot: _double(a, 'spot'),
                volatility: _double(a, 'volatility'),
                weight: _double(a, 'weight'),
                dividendYield: a['dividend_yield'] == null
                    ? 0
                    : _double(a, 'dividend_yield'),
                name: a['name']?.toString() ?? '',
              );
            }(),
        ],
        correlation: <List<double>>[
          for (final Object? row in rawCorrelation)
            <double>[
              for (final Object? cell in _asList(row, 'correlation row'))
                _toDouble(cell, 'correlation cell'),
            ],
        ],
        strike: _double(json, 'strike'),
        type: _optionType(json['type']),
        rate: _double(json, 'rate'),
        timeToExpiry: _double(json, 'time_to_expiry'),
        average: _enumByName(BasketAverage.values, json['average'], 'average'),
      ),
      settings: _settingsFromJson(_map(json, 'settings')),
    );
  }
}

/// An option under stochastic volatility.
class HestonPricingJob extends PricingJob {
  const HestonPricingJob({
    required this.type,
    required this.params,
    required this.spot,
    required this.strike,
    required this.rate,
    required this.timeToExpiry,
    this.dividendYield = 0,
    this.payoff = HestonPayoff.european,
    super.settings = const McSettings(),
  });

  final OptionType type;
  final HestonParams params;
  final double spot;
  final double strike;
  final double rate;
  final double timeToExpiry;
  final double dividendYield;
  final HestonPayoff payoff;

  @override
  String get kind => 'heston';

  @override
  String get label =>
      'Heston ${payoff == HestonPayoff.asianArithmetic ? 'Asian ' : ''}'
      '${type == OptionType.call ? 'call' : 'put'}, strike '
      '${strike.toStringAsFixed(0)}';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'type': type.name,
    'payoff': payoff.name,
    'params': <String, dynamic>{
      'initial_variance': params.initialVariance,
      'long_run_variance': params.longRunVariance,
      'mean_reversion': params.meanReversion,
      'vol_of_vol': params.volOfVol,
      'correlation': params.correlation,
    },
    'spot': spot,
    'strike': strike,
    'rate': rate,
    'time_to_expiry': timeToExpiry,
    'dividend_yield': dividendYield,
    'settings': _settingsToJson(settings),
  };

  factory HestonPricingJob.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> p = _map(json, 'params');
    return HestonPricingJob(
      type: _optionType(json['type']),
      payoff: _enumByName(HestonPayoff.values, json['payoff'], 'payoff'),
      params: HestonParams(
        initialVariance: _double(p, 'initial_variance'),
        longRunVariance: _double(p, 'long_run_variance'),
        meanReversion: _double(p, 'mean_reversion'),
        volOfVol: _double(p, 'vol_of_vol'),
        correlation: _double(p, 'correlation'),
      ),
      spot: _double(json, 'spot'),
      strike: _double(json, 'strike'),
      rate: _double(json, 'rate'),
      timeToExpiry: _double(json, 'time_to_expiry'),
      dividendYield: json['dividend_yield'] == null
          ? 0
          : _double(json, 'dividend_yield'),
      settings: _settingsFromJson(_map(json, 'settings')),
    );
  }
}

/// ── Execution ────────────────────────────────────────────────────────────

/// Runs the SIMULATION for [job] — the expensive part, and the only part a
/// server would ever be asked to do.
///
/// Split out from [runPricingJob] deliberately. The `price-heavy` Edge
/// Function (DEPLOY.md 1d) is a second implementation of this engine in
/// another language, and every line it has to reimplement is a line that can
/// silently disagree with this one. Closed forms and caveats are instant to
/// compute, so they stay on the client and the server reimplements only what
/// is genuinely heavy: the paths.
McEstimate simulatePricingJob(PricingJob job) => switch (job) {
  EuropeanPricingJob(:final OptionType type, :final BsmInputs inputs) =>
    europeanMonteCarloPrice(type, inputs, settings: job.settings),

  BarrierPricingJob(:final BarrierSpec spec, :final BsmInputs inputs) =>
    barrierMonteCarloPrice(
      spec,
      inputs,
      settings: job.settings,
      continuityCorrection: job.continuityCorrection,
    ),

  AsianPricingJob(:final OptionType type, :final BsmInputs inputs) =>
    asianMonteCarloPrice(
      type,
      inputs,
      settings: job.settings,
      average: job.average,
    ),

  BasketPricingJob(:final BasketSpec spec) =>
    basketMonteCarloPrice(spec, settings: job.settings),

  HestonPricingJob(:final OptionType type, :final HestonParams params) =>
    hestonMonteCarloPrice(
      type,
      params: params,
      spot: job.spot,
      strike: job.strike,
      rate: job.rate,
      timeToExpiry: job.timeToExpiry,
      dividendYield: job.dividendYield,
      payoff: job.payoff,
      settings: job.settings,
    ),
};

/// The exact price of [job]'s contract, where one exists.
///
/// Null for the contracts that have no formula — which is most of the
/// interesting ones, and precisely why the simulation exists. Never a
/// substitute or an approximation dressed up as an answer: a "close enough"
/// reference sitting beside a simulated price would teach the learner to
/// distrust the wrong one of the two.
double? analyticReferenceFor(PricingJob job) => switch (job) {
  EuropeanPricingJob(:final OptionType type, :final BsmInputs inputs) =>
    bsmQuote(type, inputs).price,

  BarrierPricingJob(:final BarrierSpec spec, :final BsmInputs inputs) =>
    barrierPrice(spec, inputs),

  // An arithmetic average has no closed form. That IS the reason it is
  // simulated, so offering the vanilla price here as a stand-in would
  // misrepresent a different contract as the answer.
  AsianPricingJob() => null,

  // Exact for a geometric blend; for the arithmetic one it is only a lower
  // bound, so it is not reported as the answer.
  BasketPricingJob(:final BasketSpec spec) =>
    spec.average == BasketAverage.geometric
        ? geometricBasketPrice(spec)
        : null,

  HestonPricingJob(:final OptionType type, :final HestonParams params) =>
    job.payoff == HestonPayoff.european
        ? hestonVanillaPrice(
            type,
            params: params,
            spot: job.spot,
            strike: job.strike,
            rate: job.rate,
            timeToExpiry: job.timeToExpiry,
            dividendYield: job.dividendYield,
          )
        : null,
};

/// What this particular run does NOT tell the learner.
///
/// Every note here is a limitation that the price and its error bar together
/// still fail to convey — a discretisation bias, a barrier watched at
/// intervals, a parameter outside its reliable range. Attached to the result
/// rather than left in a source comment, because the person who needs them is
/// the one reading the number (CLAUDE.md rules 4 and 5).
List<String> notesFor(PricingJob job) => switch (job) {
  EuropeanPricingJob() => const <String>[
    'A European option has an exact formula, so this simulation is a '
        'demonstration rather than a necessity. The two should agree to '
        'within the error shown.',
  ],

  BarrierPricingJob(:final BarrierSpec spec, :final BsmInputs inputs) =>
    <String>[
      if (job.continuityCorrection)
        'Corrected towards a continuously monitored barrier '
            '(Broadie-Glasserman-Kou), so it is comparable with the closed '
            'form. The correction is itself an approximation.'
      else
        'The barrier is watched at ${job.settings.steps} dates, not '
            'continuously. A discretely watched knock-out survives more '
            'often and is therefore worth more than the closed form beside '
            'it — that gap is real, not an error.',
      if (spec.alreadyTriggered(inputs.spot))
        'The spot is already past the barrier, so the outcome is settled '
            'and there was nothing to simulate.',
    ],

  AsianPricingJob() => <String>[
    'An arithmetic average has no closed-form price, which is why this is '
        'simulated. The average is taken over ${job.settings.steps} dates.',
    'Averaging damps the extremes, so an Asian option is worth less than '
        'the otherwise identical European one.',
  ],

  BasketPricingJob(:final BasketSpec spec) => <String>[
    if (spec.average == BasketAverage.arithmetic)
      'An arithmetic basket has no closed-form price. The geometric '
          'version does, and is always slightly cheaper — a useful lower '
          'bound but not this contract.',
    'Correlation is the least stable input here. It is estimated from '
        'history, it moves, and it tends towards 1 in a crash — exactly '
        'when a diversified basket is being relied on.',
  ],

  HestonPricingJob(:final HestonParams params) => <String>[
    'Simulated with a full-truncation Euler scheme, which carries a '
        'discretisation bias ON TOP of the sampling error. The error bar '
        'does not describe that bias; more steps are what reduce it.',
    if (!params.satisfiesFeller)
      'These parameters violate the Feller condition, so variance can '
          'reach zero. That is common in real calibrations, but it makes '
          'the simulation less accurate at a given number of steps.',
    if (params.volOfVol < HestonParams.minimumUsableVolOfVol)
      'Vol-of-vol is below the range where the semi-analytic price stays '
          'accurate, so the reference beside this number is unreliable.',
  ],
};

/// Runs a job in full: simulate, then attach the exact answer and the
/// caveats.
PricingJobResult runPricingJob(PricingJob job) =>
    describeSimulation(job, simulatePricingJob(job));

/// Wraps an estimate — from here or from the server — with the exact answer
/// and the caveats for [job].
///
/// This is what lets the Edge Function return three numbers and nothing else:
/// whatever produced the estimate, the honesty is added on the client, so it
/// can never be missing because a server was an older version.
PricingJobResult describeSimulation(PricingJob job, McEstimate estimate) =>
    PricingJobResult(
      price: estimate.price,
      standardError: estimate.standardError,
      paths: estimate.paths,
      analyticReference: analyticReferenceFor(job),
      notes: notesFor(job),
    );

/// The isolate entry point.
///
/// Top-level and free of captured state, which is what `compute()` requires.
/// It takes and returns JSON so the identical payload can be posted to the
/// `price-heavy` Edge Function without a second code path.
Map<String, dynamic> runPricingJobJson(Map<String, dynamic> json) =>
    runPricingJob(PricingJob.fromJson(json)).toJson();

/// ── JSON helpers ─────────────────────────────────────────────────────────
///
/// Deliberately strict. A silently-defaulted input would turn a malformed
/// payload into a plausible-looking price, which is the worst possible
/// failure for a pricing tool: wrong, and confident.

Map<String, dynamic> _settingsToJson(McSettings s) => <String, dynamic>{
  'paths': s.paths,
  'steps': s.steps,
  'seed': s.seed,
  'antithetic': s.antithetic,
};

McSettings _settingsFromJson(Map<String, dynamic> json) => McSettings(
  paths: _int(json, 'paths'),
  steps: _int(json, 'steps'),
  seed: _int(json, 'seed'),
  antithetic: json['antithetic'] != false,
);

Map<String, dynamic> _inputsToJson(BsmInputs i) => <String, dynamic>{
  'spot': i.spot,
  'strike': i.strike,
  'rate': i.rate,
  'volatility': i.volatility,
  'time_to_expiry': i.timeToExpiry,
  'dividend_yield': i.dividendYield,
};

BsmInputs _inputsFromJson(Map<String, dynamic> json) => BsmInputs(
  spot: _double(json, 'spot'),
  strike: _double(json, 'strike'),
  rate: _double(json, 'rate'),
  volatility: _double(json, 'volatility'),
  timeToExpiry: _double(json, 'time_to_expiry'),
  dividendYield: json['dividend_yield'] == null
      ? 0
      : _double(json, 'dividend_yield'),
);

OptionType _optionType(Object? raw) =>
    _enumByName(OptionType.values, raw, 'option type');

T _enumByName<T extends Enum>(List<T> values, Object? raw, String what) {
  for (final T value in values) {
    if (value.name == raw) return value;
  }
  throw PricingJobFormatException('Unknown $what "$raw".');
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) =>
    _asMap(json[key], key);

Map<String, dynamic> _asMap(Object? raw, String what) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  throw PricingJobFormatException('Expected an object for "$what".');
}

List<Object?> _list(Map<String, dynamic> json, String key) =>
    _asList(json[key], key);

List<Object?> _asList(Object? raw, String what) {
  if (raw is List) return raw;
  throw PricingJobFormatException('Expected a list for "$what".');
}

double _double(Map<String, dynamic> json, String key) =>
    _toDouble(json[key], key);

double _toDouble(Object? raw, String what) {
  if (raw is num) {
    final double value = raw.toDouble();
    if (value.isNaN || value.isInfinite) {
      throw PricingJobFormatException('"$what" is not a finite number.');
    }
    return value;
  }
  throw PricingJobFormatException('Expected a number for "$what".');
}

int _int(Map<String, dynamic> json, String key) {
  final Object? raw = json[key];
  if (raw is int) return raw;
  if (raw is num && raw == raw.roundToDouble()) return raw.toInt();
  throw PricingJobFormatException('Expected a whole number for "$key".');
}
