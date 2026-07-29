import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/payoff_diagram.dart';
import '../../../pricing/payoff.dart';
import '../../../pricing/priced_leg.dart';
import '../../../providers/sandbox_tutorial_controller.dart';

/// A full-screen, step-by-step walkthrough of the Sandbox, shown the first
/// time a learner opens it and reachable again from the app bar's help icon.
///
/// Each step animates ONE market input across a demonstrative range on a
/// self-contained payoff graph — not the real Sandbox state, so playing
/// through the walkthrough never leaves a learner's actual sliders moved
/// when they land back on the real screen.
class SandboxTutorial extends ConsumerStatefulWidget {
  const SandboxTutorial({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const SandboxTutorial(),
      ),
    );
  }

  @override
  ConsumerState<SandboxTutorial> createState() => _SandboxTutorialState();
}

/// Baseline demo scenario every step resets to before animating its own
/// field — a $100 spot and strike, so the marker sits right at the money
/// and the curve's kink is centred on screen.
const double _baseSpot = 100;
const double _baseStrike = 100;
const double _baseVolatility = 0.25;
const double _baseTimeToExpiry = 0.5;
const double _baseRate = 0.04;

enum _Field { spot, volatility, timeToExpiry, rate, none }

class _Step {
  const _Step({
    required this.heading,
    required this.body,
    required this.field,
    this.from = 0,
    this.to = 0,
  });

  final String heading;
  final String body;
  final _Field field;
  final double from;
  final double to;
}

const List<_Step> _steps = <_Step>[
  _Step(
    heading: 'Meet the payoff graph',
    body:
        'This is the payoff graph — profit or loss at expiry against where the '
        "underlying finishes. The marker tracks today's spot price. Watch it "
        'slide as the spot price sweeps from deep out of the money to deep in '
        'the money.',
    field: _Field.spot,
    from: 70,
    to: 130,
  ),
  _Step(
    heading: 'Volatility',
    body:
        "Raise volatility and the option's live premium rises with it — the "
        'whole curve shifts down, because a pricier option needs the '
        'underlying to move further before the position is ahead.',
    field: _Field.volatility,
    from: 0.10,
    to: 0.70,
  ),
  _Step(
    heading: 'Time to expiry',
    body:
        'As time to expiry shrinks toward zero, the premium bleeds away toward '
        'pure intrinsic value — the curve tightens into the sharp kink from '
        'the Payoff at Expiry lesson.',
    field: _Field.timeToExpiry,
    from: 1.5,
    to: 0.02,
  ),
  _Step(
    heading: 'Risk-free rate',
    body:
        'The risk-free rate has a smaller, subtler effect here — it nudges '
        'the premium through the discounted cost of paying the strike.',
    field: _Field.rate,
    from: -0.01,
    to: 0.08,
  ),
  _Step(
    heading: 'Beyond one leg',
    body:
        'The Strategy tab combines legs like this one into named strategies — '
        'spreads, a straddle, a covered call, a protective put. It unlocks '
        'once you finish the Strategies lesson in Learn, so the presets make '
        'sense when you get there.',
    field: _Field.none,
  ),
];

class _SandboxTutorialState extends ConsumerState<SandboxTutorial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  int _stepIndex = 0;
  double _spot = _baseSpot;
  double _volatility = _baseVolatility;
  double _timeToExpiry = _baseTimeToExpiry;
  double _rate = _baseRate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addListener(_onTick);
    // Field initialisers already sit at baseline for step 0, so this only
    // needs to start the animation — no setState during initState.
    if (_steps[0].field != _Field.none) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _Step get _step => _steps[_stepIndex];

  void _onTick() {
    final _Step step = _step;
    if (step.field == _Field.none) return;

    final double t = Curves.easeInOut.transform(_controller.value);
    final double value = step.from + (step.to - step.from) * t;

    setState(() {
      switch (step.field) {
        case _Field.spot:
          _spot = value;
        case _Field.volatility:
          _volatility = value;
        case _Field.timeToExpiry:
          _timeToExpiry = value;
        case _Field.rate:
          _rate = value;
        case _Field.none:
          break;
      }
    });
  }

  void _playStep(int index) {
    setState(() {
      _stepIndex = index;
      _spot = _baseSpot;
      _volatility = _baseVolatility;
      _timeToExpiry = _baseTimeToExpiry;
      _rate = _baseRate;
    });
    if (_steps[index].field != _Field.none) {
      _controller.forward(from: 0);
    }
  }

  void _next() {
    if (_stepIndex == _steps.length - 1) {
      _finish();
      return;
    }
    _playStep(_stepIndex + 1);
  }

  void _back() {
    if (_stepIndex == 0) return;
    _playStep(_stepIndex - 1);
  }

  void _finish() {
    ref.read(sandboxTutorialSeenProvider.notifier).markSeen();
    Navigator.of(context).pop();
  }

  List<StrategyLeg> get _legs {
    final _Step step = _step;
    if (step.field == _Field.none) {
      // The closing step previews a straddle, at the resting baseline —
      // nothing animates here, this is purely "here's what's coming".
      const MarketEnvironment env = MarketEnvironment(
        spot: _baseSpot,
        volatility: _baseVolatility,
        timeToExpiry: _baseTimeToExpiry,
        rate: _baseRate,
      );
      return <StrategyLeg>[
        pricedLeg(env, kind: LegKind.call, side: LegSide.long, strike: _baseStrike),
        pricedLeg(env, kind: LegKind.put, side: LegSide.long, strike: _baseStrike),
      ];
    }

    final MarketEnvironment env = MarketEnvironment(
      spot: _spot,
      volatility: _volatility,
      timeToExpiry: _timeToExpiry,
      rate: _rate,
    );
    return <StrategyLeg>[
      pricedLeg(env, kind: LegKind.call, side: LegSide.long, strike: _baseStrike),
    ];
  }

  /// The marker only tracks spot while spot itself is the thing animating —
  /// on every other step it sits still at the baseline, so the curve's own
  /// vertical shift is the only thing moving.
  double get _markerSpot => _step.field == _Field.spot ? _spot : _baseSpot;

  String? get _activeValueLabel => switch (_step.field) {
    _Field.spot => 'Spot: \$${_spot.toStringAsFixed(0)}',
    _Field.volatility => 'Volatility: ${(_volatility * 100).toStringAsFixed(0)}%',
    _Field.timeToExpiry => 'Time to expiry: ${_formatYears(_timeToExpiry)}',
    _Field.rate => 'Risk-free rate: ${(_rate * 100).toStringAsFixed(2)}%',
    _Field.none => null,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _Step step = _step;
    final bool isLast = _stepIndex == _steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sandbox walkthrough'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: _finish,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text('Payoff at expiry', style: theme.textTheme.titleMedium),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Replay',
                            icon: const Icon(Icons.replay, size: 20),
                            onPressed: () => _playStep(_stepIndex),
                          ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _activeValueLabel == null
                            ? const SizedBox(height: 4)
                            : Padding(
                                key: ValueKey<String>(_activeValueLabel!),
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  _activeValueLabel!,
                                  style: theme.textTheme.numeric.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      PayoffDiagram(
                        legs: _legs,
                        spotMin: 60,
                        spotMax: 140,
                        markerSpot: _markerSpot,
                        animate: false,
                        height: 190,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                      key: ValueKey<int>(_stepIndex),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(step.heading, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 10),
                        Text(
                          step.body,
                          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < _steps.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _stepIndex ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _stepIndex
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  if (_stepIndex > 0)
                    Expanded(
                      child: OutlinedButton(onPressed: _back, child: const Text('Back')),
                    ),
                  if (_stepIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(isLast ? 'Got it' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `0.5` -> `'6.0 months'`, `1.5` -> `'1.50 yr'`.
String _formatYears(double years) {
  if (years < 1) return '${(years * 12).toStringAsFixed(1)} months';
  return '${years.toStringAsFixed(2)} yr';
}
