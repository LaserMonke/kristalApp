import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/payoff_diagram.dart';
import '../../pricing/black_scholes.dart';
import '../../pricing/priced_leg.dart';
import '../../providers/pricer_providers.dart';
import 'widgets/market_inputs_panel.dart';
import 'widgets/pricer_slider.dart';

/// "Single option" tab: pick call or put and a strike, drag the shared
/// market inputs, and watch the theoretical price, the Greeks and the
/// at-expiry payoff respond immediately.
///
/// Every number here comes from `lib/pricing/black_scholes.dart` (Phase 3),
/// a pure, unit-tested Dart library — this view only reads it live off
/// Riverpod state and draws it.
class SingleOptionPricerView extends ConsumerWidget {
  const SingleOptionPricerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
    final SingleOptionState option = ref.watch(singleOptionProvider);
    final SingleOptionController controller = ref.read(
      singleOptionProvider.notifier,
    );
    final BsmQuote quote = ref.watch(singleOptionQuoteProvider);

    final double spotMin = (env.spot * 0.5).clamp(1, env.spot);
    final double spotMax = env.spot * 1.5;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        const MarketInputsPanel(),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
                  selected: <OptionType>{option.type},
                  onSelectionChanged: (Set<OptionType> s) =>
                      controller.setType(s.first),
                ),
                const SizedBox(height: 12),
                PricerSlider(
                  label: 'Strike',
                  value: option.strike,
                  min: 20,
                  max: 200,
                  divisions: 180,
                  valueLabel: r'$' '${option.strike.toStringAsFixed(0)}',
                  onChanged: controller.setStrike,
                ),
                const SizedBox(height: 4),
                _PriceReadout(quote: quote),
                const SizedBox(height: 14),
                _GreeksGrid(quote: quote),
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
                Text('Payoff at expiry', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'If bought today at the price above and held to expiry.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, _) =>
                      PayoffDiagram(
                        legs: ref.watch(singleOptionLegsProvider),
                        spotMin: spotMin,
                        spotMax: spotMax,
                        markerSpot: env.spot,
                        animate: false,
                      ),
                ),
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

class _PriceReadout extends StatelessWidget {
  const _PriceReadout({required this.quote});

  final BsmQuote quote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            'Theoretical price',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            r'$' '${quote.price.toStringAsFixed(2)}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The five Greeks, quoted in the "per one unit of practical change"
/// convention traders actually use — 1 vol point, 1 rate point, 1 calendar
/// day — rather than the raw per-100%/per-year units the formulas return.
class _GreeksGrid extends StatelessWidget {
  const _GreeksGrid({required this.quote});

  final BsmQuote quote;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _GreekTile(
          label: 'Delta',
          value: quote.delta.toStringAsFixed(3),
          hint: 'Price change per \$1 move in the underlying.',
        ),
        _GreekTile(
          label: 'Gamma',
          value: quote.gamma.toStringAsFixed(4),
          hint: "Delta's change per \$1 move in the underlying.",
        ),
        _GreekTile(
          label: 'Vega',
          value: (quote.vega / 100).toStringAsFixed(3),
          hint: 'Price change per 1 percentage point of volatility.',
        ),
        _GreekTile(
          label: 'Theta / day',
          value: (quote.theta / 365).toStringAsFixed(3),
          hint: 'Price change per calendar day of time passing.',
        ),
        _GreekTile(
          label: 'Rho',
          value: (quote.rho / 100).toStringAsFixed(3),
          hint: 'Price change per 1 percentage point of the rate.',
        ),
      ],
    );
  }
}

class _GreekTile extends StatelessWidget {
  const _GreekTile({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: hint,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.numeric),
          ],
        ),
      ),
    );
  }
}
