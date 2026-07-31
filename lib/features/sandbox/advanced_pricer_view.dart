import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/disclaimer_text.dart';
import '../../pricing/barrier.dart';
import '../../pricing/black_scholes.dart';
import '../../pricing/heston.dart';
import '../../pricing/monte_carlo.dart';
import '../../pricing/priced_leg.dart';
import '../../pricing/pricing_job.dart';
import '../../providers/advanced_pricer_providers.dart';
import '../../providers/pricer_providers.dart';
import '../../services/advanced_pricer.dart';
import 'widgets/market_inputs_panel.dart';
import 'widgets/pricer_slider.dart';
import 'widgets/simulation_distribution_chart.dart';
import 'widgets/simulation_result_card.dart';
import 'widgets/structured_product_panel.dart';

/// The Phase 8 "Advanced" tab: options that cannot be priced with a formula.
///
/// WHY THERE IS A BUTTON HERE and not on the other two tabs. The simple
/// pricer recomputes on every slider tick because Black-Scholes takes
/// microseconds. A Monte Carlo run takes seconds, so recomputing live would
/// queue stale jobs and heat the phone. Making the run explicit also makes its
/// COST visible — that some prices are cheap to know and others expensive is
/// itself one of the things this tab teaches.
class AdvancedPricerView extends ConsumerWidget {
  const AdvancedPricerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AdvancedInstrument instrument = ref.watch(advancedInstrumentProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        _InstrumentSelector(instrument: instrument),
        const SizedBox(height: 12),
        Text(
          instrument.blurb,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: 16),

        if (instrument == AdvancedInstrument.structured) ...<Widget>[
          const MarketInputsPanel(),
          const SizedBox(height: 12),
          const StructuredProductPanel(),
        ] else ...<Widget>[
          // Results first: the run button and its outcome sit at the top, with
          // the contract and effort controls to tweak below. Changing any of
          // those clears the run, so the outcome up here never looks stale.
          const _RunButton(),
          const SizedBox(height: 16),
          const _RunOutcome(),
          const SizedBox(height: 20),
          const MarketInputsPanel(),
          const SizedBox(height: 12),
          _ContractPanel(instrument: instrument),
          const SizedBox(height: 12),
          const _EffortPanel(),
        ],

        const SizedBox(height: 20),
        const DisclaimerBanner(),
        const SizedBox(height: 10),
        const DisclaimerBanner(
          text: Disclaimers.modelAssumptions,
          icon: Icons.functions_outlined,
        ),
      ],
    );
  }
}

class _InstrumentSelector extends ConsumerWidget {
  const _InstrumentSelector({required this.instrument});

  final AdvancedInstrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<AdvancedInstrument>(
        segments: <ButtonSegment<AdvancedInstrument>>[
          for (final AdvancedInstrument option in AdvancedInstrument.values)
            ButtonSegment<AdvancedInstrument>(
              value: option,
              label: Text(option.label),
            ),
        ],
        selected: <AdvancedInstrument>{instrument},
        showSelectedIcon: false,
        onSelectionChanged: (Set<AdvancedInstrument> selection) {
          ref
              .read(advancedInstrumentProvider.notifier)
              .select(selection.first);
          // A result from the previous instrument must not linger looking
          // current.
          ref.read(advancedRunProvider.notifier).clear();
        },
      ),
    );
  }
}

/// The contract's own terms — strike, barrier, correlation, Heston
/// parameters.
class _ContractPanel extends ConsumerWidget {
  const _ContractPanel({required this.instrument});

  final AdvancedInstrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AdvancedSettings settings = ref.watch(advancedSettingsProvider);
    final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
    final AdvancedSettingsController controller = ref.read(
      advancedSettingsProvider.notifier,
    );

    void change(AdvancedSettings Function(AdvancedSettings) update) {
      controller.update(update);
      ref.read(advancedRunProvider.notifier).clear();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'THE CONTRACT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),

            SegmentedButton<OptionType>(
              segments: const <ButtonSegment<OptionType>>[
                ButtonSegment<OptionType>(
                  value: OptionType.call,
                  label: Text('Call'),
                ),
                ButtonSegment<OptionType>(
                  value: OptionType.put,
                  label: Text('Put'),
                ),
              ],
              selected: <OptionType>{settings.optionType},
              showSelectedIcon: false,
              onSelectionChanged: (Set<OptionType> s) =>
                  change((AdvancedSettings v) => v.copyWith(optionType: s.first)),
            ),
            const SizedBox(height: 12),

            PricerSlider(
              label: 'Strike',
              value: settings.strike,
              min: 20,
              max: 200,
              divisions: 180,
              valueLabel: r'$' '${settings.strike.toStringAsFixed(0)}',
              onChanged: (double v) =>
                  change((AdvancedSettings s) => s.copyWith(strike: v)),
            ),

            if (instrument == AdvancedInstrument.barrier)
              ..._barrierControls(context, ref, settings, env, change),
            if (instrument == AdvancedInstrument.asian)
              ..._asianControls(context, settings, change),
            if (instrument == AdvancedInstrument.basket)
              ..._basketControls(context, settings, change),
            if (instrument == AdvancedInstrument.heston)
              ..._hestonControls(context, settings, change),
          ],
        ),
      ),
    );
  }

  List<Widget> _barrierControls(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettings settings,
    MarketEnvironment env,
    void Function(AdvancedSettings Function(AdvancedSettings)) change,
  ) {
    final ThemeData theme = Theme.of(context);
    final double level = env.spot * settings.barrierRatio;
    final BarrierSpec spec = BarrierSpec(
      type: settings.optionType,
      direction: settings.barrierDirection,
      style: settings.barrierStyle,
      barrier: level,
    );

    return <Widget>[
      const SizedBox(height: 8),
      SegmentedButton<BarrierDirection>(
        segments: const <ButtonSegment<BarrierDirection>>[
          ButtonSegment<BarrierDirection>(
            value: BarrierDirection.down,
            label: Text('Down'),
          ),
          ButtonSegment<BarrierDirection>(
            value: BarrierDirection.up,
            label: Text('Up'),
          ),
        ],
        selected: <BarrierDirection>{settings.barrierDirection},
        showSelectedIcon: false,
        onSelectionChanged: (Set<BarrierDirection> s) => change(
          (AdvancedSettings v) => v.copyWith(
            barrierDirection: s.first,
            // A down barrier belongs below the spot and an up barrier above
            // it. Flipping the direction without moving the level would put
            // the contract straight into its already-triggered state, which
            // is a confusing thing to have happen by accident.
            barrierRatio: s.first == BarrierDirection.down ? 0.85 : 1.15,
          ),
        ),
      ),
      const SizedBox(height: 8),
      SegmentedButton<BarrierStyle>(
        segments: const <ButtonSegment<BarrierStyle>>[
          ButtonSegment<BarrierStyle>(
            value: BarrierStyle.knockOut,
            label: Text('Knock-out'),
          ),
          ButtonSegment<BarrierStyle>(
            value: BarrierStyle.knockIn,
            label: Text('Knock-in'),
          ),
        ],
        selected: <BarrierStyle>{settings.barrierStyle},
        showSelectedIcon: false,
        onSelectionChanged: (Set<BarrierStyle> s) =>
            change((AdvancedSettings v) => v.copyWith(barrierStyle: s.first)),
      ),
      const SizedBox(height: 12),
      PricerSlider(
        label: 'Barrier level',
        value: settings.barrierRatio,
        min: 0.5,
        max: 1.5,
        divisions: 100,
        valueLabel: r'$' '${level.toStringAsFixed(0)}',
        semanticLabel: 'Barrier level',
        onChanged: (double v) =>
            change((AdvancedSettings s) => s.copyWith(barrierRatio: v)),
      ),
      if (spec.alreadyTriggered(env.spot))
        _Inline(
          spec.style == BarrierStyle.knockOut
              ? 'The price is already past this barrier, so a knock-out is '
                    'already dead and worth nothing. Nothing needs simulating.'
              : 'The price is already past this barrier, so the knock-in has '
                    'already come alive — it is simply an ordinary option now.',
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: settings.continuityCorrection,
        title: Text(
          'Price the continuously watched contract',
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          settings.continuityCorrection
              ? 'Nudges the barrier so the simulation approximates a barrier '
                    'watched at every instant — comparable with the textbook '
                    'formula.'
              : 'The barrier is checked at each simulated date, like a real '
                    'contract monitored at daily closes.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onChanged: (bool v) => change(
          (AdvancedSettings s) => s.copyWith(continuityCorrection: v),
        ),
      ),
    ];
  }

  List<Widget> _asianControls(
    BuildContext context,
    AdvancedSettings settings,
    void Function(AdvancedSettings Function(AdvancedSettings)) change,
  ) => <Widget>[
    const SizedBox(height: 8),
    SegmentedButton<AsianAverage>(
      segments: const <ButtonSegment<AsianAverage>>[
        ButtonSegment<AsianAverage>(
          value: AsianAverage.arithmetic,
          label: Text('Arithmetic'),
        ),
        ButtonSegment<AsianAverage>(
          value: AsianAverage.geometric,
          label: Text('Geometric'),
        ),
      ],
      selected: <AsianAverage>{settings.asianAverage},
      showSelectedIcon: false,
      onSelectionChanged: (Set<AsianAverage> s) =>
          change((AdvancedSettings v) => v.copyWith(asianAverage: s.first)),
    ),
  ];

  List<Widget> _basketControls(
    BuildContext context,
    AdvancedSettings settings,
    void Function(AdvancedSettings Function(AdvancedSettings)) change,
  ) => <Widget>[
    const SizedBox(height: 8),
    PricerSlider(
      label: 'Assets in the basket',
      value: settings.basketSize.toDouble(),
      min: 2,
      max: 4,
      divisions: 2,
      valueLabel: '${settings.basketSize}',
      onChanged: (double v) => change(
        (AdvancedSettings s) => s.copyWith(basketSize: v.round()),
      ),
    ),
    PricerSlider(
      label: 'Correlation between them',
      value: settings.basketCorrelation,
      min: -0.3,
      max: 1,
      divisions: 130,
      valueLabel: settings.basketCorrelation.toStringAsFixed(2),
      onChanged: (double v) =>
          change((AdvancedSettings s) => s.copyWith(basketCorrelation: v)),
    ),
  ];

  List<Widget> _hestonControls(
    BuildContext context,
    AdvancedSettings settings,
    void Function(AdvancedSettings Function(AdvancedSettings)) change,
  ) {
    final HestonParams p = settings.heston;

    void setParams(HestonParams next) =>
        change((AdvancedSettings s) => s.copyWith(heston: next));

    return <Widget>[
      const SizedBox(height: 8),
      PricerSlider(
        label: 'Volatility today',
        value: p.initialVolatility,
        min: 0.05,
        max: 0.9,
        divisions: 85,
        valueLabel: '${(p.initialVolatility * 100).toStringAsFixed(0)}%',
        onChanged: (double v) =>
            setParams(p.copyWith(initialVariance: v * v)),
      ),
      PricerSlider(
        label: 'Long-run volatility',
        value: p.longRunVolatility,
        min: 0.05,
        max: 0.9,
        divisions: 85,
        valueLabel: '${(p.longRunVolatility * 100).toStringAsFixed(0)}%',
        onChanged: (double v) =>
            setParams(p.copyWith(longRunVariance: v * v)),
      ),
      PricerSlider(
        label: 'Speed of return to it',
        value: p.meanReversion,
        min: 0.1,
        max: 8,
        divisions: 79,
        valueLabel: p.meanReversion.toStringAsFixed(1),
        onChanged: (double v) => setParams(p.copyWith(meanReversion: v)),
      ),
      PricerSlider(
        label: 'Volatility of volatility',
        value: p.volOfVol,
        // Stops at the documented floor rather than running to zero, where
        // the semi-analytic price becomes unreliable — see
        // HestonParams.minimumUsableVolOfVol.
        min: HestonParams.minimumUsableVolOfVol,
        max: 1.5,
        divisions: 149,
        valueLabel: p.volOfVol.toStringAsFixed(2),
        onChanged: (double v) => setParams(p.copyWith(volOfVol: v)),
      ),
      PricerSlider(
        label: 'Price / volatility correlation',
        value: p.correlation,
        min: -0.95,
        max: 0.95,
        divisions: 38,
        valueLabel: p.correlation.toStringAsFixed(2),
        onChanged: (double v) => setParams(p.copyWith(correlation: v)),
      ),
      if (!p.satisfiesFeller)
        _Inline(
          'These values break the Feller condition, so volatility can reach '
          'zero. Real market fits often do this too — it is a note about the '
          'simulation needing more steps, not a mistake.',
        ),
    ];
  }
}

/// How hard to run the simulation.
class _EffortPanel extends ConsumerWidget {
  const _EffortPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AdvancedSettings settings = ref.watch(advancedSettingsProvider);
    final PricingJob? job = ref.watch(advancedJobProvider);
    final AdvancedPricer pricer = ref.watch(advancedPricerProvider);

    void change(AdvancedSettings Function(AdvancedSettings) update) {
      ref.read(advancedSettingsProvider.notifier).update(update);
      ref.read(advancedRunProvider.notifier).clear();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'HOW HARD TO WORK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            PricerSlider(
              label: 'Simulated paths',
              value: settings.paths.toDouble(),
              min: 1000,
              max: 500000,
              divisions: 100,
              valueLabel: _grouped(settings.paths),
              onChanged: (double v) => change(
                (AdvancedSettings s) => s.copyWith(paths: v.round()),
              ),
            ),
            PricerSlider(
              label: 'Steps per path',
              value: settings.steps.toDouble(),
              min: 1,
              max: 500,
              divisions: 100,
              valueLabel: '${settings.steps}',
              onChanged: (double v) => change(
                (AdvancedSettings s) => s.copyWith(steps: v.round()),
              ),
            ),
            if (job != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'This run will happen ${pricer.venueFor(job).label}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _grouped(int value) {
    final String digits = value.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

class _RunButton extends ConsumerWidget {
  const _RunButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PricingRun?> run = ref.watch(advancedRunProvider);
    final bool busy = run.isLoading;

    return FilledButton.icon(
      onPressed: busy
          ? null
          : () => ref.read(advancedRunProvider.notifier).run(),
      icon: busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(busy ? 'Simulating…' : 'Run simulation'),
    );
  }
}

class _RunOutcome extends ConsumerWidget {
  const _RunOutcome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PricingRun?> run = ref.watch(advancedRunProvider);

    return run.when(
      loading: () => const _Placeholder(
        icon: Icons.hourglass_empty,
        text:
            'Simulating. The work is happening off the main thread, so the app '
            'stays responsive.',
      ),
      error: (Object error, StackTrace _) => _Placeholder(
        icon: Icons.error_outline,
        text: error is ArgumentError
            ? (error.message?.toString() ?? 'That run was too large.')
            : 'The simulation could not be completed.',
      ),
      data: (PricingRun? value) {
        if (value == null) {
          return const _Placeholder(
            icon: Icons.play_circle_outline,
            text:
                'These contracts have no formula, so their price has to be '
                'simulated. Press Run to find out what it costs to know.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SimulationResultCard(run: value, currencySymbol: r'$'),
            // The sampling distribution only means something when there was
            // sampling: a settled, zero-error outcome (a dead knock-out, say)
            // has no bell to draw.
            if (value.result.standardError > 0) ...<Widget>[
              const SizedBox(height: 12),
              SimulationDistributionChart(
                price: value.result.price,
                standardError: value.result.standardError,
                reference: value.result.analyticReference,
                currencySymbol: r'$',
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short explanatory line under a control, reacting to its value.
class _Inline extends StatelessWidget {
  const _Inline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
    );
  }
}
