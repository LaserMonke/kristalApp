import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson.dart';
import '../../../pricing/black_scholes.dart';
import 'lesson_icons.dart';

/// A live Black-Scholes-Merton quote the learner drags around.
///
/// Every number comes from `lib/pricing/black_scholes.dart` (Phase 3), the
/// same pure, unit-tested pricer behind the Sandbox tab — this widget only
/// reads it live off local slider state and draws it.
class PricerExploreCardView extends StatefulWidget {
  const PricerExploreCardView({required this.card, super.key});

  final PricerExploreCard card;

  @override
  State<PricerExploreCardView> createState() => _PricerExploreCardViewState();
}

class _PricerExploreCardViewState extends State<PricerExploreCardView> {
  late double _spot;
  late double _volatility;
  late double _timeToExpiry;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(PricerExploreCardView old) {
    super.didUpdateWidget(old);
    if (old.card != widget.card) _reset();
  }

  void _reset() {
    final PricerExploreCard card = widget.card;
    _spot = card.spotStart;
    _volatility = card.volatility;
    _timeToExpiry = card.timeToExpiry;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PricerExploreCard card = widget.card;

    final BsmQuote quote = bsmQuote(
      card.optionType,
      BsmInputs(
        spot: _spot,
        strike: card.strike,
        rate: card.rate,
        volatility: _volatility,
        timeToExpiry: _timeToExpiry,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(lessonIcon('compass'), size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'TRY IT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(card.heading, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          card.prompt,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _PriceReadout(
          price: quote.price,
          currencySymbol: card.currencySymbol,
          emphasised: card.focus == PricerGreek.price,
        ),
        const SizedBox(height: 12),
        _GreeksRow(quote: quote, focus: card.focus),
        const SizedBox(height: 10),
        _PricerExploreSlider(
          label: 'Underlying (spot)',
          value: _spot,
          min: card.spotMin,
          max: card.spotMax,
          step: 1,
          valueLabel: '${card.currencySymbol}${_fmt(_spot)}',
          onChanged: (double v) => setState(() => _spot = v),
        ),
        if (card.adjustVolatility)
          _PricerExploreSlider(
            label: 'Volatility',
            value: _volatility,
            min: 0.05,
            max: 1.0,
            step: 0.01,
            valueLabel: '${(_volatility * 100).toStringAsFixed(0)}%',
            onChanged: (double v) => setState(() => _volatility = v),
          ),
        if (card.adjustTimeToExpiry)
          _PricerExploreSlider(
            label: 'Time to expiry',
            value: _timeToExpiry,
            min: 1 / 52,
            max: 2.0,
            step: 1 / 52,
            valueLabel: _formatYears(_timeToExpiry),
            onChanged: (double v) => setState(() => _timeToExpiry = v),
          ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.science_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A model estimate, not a market quote. Real prices differ — '
                'liquidity, bid/ask spread, dividends and non-constant '
                'volatility are not in this formula.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PriceReadout extends StatelessWidget {
  const _PriceReadout({
    required this.price,
    required this.currencySymbol,
    required this.emphasised,
  });

  final double price;
  final String currencySymbol;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: emphasised ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: emphasised ? 0.55 : 0.25)),
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
            '$currencySymbol${price.toStringAsFixed(2)}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// All five Greeks, quoted the way a trader would ask for them — per $1 of
/// spot, per 1 point of vol, per 1 point of rate, per calendar day — with
/// [focus] picked out so the number this card is actually teaching stands
/// apart from the other four, which are visible but muted.
class _GreeksRow extends StatelessWidget {
  const _GreeksRow({required this.quote, required this.focus});

  final BsmQuote quote;
  final PricerGreek focus;

  @override
  Widget build(BuildContext context) {
    final List<(PricerGreek, String, double, int)> tiles = <(PricerGreek, String, double, int)>[
      (PricerGreek.delta, 'Delta', quote.delta, 3),
      (PricerGreek.gamma, 'Gamma', quote.gamma, 4),
      (PricerGreek.vega, 'Vega/1%', quote.vega / 100, 3),
      (PricerGreek.theta, 'Theta/day', quote.theta / 365, 3),
      (PricerGreek.rho, 'Rho/1%', quote.rho / 100, 3),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final (PricerGreek key, String label, double value, int decimals) in tiles)
          _GreekTile(
            label: label,
            value: value.toStringAsFixed(decimals),
            focused: key == focus,
          ),
      ],
    );
  }
}

class _GreekTile extends StatelessWidget {
  const _GreekTile({required this.label, required this.value, required this.focused});

  final String label;
  final String value;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = focused ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: focused
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: focused ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.numeric.copyWith(
              fontSize: 14,
              color: focused ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricerExploreSlider extends StatelessWidget {
  const _PricerExploreSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double clamped = value.clamp(min, max);
    final int divisions = ((max - min) / step).round().clamp(1, 400);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
              Text(
                valueLabel,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
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
              semanticFormatterCallback: (double v) => '$label $valueLabel',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// `0.5` -> `'6.0 months'`, `1.5` -> `'1.50 yr'`.
String _formatYears(double years) {
  if (years < 1) return '${(years * 12).toStringAsFixed(1)} months';
  return '${years.toStringAsFixed(2)} yr';
}
