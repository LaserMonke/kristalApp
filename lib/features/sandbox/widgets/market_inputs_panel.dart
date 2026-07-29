import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pricing/priced_leg.dart';
import '../../../providers/pricer_providers.dart';
import 'pricer_slider.dart';

/// Spot, volatility, time to expiry and rate — the market inputs shared by
/// the single-option and strategy views, per CLAUDE.md Phase 4. Dragging any
/// slider here updates both tabs, since they read the same
/// [marketEnvironmentProvider].
class MarketInputsPanel extends ConsumerWidget {
  const MarketInputsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
    final MarketEnvironmentController controller = ref.read(
      marketEnvironmentProvider.notifier,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.tune_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('MARKET INPUTS', style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                )),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Reset to defaults',
                  icon: const Icon(Icons.restart_alt, size: 18),
                  onPressed: controller.reset,
                ),
              ],
            ),
            const SizedBox(height: 4),
            PricerSlider(
              label: 'Spot (underlying price)',
              value: env.spot,
              min: 20,
              max: 200,
              divisions: 180,
              valueLabel: r'$' '${env.spot.toStringAsFixed(0)}',
              onChanged: controller.setSpot,
            ),
            PricerSlider(
              label: 'Volatility',
              value: env.volatility,
              min: 0.05,
              max: 1.0,
              divisions: 95,
              valueLabel: '${(env.volatility * 100).toStringAsFixed(0)}%',
              onChanged: controller.setVolatility,
            ),
            PricerSlider(
              label: 'Time to expiry',
              value: env.timeToExpiry,
              min: 1 / 52,
              max: 2.0,
              divisions: 103,
              valueLabel: formatYears(env.timeToExpiry),
              onChanged: controller.setTimeToExpiry,
            ),
            PricerSlider(
              label: 'Risk-free rate',
              value: env.rate,
              min: -0.02,
              max: 0.10,
              divisions: 48,
              valueLabel: '${(env.rate * 100).toStringAsFixed(2)}%',
              onChanged: controller.setRate,
            ),
          ],
        ),
      ),
    );
  }
}

/// `0.5` -> `'6.0 months'`, `1.5` -> `'1.50 yr'`.
String formatYears(double years) {
  if (years < 1) return '${(years * 12).toStringAsFixed(1)} months';
  return '${years.toStringAsFixed(2)} yr';
}
