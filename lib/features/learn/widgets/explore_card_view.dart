import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/payoff_diagram.dart';
import '../../../data/models/lesson.dart';
import '../../../pricing/payoff.dart';
import 'lesson_icons.dart';

/// A payoff diagram the learner drives with sliders.
///
/// Every number shown here comes from `lib/pricing/payoff.dart` — the same
/// unit-tested expiry arithmetic the static diagrams use. Nothing is
/// predicted: the learner picks a finishing price and the card reports what
/// the position would be worth *if* the underlying ended there.
class ExploreCardView extends StatefulWidget {
  const ExploreCardView({required this.card, super.key});

  final ExploreCard card;

  @override
  State<ExploreCardView> createState() => _ExploreCardViewState();
}

class _ExploreCardViewState extends State<ExploreCardView> {
  late double _spot;
  late double _strike;
  late double _premium;

  /// Slider edits apply to the first option leg, so the learner is changing a
  /// contract rather than an abstract line. An underlying leg (the shares in a
  /// protective put) is left alone.
  int get _targetLeg =>
      widget.card.legs.indexWhere((StrategyLeg l) => l.kind != LegKind.underlying);

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(ExploreCardView old) {
    super.didUpdateWidget(old);
    if (old.card != widget.card) _reset();
  }

  void _reset() {
    final ExploreCard card = widget.card;
    final int index = _targetLeg;
    _spot = card.spotStart;
    _strike = index < 0 ? 0 : card.legs[index].strike;
    _premium = index < 0 ? 0 : card.legs[index].premium;
  }

  List<StrategyLeg> get _legs {
    final int index = _targetLeg;
    return <StrategyLeg>[
      for (int i = 0; i < widget.card.legs.length; i++)
        if (i == index)
          widget.card.legs[i].copyWith(strike: _strike, premium: _premium)
        else
          widget.card.legs[i],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ExploreCard card = widget.card;
    final List<StrategyLeg> legs = _legs;

    final double profit = strategyProfit(legs, _spot);
    final List<double> zeros = breakEvens(
      legs,
      spotMin: card.spotMin,
      spotMax: card.spotMax,
    );
    final bool unbounded = hasUnboundedUpsideLoss(legs);
    final double worst = worstProfitInRange(
      legs,
      spotMin: card.spotMin,
      spotMax: card.spotMax,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              lessonIcon('compass'),
              size: 18,
              color: theme.colorScheme.primary,
            ),
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
        PayoffDiagram(
          legs: legs,
          spotMin: card.spotMin,
          spotMax: card.spotMax,
          currencySymbol: card.currencySymbol,
          markerSpot: _spot,
          height: 200,
          // Redrawn on every slider tick — replaying the reveal would be noise.
          animate: false,
          showLegend: false,
        ),
        const SizedBox(height: 12),
        _Readout(
          spot: _spot,
          profit: profit,
          currencySymbol: card.currencySymbol,
        ),
        const SizedBox(height: 6),
        _ExploreSlider(
          label: 'Underlying at expiry',
          value: _spot,
          min: card.spotMin,
          max: card.spotMax,
          step: 1,
          currencySymbol: card.currencySymbol,
          onChanged: (double v) => setState(() => _spot = v),
        ),
        if (card.adjustStrike && _targetLeg >= 0)
          _ExploreSlider(
            label: 'Strike',
            value: _strike,
            min: _round(card.spotMin + (card.spotMax - card.spotMin) * 0.15, 5),
            max: _round(card.spotMax - (card.spotMax - card.spotMin) * 0.15, 5),
            step: 5,
            currencySymbol: card.currencySymbol,
            onChanged: (double v) => setState(() => _strike = v),
          ),
        if (card.adjustPremium && _targetLeg >= 0)
          _ExploreSlider(
            label: 'Premium',
            value: _premium,
            min: 1,
            max: 20,
            step: 1,
            currencySymbol: card.currencySymbol,
            onChanged: (double v) => setState(() => _premium = v),
          ),
        const SizedBox(height: 10),
        _FactRow(
          icon: Icons.adjust,
          text: zeros.isEmpty
              ? 'No break-even inside this price range.'
              : 'Break-even: ${zeros.map((double z) => '${card.currencySymbol}${_fmt(z)}').join(' and ')}.',
        ),
        _FactRow(
          icon: Icons.south_east,
          tone: theme.pnl.loss,
          text: unbounded
              ? 'Worst case: none. The loss keeps growing as the underlying '
                    'rises — this position has no fixed maximum loss.'
              : 'Worst result across this range: '
                    '${_signed(worst, card.currencySymbol)}.',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.science_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Simulation for learning. Value at expiry only, in an '
                'idealised market with no fees, bid/ask spread, dividends or '
                'early exercise. Real results differ.',
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

/// The headline number: what this position is worth at the chosen price.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.spot,
    required this.profit,
    required this.currencySymbol,
  });

  final double spot;
  final double profit;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool up = profit > 0;
    final bool flat = profit.abs() < 0.005;
    final Color tone = flat
        ? theme.colorScheme.onSurfaceVariant
        : (up ? theme.pnl.gain : theme.pnl.loss);

    // Word, sign and icon all carry the same meaning, so the result is never
    // conveyed by colour alone (CLAUDE.md accessibility rule).
    final String word = flat ? 'break-even' : (up ? 'profit' : 'loss');

    return Semantics(
      liveRegion: true,
      label:
          'At $currencySymbol${_fmt(spot)}, the position ends at '
          '${_signed(profit, currencySymbol)}, a $word.',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              flat
                  ? Icons.horizontal_rule
                  : (up ? Icons.arrow_upward : Icons.arrow_downward),
              size: 20,
              color: tone,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Finishes at $currencySymbol${_fmt(spot)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_signed(profit, currencySymbol)}  $word',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
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

class _ExploreSlider extends StatelessWidget {
  const _ExploreSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.currencySymbol,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String currencySymbol;
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
                '$currencySymbol${_fmt(clamped)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
              label: '$currencySymbol${_fmt(clamped)}',
              semanticFormatterCallback: (double v) =>
                  '$label $currencySymbol${_fmt(v)}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color colour = tone ?? theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: colour),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _signed(double v, String symbol) {
  if (v.abs() < 0.005) return '${symbol}0';
  return '${v > 0 ? '+' : '−'}$symbol${_fmt(v.abs())}';
}

double _round(double v, double to) => (v / to).round() * to;
