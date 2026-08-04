import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The gold tones used by the certificate.
///
/// Fixed rather than drawn from the theme: a seal that turns blue in dark mode
/// stops reading as a seal. It is decoration and carries no meaning, so it is
/// exempt from the colourblind-safe rule that governs gain/loss colours — but
/// it also never stands alone, since the certificate says everything in words.
abstract final class CertificateGold {
  static const Color deep = Color(0xFF8A6A1F);
  static const Color mid = Color(0xFFC9A227);
  static const Color bright = Color(0xFFF2D57E);
  static const Color pale = Color(0xFFFFF4D2);
}

/// A wax-and-foil style award seal, drawn rather than shipped as an image so it
/// stays crisp at any size and on any screen density — and so printing it does
/// not depend on an asset's resolution.
class CertificateSeal extends StatelessWidget {
  const CertificateSeal({this.size = 92, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      // Room below the disc for the ribbon tails.
      height: size * 1.34,
      child: Semantics(
        label: 'Gold completion seal.',
        excludeSemantics: true,
        child: CustomPaint(painter: _SealPainter()),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset centre = Offset(r, r);

    _paintRibbons(canvas, centre, r);
    _paintScallops(canvas, centre, r);
    _paintDisc(canvas, centre, r);
    _paintStar(canvas, centre, r * 0.34);
  }

  /// Two tails falling from behind the disc.
  void _paintRibbons(Canvas canvas, Offset centre, double r) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (final double dir in <double>[-1, 1]) {
      final Path tail = Path()
        ..moveTo(centre.dx + dir * r * 0.34, centre.dy + r * 0.55)
        ..lineTo(centre.dx + dir * r * 0.72, centre.dy + r * 1.5)
        ..lineTo(centre.dx + dir * r * 0.34, centre.dy + r * 1.28)
        ..lineTo(centre.dx + dir * r * 0.06, centre.dy + r * 1.5)
        ..close();
      paint.color = dir < 0 ? CertificateGold.deep : CertificateGold.mid;
      canvas.drawPath(tail, paint);
    }
  }

  /// The notched outer edge that reads as a pressed foil seal.
  void _paintScallops(Canvas canvas, Offset centre, double r) {
    const int points = 24;
    final Path path = Path();
    for (int i = 0; i < points * 2; i++) {
      final double angle = i * math.pi / points - math.pi / 2;
      final double radius = i.isEven ? r : r * 0.88;
      final Offset p = Offset(
        centre.dx + math.cos(angle) * radius,
        centre.dy + math.sin(angle) * radius,
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[CertificateGold.bright, CertificateGold.deep],
        ).createShader(Rect.fromCircle(center: centre, radius: r)),
    );
  }

  /// The face of the seal, with a raised rim.
  void _paintDisc(Canvas canvas, Offset centre, double r) {
    canvas.drawCircle(
      centre,
      r * 0.8,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            CertificateGold.pale,
            CertificateGold.mid,
            CertificateGold.deep,
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: r * 0.8)),
    );

    // Two thin rings: the engraved border of a struck medal.
    canvas.drawCircle(
      centre,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = CertificateGold.deep.withValues(alpha: 0.75),
    );
    canvas.drawCircle(
      centre,
      r * 0.63,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.02
        ..color = CertificateGold.pale.withValues(alpha: 0.7),
    );
  }

  void _paintStar(Canvas canvas, Offset centre, double radius) {
    const int arms = 5;
    final Path star = Path();
    for (int i = 0; i < arms * 2; i++) {
      final double angle = i * math.pi / arms - math.pi / 2;
      final double rr = i.isEven ? radius : radius * 0.42;
      final Offset p = Offset(
        centre.dx + math.cos(angle) * rr,
        centre.dy + math.sin(angle) * rr,
      );
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = CertificateGold.deep);
  }

  @override
  bool shouldRepaint(_SealPainter oldDelegate) => false;
}

/// A hairline double rule, the frame you expect around a certificate.
class CertificateFrame extends StatelessWidget {
  const CertificateFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CertificateGold.mid, width: 2.5),
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: CertificateGold.mid.withValues(alpha: 0.55),
          ),
        ),
        child: child,
      ),
    );
  }
}
