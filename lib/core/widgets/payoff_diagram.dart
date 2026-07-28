import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../pricing/payoff.dart';
import '../theme/app_colors.dart';

/// Profit-and-loss at expiry, plotted against the underlying price.
///
/// The maths comes from `lib/pricing/payoff.dart` (pure Dart, unit-tested);
/// this widget only draws it. Colour is never the sole signal — the loss
/// region is hatched and dashed as well as coloured, break-even is labelled,
/// and a spoken summary is attached for screen readers.
class PayoffDiagram extends StatelessWidget {
  const PayoffDiagram({
    required this.legs,
    required this.spotMin,
    required this.spotMax,
    super.key,
    this.currencySymbol = r'$',
    this.height = 230,
    this.markerSpot,
    this.animate = true,
    this.showLegend = true,
  });

  final List<StrategyLeg> legs;
  final double spotMin;
  final double spotMax;
  final String currencySymbol;
  final double height;

  /// Underlying price to mark on the curve, for cards where the learner is
  /// dragging a price around. Null draws no marker.
  final double? markerSpot;

  /// Draws the curve on once when the card appears. Turned off where the
  /// diagram is redrawn continuously (an interactive card), because replaying
  /// the reveal on every slider tick would be noise, not information.
  final bool animate;

  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PnlColors pnl = theme.pnl;

    final List<PayoffPoint> curve = profitCurve(
      legs,
      spotMin: spotMin,
      spotMax: spotMax,
    );
    final List<double> zeros = breakEvens(
      legs,
      spotMin: spotMin,
      spotMax: spotMax,
    );
    final bool unboundedLoss = hasUnboundedUpsideLoss(legs);

    // Splitting the curve at every break-even keeps each drawn segment wholly
    // in profit or wholly in loss, so styling per segment is unambiguous.
    final List<PayoffPoint> drawable = _withCrossings(curve, zeros);

    _PayoffPainter painterAt(double progress) => _PayoffPainter(
      points: drawable,
      breakEvenPoints: zeros,
      strikes: legs
          .where((StrategyLeg leg) => leg.kind != LegKind.underlying)
          .map((StrategyLeg leg) => leg.strike)
          .where((double s) => s > spotMin && s < spotMax)
          .toSet()
          .toList(),
      spotMin: spotMin,
      spotMax: spotMax,
      markerSpot: markerSpot,
      markerProfit: markerSpot == null
          ? 0
          : strategyProfit(legs, markerSpot!),
      progress: progress,
      gain: pnl.gain,
      loss: pnl.loss,
      axis: theme.colorScheme.outline,
      label: theme.colorScheme.onSurfaceVariant,
      markerRing: theme.colorScheme.surface,
      currencySymbol: currencySymbol,
      labelStyle: theme.textTheme.labelSmall!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
      ),
      textDirection: Directionality.of(context),
    );

    final Widget chart = SizedBox(
      height: height,
      width: double.infinity,
      child: animate
          ? TweenAnimationBuilder<double>(
              // Draws the curve on from left to right, so the eye follows the
              // shape being built instead of arriving at a finished picture.
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 750),
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double t, Widget? _) =>
                  CustomPaint(painter: painterAt(t)),
            )
          : CustomPaint(painter: painterAt(1)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          label: _describe(curve, zeros, unboundedLoss),
          excludeSemantics: true,
          child: chart,
        ),
        if (showLegend) ...<Widget>[
          const SizedBox(height: 8),
          _Legend(unboundedLoss: unboundedLoss),
        ],
      ],
    );
  }

  /// Screen-reader description. A payoff chart is meaningless as an image, so
  /// the shape is spelled out in words.
  String _describe(
    List<PayoffPoint> curve,
    List<double> zeros,
    bool unboundedLoss,
  ) {
    final double worst = curve
        .map((PayoffPoint p) => p.profit)
        .reduce((double a, double b) => a < b ? a : b);
    final double best = curve
        .map((PayoffPoint p) => p.profit)
        .reduce((double a, double b) => a > b ? a : b);

    final String breakEven = zeros.isEmpty
        ? 'No break-even inside the plotted range.'
        : 'Break-even at ${zeros.map(_money).join(' and ')}.';
    final String tail = unboundedLoss
        ? 'Beyond the right edge the loss keeps growing without a fixed limit.'
        : '';

    return 'Profit and loss at expiry, plotted from ${_money(spotMin)} to '
        '${_money(spotMax)}. Worst result on this chart ${_money(worst)}, best '
        '${_money(best)}. $breakEven $tail';
  }

  String _money(double v) =>
      '$currencySymbol${v.abs() >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
}

/// Inserts exact zero crossings into the sampled curve.
List<PayoffPoint> _withCrossings(List<PayoffPoint> curve, List<double> zeros) {
  if (zeros.isEmpty) return curve;

  final List<PayoffPoint> merged = <PayoffPoint>[
    ...curve,
    for (final double x in zeros) PayoffPoint(x, 0),
  ]..sort((PayoffPoint a, PayoffPoint b) => a.spot.compareTo(b.spot));

  return merged;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.unboundedLoss});

  final bool unboundedLoss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PnlColors pnl = theme.pnl;
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _Swatch(color: pnl.gain, dashed: false),
            const SizedBox(width: 6),
            Text('Profit', style: style),
            const SizedBox(width: 16),
            _Swatch(color: pnl.loss, dashed: true),
            const SizedBox(width: 6),
            Text('Loss', style: style),
          ],
        ),
        if (unboundedLoss) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 14, color: pnl.loss),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'The loss keeps growing past the right edge — this position '
                  'has no fixed maximum loss.',
                  style: style,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 3,
      child: CustomPaint(painter: _SwatchPainter(color: color, dashed: dashed)),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 4, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}

class _PayoffPainter extends CustomPainter {
  const _PayoffPainter({
    required this.points,
    required this.breakEvenPoints,
    required this.strikes,
    required this.spotMin,
    required this.spotMax,
    required this.markerSpot,
    required this.markerProfit,
    required this.progress,
    required this.gain,
    required this.loss,
    required this.axis,
    required this.label,
    required this.markerRing,
    required this.labelStyle,
    required this.currencySymbol,
    required this.textDirection,
  });

  final List<PayoffPoint> points;
  final List<double> breakEvenPoints;
  final List<double> strikes;
  final double spotMin;
  final double spotMax;
  final double? markerSpot;
  final double markerProfit;

  /// How much of the curve to reveal, left to right, 0 to 1.
  final double progress;

  final Color gain;
  final Color loss;
  final Color axis;
  final Color label;
  final Color markerRing;
  final TextStyle labelStyle;
  final String currencySymbol;
  final TextDirection textDirection;

  static const double _padLeft = 48;
  static const double _padRight = 12;
  static const double _padTop = 10;
  static const double _padBottom = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      _padLeft,
      _padTop,
      size.width - _padRight,
      size.height - _padBottom,
    );
    if (plot.width <= 0 || plot.height <= 0 || points.isEmpty) return;

    // Vertical range always includes zero so the break-even line is on-chart,
    // with headroom so the curve never touches the frame.
    double lo = 0;
    double hi = 0;
    for (final PayoffPoint p in points) {
      lo = math.min(lo, p.profit);
      hi = math.max(hi, p.profit);
    }
    final double span = math.max(hi - lo, 1);
    lo -= span * 0.12;
    hi += span * 0.12;

    double dx(double spot) =>
        plot.left + (spot - spotMin) / (spotMax - spotMin) * plot.width;
    double dy(double profit) =>
        plot.bottom - (profit - lo) / (hi - lo) * plot.height;

    _drawFrame(canvas, plot);
    _drawStrikes(canvas, plot, dx);
    _drawZeroLine(canvas, plot, dy(0));

    // Everything that represents the position itself is revealed left to
    // right; the frame and axes stay put so the chart never appears to move.
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          plot.left,
          plot.top,
          plot.left + plot.width * progress.clamp(0.0, 1.0),
          plot.bottom,
        ),
      );
    _drawAreas(canvas, plot, dx, dy);
    _drawCurve(canvas, dx, dy);
    _drawBreakEvens(canvas, plot, dx, dy);
    canvas.restore();

    _drawMarker(canvas, plot, dx, dy);
    _drawAxisLabels(canvas, plot, lo, hi, dy);
  }

  /// The price the learner has chosen, pinned to the curve.
  void _drawMarker(
    Canvas canvas,
    Rect plot,
    double Function(double) dx,
    double Function(double) dy,
  ) {
    final double? spot = markerSpot;
    if (spot == null || spot < spotMin || spot > spotMax) return;

    final double x = dx(spot);
    final double y = dy(markerProfit).clamp(plot.top, plot.bottom);
    final Color tone = markerProfit >= 0 ? gain : loss;

    final Paint stem = Paint()
      ..color = label.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (double at = plot.top; at < plot.bottom; at += 6) {
      canvas.drawLine(
        Offset(x, at),
        Offset(x, math.min(at + 3, plot.bottom)),
        stem,
      );
    }

    canvas
      ..drawCircle(Offset(x, y), 6.5, Paint()..color = markerRing)
      ..drawCircle(Offset(x, y), 5, Paint()..color = tone);
  }

  void _drawFrame(Canvas canvas, Rect plot) {
    canvas.drawRect(
      plot,
      Paint()
        ..color = axis.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawStrikes(Canvas canvas, Rect plot, double Function(double) dx) {
    final Paint paint = Paint()
      ..color = axis
      ..strokeWidth = 1;

    for (final double strike in strikes) {
      final double x = dx(strike);
      for (double y = plot.top; y < plot.bottom; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, plot.bottom)), paint);
      }
      _text(
        canvas,
        'K ${_short(strike)}',
        Offset(x + 4, plot.top + 3),
        labelStyle,
      );
    }
  }

  void _drawZeroLine(Canvas canvas, Rect plot, double y) {
    canvas.drawLine(
      Offset(plot.left, y),
      Offset(plot.right, y),
      Paint()
        ..color = axis
        ..strokeWidth = 1.2,
    );
  }

  /// Shaded profit and loss regions. The loss region is additionally hatched
  /// so it is distinguishable without relying on hue.
  void _drawAreas(
    Canvas canvas,
    Rect plot,
    double Function(double) dx,
    double Function(double) dy,
  ) {
    final Path gainPath = Path();
    final Path lossPath = Path();
    final double zeroY = dy(0);

    void addRegion(Path path, bool wantProfit) {
      bool open = false;
      for (int i = 0; i < points.length; i++) {
        final PayoffPoint p = points[i];
        final bool inRegion = wantProfit ? p.profit >= 0 : p.profit <= 0;
        if (inRegion) {
          final Offset at = Offset(dx(p.spot), dy(p.profit));
          if (!open) {
            path.moveTo(at.dx, zeroY);
            open = true;
          }
          path.lineTo(at.dx, at.dy);
          final bool last = i == points.length - 1;
          final bool leaving =
              last ||
              (wantProfit ? points[i + 1].profit < 0 : points[i + 1].profit > 0);
          if (leaving) {
            path.lineTo(at.dx, zeroY);
            path.close();
            open = false;
          }
        }
      }
    }

    addRegion(gainPath, true);
    addRegion(lossPath, false);

    canvas.drawPath(gainPath, Paint()..color = gain.withValues(alpha: 0.16));
    canvas.drawPath(lossPath, Paint()..color = loss.withValues(alpha: 0.14));

    canvas
      ..save()
      ..clipPath(lossPath);
    final Paint hatch = Paint()
      ..color = loss.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (double x = plot.left - plot.height; x < plot.right; x += 9) {
      canvas.drawLine(
        Offset(x, plot.bottom),
        Offset(x + plot.height, plot.top),
        hatch,
      );
    }
    canvas.restore();
  }

  /// Solid where the position is in profit, dashed where it is in loss.
  void _drawCurve(
    Canvas canvas,
    double Function(double) dx,
    double Function(double) dy,
  ) {
    for (int i = 0; i < points.length - 1; i++) {
      final PayoffPoint a = points[i];
      final PayoffPoint b = points[i + 1];
      final bool profitable = (a.profit + b.profit) / 2 >= 0;

      final Paint paint = Paint()
        ..color = profitable ? gain : loss
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      final Offset from = Offset(dx(a.spot), dy(a.profit));
      final Offset to = Offset(dx(b.spot), dy(b.profit));

      if (profitable) {
        canvas.drawLine(from, to, paint);
      } else {
        _dashedLine(canvas, from, to, paint);
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const double dash = 5;
    const double gap = 3.5;
    final double length = (to - from).distance;
    if (length == 0) return;

    final Offset unit = (to - from) / length;
    double travelled = 0;
    while (travelled < length) {
      final double end = math.min(travelled + dash, length);
      canvas.drawLine(from + unit * travelled, from + unit * end, paint);
      travelled = end + gap;
    }
  }

  void _drawBreakEvens(
    Canvas canvas,
    Rect plot,
    double Function(double) dx,
    double Function(double) dy,
  ) {
    for (final double breakEven in breakEvenPoints) {
      if (breakEven <= spotMin || breakEven >= spotMax) continue;
      final Offset at = Offset(dx(breakEven), dy(0));

      canvas
        ..drawCircle(at, 4, Paint()..color = label)
        ..drawCircle(
          at,
          4,
          Paint()
            ..color = axis
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

      _text(
        canvas,
        'BE ${_short(breakEven)}',
        Offset(at.dx + 6, at.dy - 16),
        labelStyle.copyWith(fontWeight: FontWeight.w600),
      );
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Rect plot,
    double lo,
    double hi,
    double Function(double) dy,
  ) {
    // Y axis: the extremes and zero are the values that carry meaning here.
    for (final double value in <double>{lo, 0, hi}) {
      final double y = dy(value);
      if (y < plot.top - 2 || y > plot.bottom + 2) continue;
      _text(
        canvas,
        _signed(value),
        Offset(2, y - 7),
        labelStyle,
        maxWidth: _padLeft - 6,
        align: TextAlign.right,
      );
    }

    // X axis.
    _text(canvas, _short(spotMin), Offset(plot.left, plot.bottom + 5), labelStyle);
    _text(
      canvas,
      _short(spotMax),
      Offset(plot.right - 34, plot.bottom + 5),
      labelStyle,
      maxWidth: 34,
      align: TextAlign.right,
    );
    _text(
      canvas,
      'Underlying at expiry',
      Offset(plot.left, plot.bottom + 5),
      labelStyle,
      maxWidth: plot.width,
      align: TextAlign.center,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at,
    TextStyle style, {
    double maxWidth = 120,
    TextAlign align = TextAlign.left,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: textDirection,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, at);
  }

  String _short(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _signed(double v) {
    if (v.abs() < 0.005) return '${currencySymbol}0';
    final String sign = v > 0 ? '+' : '-';
    return '$sign$currencySymbol${_short(v.abs())}';
  }

  @override
  bool shouldRepaint(_PayoffPainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.markerSpot != markerSpot ||
      old.markerProfit != markerProfit ||
      old.gain != gain ||
      old.loss != loss ||
      old.spotMin != spotMin ||
      old.spotMax != spotMax;
}
