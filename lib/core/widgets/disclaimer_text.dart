import 'package:flutter/material.dart';

/// The canonical disclaimer strings.
///
/// Kept in one place so onboarding, Settings, the pricer and the practice
/// market all state the same thing — CLAUDE.md rules 1, 4 and 5. Change the
/// wording here, not at the call sites.
abstract final class Disclaimers {
  static const String educationalOnly =
      'OptionsSchool is educational only. Nothing here is financial, '
      'investment, tax or legal advice, and nothing is a recommendation to buy '
      'or sell any security.';

  static const String riskIsReal =
      'Options carry real risk. A long option can expire worthless, losing '
      '100% of the premium paid. Short or uncovered positions can lose far '
      'more than the amount received — in some cases without a fixed limit.';

  static const String simulationOnly =
      'Simulation for learning. Models are idealised; real markets differ '
      '(liquidity, bid/ask spreads, dividends, early exercise, fees). Past or '
      'simulated performance does not indicate future results.';

  static const String noAdviceShort =
      'Educational only — not financial advice.';

  static const String modelAssumptions =
      'Pricing models rest on simplifying assumptions (no arbitrage, constant '
      'volatility, European exercise, frictionless trading). Treat outputs as '
      'illustrations of how the inputs interact, not as exact prices.';
}

/// Compact, always-visible reminder for screens that show prices or payoffs.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({
    super.key,
    this.text = Disclaimers.simulationOnly,
    this.icon = Icons.science_outlined,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      liveRegion: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
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
