import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One labelled slider row for the interactive pricer — a value label on the
/// right, a `Slider` beneath it. Shared by the market-inputs panel and the
/// per-leg strike controls in the strategy view.
class PricerSlider extends StatelessWidget {
  const PricerSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    super.key,
    this.semanticLabel,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Formatted display value, e.g. `'$104'`, `'25%'`, `'6.0 months'`.
  final String valueLabel;
  final ValueChanged<double> onChanged;

  /// Read aloud instead of [label]/[valueLabel] when set — used where the
  /// visible text is abbreviated (e.g. `'K'` for strike) but a screen reader
  /// should hear the full word.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double clamped = value.clamp(min, max);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(valueLabel, style: theme.textTheme.numeric),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              semanticFormatterCallback: (double v) =>
                  '${semanticLabel ?? label} $valueLabel',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
