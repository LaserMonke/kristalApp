import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/advanced_pricer.dart';

/// The result of a Monte Carlo run.
///
/// The design rule here is that the UNCERTAINTY is not a footnote. A
/// simulated price printed alone, to two decimal places, claims a precision
/// it does not have — so the error bar sits immediately beside the number in
/// the same visual weight, and the confidence interval is spelled out in
/// words underneath (CLAUDE.md rules 4 and 5).
///
/// Where the contract also has a closed form, the exact answer is shown next
/// to the estimate. Watching a simulation land on a formula's answer is what
/// earns it the right to be believed on the contracts where no formula exists.
class SimulationResultCard extends StatelessWidget {
  const SimulationResultCard({
    required this.run,
    required this.currencySymbol,
    super.key,
  });

  final PricingRun run;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (double low, double high) = run.result.confidenceInterval95;
    final double? reference = run.result.analyticReference;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SIMULATED PRICE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            // The estimate and its error, together and inseparable.
            Semantics(
              label:
                  'Simulated price ${_money(run.result.price)}, '
                  'plus or minus ${_money(run.result.standardError)} standard '
                  'error.',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    _money(run.result.price),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '± ${_money(run.result.standardError)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              run.result.standardError > 0
                  ? 'Run this simulation many times and about 19 answers in 20 '
                        'would fall between ${_money(low)} and ${_money(high)}.'
                  : 'This outcome was settled without simulating anything, so '
                        'there is no sampling error.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),

            if (reference != null) ...<Widget>[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _ReferenceRow(
                reference: reference,
                deviation: run.result.referenceDeviationInErrors,
                currencySymbol: currencySymbol,
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _RunFacts(run: run),

            if (run.serverFallbackReason != null) ...<Widget>[
              const SizedBox(height: 12),
              _Note(
                icon: Icons.cloud_off_outlined,
                text: run.serverFallbackReason!,
              ),
            ],

            for (final String note in run.result.notes) ...<Widget>[
              const SizedBox(height: 12),
              _Note(icon: Icons.info_outline, text: note),
            ],
          ],
        ),
      ),
    );
  }

  String _money(double value) =>
      '$currencySymbol${value.toStringAsFixed(2)}';
}

/// The exact price beside the simulated one.
class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({
    required this.reference,
    required this.deviation,
    required this.currencySymbol,
  });

  final double reference;
  final double? deviation;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Exact formula',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$currencySymbol${reference.toStringAsFixed(4)}',
              style: theme.textTheme.numeric,
            ),
          ],
        ),
        if (deviation != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            deviation! < 3
                ? 'The simulation landed ${deviation!.toStringAsFixed(1)} '
                      'standard errors from the exact answer — comfortably '
                      'inside what sampling alone explains.'
                : 'The simulation landed ${deviation!.toStringAsFixed(1)} '
                      'standard errors from the exact answer. That is further '
                      'than sampling explains, which usually means the method '
                      'itself is biased here — more steps, not more paths.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

/// Where it ran, how long it took, how many paths it averaged.
///
/// Shown rather than hidden because "on the server" means data left the
/// device, and a learner is entitled to know that without digging.
class _RunFacts extends StatelessWidget {
  const _RunFacts({required this.run});

  final PricingRun run;

  @override
  Widget build(BuildContext context) {
    final int milliseconds = run.elapsed.inMilliseconds;

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: <Widget>[
        _Fact(
          icon: Icons.timeline_outlined,
          text: '${_grouped(run.result.paths)} independent paths',
        ),
        _Fact(
          icon: run.venue == PricingVenue.server
              ? Icons.cloud_outlined
              : Icons.smartphone_outlined,
          text: 'Ran ${run.venue.label}',
        ),
        _Fact(
          icon: Icons.schedule_outlined,
          text: milliseconds < 1000
              ? '${milliseconds}ms'
              : '${(milliseconds / 1000).toStringAsFixed(1)}s',
        ),
      ],
    );
  }

  /// `1234567` -> `'1,234,567'`.
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

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
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
    );
  }
}
