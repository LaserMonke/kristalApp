import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../pricing/structured.dart';
import '../../../providers/advanced_pricer_providers.dart';

/// Takes the wrapper off a structured product.
///
/// The whole panel is one argument: a certificate sold on a headline ("100%
/// capital protection with 70% of any rise") is a bond plus some options, and
/// once a learner can see the parts and their prices, the headline stops being
/// magic and becomes arithmetic they can check.
///
/// Three things are shown that a brochure would not (CLAUDE.md rules 2 and 3):
/// the sold components, marked as sold; the worst case in plain words; and the
/// gap between what the product is worth and what it costs.
class StructuredProductPanel extends ConsumerWidget {
  const StructuredProductPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AdvancedSettings settings = ref.watch(advancedSettingsProvider);
    final AdvancedSettingsController controller = ref.read(
      advancedSettingsProvider.notifier,
    );
    final StructuredValuation valuation = ref.watch(
      structuredValuationProvider,
    );
    final StructuredProduct product = settings.product.build();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<StructuredProductKind>(
                  initialValue: settings.product,
                  decoration: const InputDecoration(
                    labelText: 'Product',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<StructuredProductKind>>[
                    for (final StructuredProductKind kind
                        in StructuredProductKind.values)
                      DropdownMenuItem<StructuredProductKind>(
                        value: kind,
                        child: Text(kind.label),
                      ),
                  ],
                  onChanged: (StructuredProductKind? kind) {
                    if (kind == null) return;
                    controller.update(
                      (AdvancedSettings s) => s.copyWith(product: kind),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  product.purpose,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'WHAT IS INSIDE THE WRAPPER',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Per ${valuation.notional.toStringAsFixed(0)} invested.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final ProductComponent component in valuation.components)
                  _ComponentRow(component: component),
                const Divider(height: 24),
                _TotalRow(valuation: valuation),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        _MarginCard(valuation: valuation),
        const SizedBox(height: 12),
        _WorstCaseCard(text: valuation.maxLossDescription),
      ],
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component});

  final ProductComponent component;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Words AND an icon, never colour alone — a sold leg has to be
              // unmistakable to a colourblind reader too.
              Icon(
                component.isSold
                    ? Icons.remove_circle_outline
                    : Icons.add_circle_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  component.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                component.value.toStringAsFixed(2),
                style: theme.textTheme.numeric,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              component.isSold
                  ? 'SOLD. ${component.explanation}'
                  : component.explanation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.valuation});

  final StructuredValuation valuation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          'Model value of the bundle',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          valuation.fairValue.toStringAsFixed(2),
          style: theme.textTheme.numeric.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The number a brochure does not print.
class _MarginCard extends StatelessWidget {
  const _MarginCard({required this.valuation});

  final StructuredValuation valuation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool costsMoreThanItIsWorth = valuation.issueMargin > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Paid on day one',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${valuation.issueMarginPercent.toStringAsFixed(1)}%',
                  style: theme.textTheme.numeric,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              costsMoreThanItIsWorth
                  ? 'Bought at ${valuation.notional.toStringAsFixed(0)}, this '
                        'bundle is worth ${valuation.fairValue.toStringAsFixed(2)} '
                        'under the model — a difference of '
                        '${valuation.issueMargin.toStringAsFixed(2)}. That gap is '
                        'the issuer\'s costs and profit, and the buyer pays it '
                        'immediately. It is not a scandal; issuers have costs. '
                        'But a buyer who cannot see it cannot judge the deal.'
                  : 'Under these market inputs the parts are worth more than '
                        'the ${valuation.notional.toStringAsFixed(0)} face value — '
                        'which tells you the inputs are unusual, not that the '
                        'product is a bargain. Real issue terms are set so this '
                        'does not happen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'The bond leg is discounted at the risk-free rate, so every '
              'value here assumes the issuer cannot fail. A real one can. '
              'Lehman Brothers issued capital-protected notes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorstCaseCard extends StatelessWidget {
  const _WorstCaseCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Worst case',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
