import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A picture of a Monte Carlo run's *uncertainty*, drawn from the two numbers
/// the engine already returns: the estimate and its standard error.
///
/// It is NOT a histogram of the simulated payoffs — the engine keeps only
/// running sums, not every path, so those samples are gone by the time a
/// result reaches the UI. What it shows instead is the sampling distribution
/// of the estimate: run the whole simulation again and the price it reports
/// would land somewhere under this bell. The shaded middle is the 95%
/// interval — the same "about 19 runs in 20" the result card states in words.
///
/// Where the contract has a closed form, the exact price is drawn as a second
/// marker. Seeing it fall inside the bell is the visual version of "the
/// simulation agrees with the formula".
class SimulationDistributionChart extends StatelessWidget {
  const SimulationDistributionChart({
    required this.price,
    required this.standardError,
    required this.currencySymbol,
    this.reference,
    super.key,
  });

  /// The simulated price — the centre of the distribution.
  final double price;

  /// Standard error of that estimate — its spread. Must be > 0; the caller
  /// does not draw this chart for a settled, zero-error outcome.
  final double standardError;

  /// The exact price where a closed form exists, marked for comparison.
  final double? reference;

  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color distribution = theme.colorScheme.primary;
    // A hue distinct from the distribution in both palettes, paired with a
    // dashed line and a text label so it never relies on colour alone.
    final Color referenceColor = AppColors.reddishPurple;

    final (double low, double high) = (
      price - 1.96 * standardError,
      price + 1.96 * standardError,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'WHERE THE ESTIMATE COULD LAND',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'A bell curve of the simulated price, centred on '
                  '${_money(price)}, with a 95 percent interval from '
                  '${_money(low)} to ${_money(high)}'
                  '${reference != null ? ', and the exact formula price of ${_money(reference!)} marked' : ''}.',
              child: SizedBox(
                height: 168,
                width: double.infinity,
                child: CustomPaint(
                  painter: _DistributionPainter(
                    price: price,
                    standardError: standardError,
                    reference: reference,
                    distribution: distribution,
                    referenceColor: referenceColor,
                    axis: theme.colorScheme.onSurfaceVariant,
                    meanLine: theme.colorScheme.onSurface,
                    labelStyle: theme.textTheme.labelSmall!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    currencySymbol: currencySymbol,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Legend(
              distribution: distribution,
              referenceColor: referenceColor,
              hasReference: reference != null,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }

  String _money(double value) =>
      '$currencySymbol${value.toStringAsFixed(2)}';
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.distribution,
    required this.referenceColor,
    required this.hasReference,
    required this.theme,
  });

  final Color distribution;
  final Color referenceColor;
  final bool hasReference;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: <Widget>[
        _LegendItem(
          color: distribution.withValues(alpha: 0.28),
          label: 'Shaded: 95% interval',
          theme: theme,
        ),
        if (hasReference)
          _LegendItem(
            color: referenceColor,
            label: 'Exact price',
            dashed: true,
            theme: theme,
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.theme,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 16,
          height: dashed ? 0 : 10,
          decoration: dashed
              ? null
              : BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
          child: dashed
              ? CustomPaint(
                  painter: _DashSwatchPainter(color: color),
                  size: const Size(16, 10),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DashSwatchPainter extends CustomPainter {
  const _DashSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const double dash = 3;
    const double gap = 2;
    double x = 0;
    final double y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashSwatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DistributionPainter extends CustomPainter {
  _DistributionPainter({
    required this.price,
    required this.standardError,
    required this.reference,
    required this.distribution,
    required this.referenceColor,
    required this.axis,
    required this.meanLine,
    required this.labelStyle,
    required this.currencySymbol,
  });

  final double price;
  final double standardError;
  final double? reference;
  final Color distribution;
  final Color referenceColor;
  final Color axis;
  final Color meanLine;
  final TextStyle labelStyle;
  final String currencySymbol;

  static const double _topPad = 8;
  static const double _bottomPad = 22; // room for the axis labels
  static const double _sigmaSpan = 4; // curve drawn to ±4σ

  @override
  void paint(Canvas canvas, Size size) {
    final double se = standardError;
    final double low95 = price - 1.96 * se;
    final double high95 = price + 1.96 * se;

    // Window: the bell to ±4σ, widened if the exact price sits outside it, so
    // a badly-biased run still shows its reference marker rather than clipping
    // it off-screen.
    double xMin = price - _sigmaSpan * se;
    double xMax = price + _sigmaSpan * se;
    final double? ref = reference;
    if (ref != null) {
      xMin = math.min(xMin, ref - 0.4 * se);
      xMax = math.max(xMax, ref + 0.4 * se);
    }
    final double span = xMax - xMin;
    if (span <= 0) return;

    final double plotBottom = size.height - _bottomPad;
    final double plotHeight = plotBottom - _topPad;

    double dxToPx(double x) => (x - xMin) / span * size.width;
    // Unnormalised normal density; the peak (at the mean) maps to the top.
    double density(double x) {
      final double z = (x - price) / se;
      return math.exp(-0.5 * z * z);
    }

    double dyToPx(double d) => plotBottom - d * plotHeight;

    // Build the curve.
    const int samples = 96;
    final Path curve = Path();
    final Path fill = Path()..moveTo(dxToPx(math.max(low95, xMin)), plotBottom);
    for (int i = 0; i <= samples; i++) {
      final double x = xMin + span * (i / samples);
      final double px = dxToPx(x);
      final double py = dyToPx(density(x));
      if (i == 0) {
        curve.moveTo(px, py);
      } else {
        curve.lineTo(px, py);
      }
    }

    // Shaded 95% interval under the curve.
    final double fillLo = math.max(low95, xMin);
    final double fillHi = math.min(high95, xMax);
    for (int i = 0; i <= samples; i++) {
      final double x = fillLo + (fillHi - fillLo) * (i / samples);
      fill.lineTo(dxToPx(x), dyToPx(density(x)));
    }
    fill
      ..lineTo(dxToPx(fillHi), plotBottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..color = distribution.withValues(alpha: 0.24)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = distribution
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Baseline.
    canvas.drawLine(
      Offset(0, plotBottom),
      Offset(size.width, plotBottom),
      Paint()
        ..color = axis.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );

    // Mean marker.
    final double meanX = dxToPx(price);
    canvas.drawLine(
      Offset(meanX, dyToPx(density(price))),
      Offset(meanX, plotBottom),
      Paint()
        ..color = meanLine.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    // Exact-formula marker, dashed, if it falls in the window.
    if (ref != null && ref >= xMin && ref <= xMax) {
      _dashedVertical(
        canvas,
        dxToPx(ref),
        _topPad,
        plotBottom,
        Paint()
          ..color = referenceColor
          ..strokeWidth = 2,
      );
    }

    // Axis labels: low95, mean, high95.
    _label(canvas, _money(low95), dxToPx(low95), plotBottom + 4, size.width);
    _label(canvas, _money(price), meanX, plotBottom + 4, size.width,
        emphasise: true);
    _label(canvas, _money(high95), dxToPx(high95), plotBottom + 4, size.width);
  }

  void _dashedVertical(
    Canvas canvas,
    double x,
    double top,
    double bottom,
    Paint paint,
  ) {
    const double dash = 5;
    const double gap = 4;
    double y = top;
    while (y < bottom) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, bottom)), paint);
      y += dash + gap;
    }
  }

  void _label(
    Canvas canvas,
    String text,
    double centreX,
    double top,
    double maxWidth, {
    bool emphasise = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: emphasise
            ? labelStyle.copyWith(fontWeight: FontWeight.w700)
            : labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = centreX - tp.width / 2;
    dx = dx.clamp(0, maxWidth - tp.width);
    tp.paint(canvas, Offset(dx, top));
  }

  String _money(double value) =>
      '$currencySymbol${value.toStringAsFixed(2)}';

  @override
  bool shouldRepaint(_DistributionPainter oldDelegate) =>
      oldDelegate.price != price ||
      oldDelegate.standardError != standardError ||
      oldDelegate.reference != reference ||
      oldDelegate.distribution != distribution ||
      oldDelegate.referenceColor != referenceColor;
}
