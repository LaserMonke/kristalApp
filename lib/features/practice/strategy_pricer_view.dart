import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/payoff_diagram.dart';
import '../../pricing/payoff.dart';
import '../../pricing/priced_leg.dart';
import '../../providers/pricer_providers.dart';
import 'widgets/market_inputs_panel.dart';
import 'widgets/pricer_slider.dart';

/// "Strategy" tab: pick a named multi-leg strategy — spreads, a straddle, a
/// covered call, a protective put — and see the combined payoff, priced live
/// off the same shared market inputs as the single-option tab.
///
/// Every leg's premium comes from `lib/pricing/black_scholes.dart` via
/// `lib/pricing/priced_leg.dart`; the combined payoff comes from the
/// expiry-payoff engine in `lib/pricing/payoff.dart` (Phase 1). This view
/// only reads Riverpod state and draws it.
class StrategyPricerView extends ConsumerWidget {
  const StrategyPricerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
    final StrategyState strategy = ref.watch(strategyProvider);
    final StrategyController controller = ref.read(strategyProvider.notifier);
    final List<StrategyLeg> legs = ref.watch(strategyLegsProvider);
    final AggregateGreeks greeks = ref.watch(strategyGreeksProvider);

    final double spotMin = (env.spot * 0.5).clamp(1, env.spot);
    final double spotMax = env.spot * 1.5;
    final double cost = netPremium(legs);
    final bool unbounded = hasUnboundedUpsideLoss(legs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        const MarketInputsPanel(),
        const SizedBox(height: 14),
        _PresetPicker(selected: strategy.preset, onSelected: controller.selectPreset),
        const SizedBox(height: 10),
        Text(
          strategy.preset.blurb,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Legs', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (int i = 0; i < strategy.legs.length; i++)
                  _LegRow(
                    spec: strategy.legs[i],
                    premium: legs[i].premium,
                    onStrikeChanged: (double v) => controller.setLegStrike(i, v),
                  ),
                const Divider(height: 24),
                _CostRow(cost: cost),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Combined payoff at expiry', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                PayoffDiagram(
                  legs: legs,
                  spotMin: spotMin,
                  spotMax: spotMax,
                  markerSpot: env.spot,
                  animate: false,
                ),
                const SizedBox(height: 12),
                _NetGreeksRow(greeks: greeks),
                if (unbounded) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.warning_amber_rounded, size: 16, color: theme.pnl.loss),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This combination has no fixed maximum loss — the '
                          'short leg is not fully covered as the underlying rises.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.pnl.loss),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const DisclaimerBanner(
          text: '${Disclaimers.simulationOnly} ${Disclaimers.modelAssumptions}',
          icon: Icons.calculate_outlined,
        ),
      ],
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.selected, required this.onSelected});

  final StrategyPreset selected;
  final ValueChanged<StrategyPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final StrategyPreset preset in StrategyPreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(preset.label),
                selected: preset == selected,
                onSelected: (_) => onSelected(preset),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.spec,
    required this.premium,
    required this.onStrikeChanged,
  });

  final StrategyLegSpec spec;
  final double premium;
  final ValueChanged<double> onStrikeChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isShare = spec.kind == LegKind.underlying;
    final String sideWord = spec.side == LegSide.long ? 'Long' : 'Short';
    final String kindWord = switch (spec.kind) {
      LegKind.call => 'call',
      LegKind.put => 'put',
      LegKind.underlying => 'shares',
    };
    final Color tone = spec.side == LegSide.long ? theme.pnl.gain : theme.pnl.loss;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                spec.side == LegSide.long ? Icons.add_circle_outline : Icons.remove_circle_outline,
                size: 16,
                color: tone,
              ),
              const SizedBox(width: 8),
              Text(
                '$sideWord $kindWord',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${spec.side == LegSide.short ? '+' : '−'}\$${premium.toStringAsFixed(2)}',
                style: theme.textTheme.numeric,
              ),
            ],
          ),
          if (!isShare)
            PricerSlider(
              label: 'Strike',
              value: spec.strike,
              min: 20,
              max: 200,
              divisions: 180,
              valueLabel: r'$' '${spec.strike.toStringAsFixed(0)}',
              semanticLabel: '$sideWord $kindWord strike',
              onChanged: onStrikeChanged,
            ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({required this.cost});

  final double cost;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool credit = cost < 0;
    return Row(
      children: <Widget>[
        Text(
          credit ? 'Net credit received' : 'Net cost to open',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          r'$' '${cost.abs().toStringAsFixed(2)}',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _NetGreeksRow extends StatelessWidget {
  const _NetGreeksRow({required this.greeks});

  final AggregateGreeks greeks;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Widget tile(String label, double value, int decimals) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value.toStringAsFixed(decimals), style: theme.textTheme.numeric),
        ],
      ),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        tile('Net delta', greeks.delta, 3),
        tile('Net gamma', greeks.gamma, 4),
        tile('Net vega/1%', greeks.vega / 100, 3),
        tile('Net theta/day', greeks.theta / 365, 3),
      ],
    );
  }
}
