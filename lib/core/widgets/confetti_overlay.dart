import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A one-shot confetti burst, drawn with a CustomPainter.
///
/// No package: this is a few dozen rectangles under gravity, which a painter
/// does perfectly well and which keeps a dependency out of the build for the
/// sake of a decoration.
///
/// Three things it deliberately does NOT do. It never blocks touches, so the
/// screen underneath stays usable while it falls. It never repeats — a
/// celebration that keeps going is a nag, and levelling up should feel like an
/// acknowledgement rather than a slot machine (CLAUDE.md rule 9). And it
/// carries no information: everything it marks is also stated in words on the
/// screen beneath, so a learner who never sees it has missed nothing.
///
/// Honours the platform's reduce-motion setting by not animating at all.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({
    required this.child,
    required this.play,
    this.onFinished,
    super.key,
  });

  /// The screen the confetti falls over.
  final Widget child;

  /// Flipping this to true starts one burst. Flipping it back and forth does
  /// not restart it — a burst happens once per mount.
  final bool play;

  final VoidCallback? onFinished;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _fall = Duration(milliseconds: 2600);
  static const int _pieceCount = 46;

  // Built eagerly rather than lazily. A `late final` initialiser would be
  // constructed by dispose() on an overlay that never played, and creating a
  // ticker while the element is deactivated throws.
  late final AnimationController _controller;

  List<_Piece> _pieces = const <_Piece>[];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _fall);
    if (widget.play) _start();
  }

  @override
  void didUpdateWidget(ConfettiOverlay old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _start();
  }

  void _start() {
    if (_started) return;
    _started = true;

    final math.Random rng = math.Random();
    _pieces = <_Piece>[
      for (int i = 0; i < _pieceCount; i++) _Piece.random(rng),
    ];
    _controller.forward().whenComplete(() {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Someone who has asked the OS to reduce motion has asked for exactly
    // this: no falling confetti. The level-up is still announced in words.
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    if (!_started || reduceMotion) return widget.child;

    final ColorScheme scheme = Theme.of(context).colorScheme;
    // A spread rather than one hue, so it reads as celebration and not as a
    // status colour. It means nothing, so no palette rule applies.
    final List<Color> palette = <Color>[
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
    ];

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          // Decoration only: it must never eat a tap meant for the button
          // underneath, and a screen reader should not announce it at all.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, Widget? _) => CustomPaint(
                    painter: _ConfettiPainter(
                      pieces: _pieces,
                      progress: _controller.value,
                      palette: palette,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One piece of confetti, in fractions of the screen so it scales to any size.
class _Piece {
  const _Piece({
    required this.startX,
    required this.startY,
    required this.driftX,
    required this.spin,
    required this.size,
    required this.aspect,
    required this.delay,
    required this.colorIndex,
    required this.isRound,
  });

  factory _Piece.random(math.Random rng) => _Piece(
    startX: rng.nextDouble(),
    // Start just above the top edge, staggered, so they enter rather than
    // appear.
    startY: -0.1 - rng.nextDouble() * 0.35,
    driftX: (rng.nextDouble() - 0.5) * 0.45,
    spin: (rng.nextDouble() - 0.5) * 10,
    size: 6 + rng.nextDouble() * 8,
    aspect: 0.4 + rng.nextDouble() * 0.9,
    delay: rng.nextDouble() * 0.25,
    colorIndex: rng.nextInt(5),
    isRound: rng.nextBool(),
  );

  final double startX;
  final double startY;
  final double driftX;
  final double spin;
  final double size;
  final double aspect;
  final double delay;
  final int colorIndex;
  final bool isRound;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.pieces,
    required this.progress,
    required this.palette,
  });

  final List<_Piece> pieces;
  final double progress;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (final _Piece piece in pieces) {
      // Each piece runs its own clock, offset by its delay.
      final double t = ((progress - piece.delay) / (1 - piece.delay)).clamp(
        0.0,
        1.0,
      );
      if (t <= 0) continue;

      // Accelerating fall with a sideways drift, so it does not read as a
      // sheet of rain dropping in lockstep.
      final double y = piece.startY + t * t * 1.55;
      if (y > 1.15) continue;
      final double x = piece.startX + piece.driftX * t;

      // Fade out over the last third rather than vanishing mid-air.
      final double fade = t < 0.65 ? 1.0 : 1.0 - (t - 0.65) / 0.35;
      paint.color = palette[piece.colorIndex % palette.length].withValues(
        alpha: fade.clamp(0.0, 1.0),
      );

      final Offset centre = Offset(x * size.width, y * size.height);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(piece.spin * t);

      if (piece.isRound) {
        canvas.drawCircle(Offset.zero, piece.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * piece.aspect,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.pieces != pieces;
}
