import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A pushed screen that a sideways drag pushes back off, following the finger.
///
/// Used by Settings, which opens from the gear in the top-LEFT and so slides in
/// from the left rather than the usual right. That leaves no obvious way back
/// out by gesture: the app-wide swipe-back only fires on release, with no sign
/// while the finger is down that anything is happening.
///
/// So this takes the drag itself. It moves with the finger either way — right
/// as on any other screen, or left, back the way the panel arrived — and past
/// [_minTravel] (or on a flick) the panel carries on off that edge and pops.
/// Short of that it springs back, which is the point of following the finger:
/// a half-swipe shows what it would do and lets you change your mind.
///
/// Being a descendant of the app-wide swipe-back in `app.dart`, this wins the
/// gesture arena, so the two never both fire.
class SwipeAwayPanel extends StatefulWidget {
  const SwipeAwayPanel({required this.child, super.key});

  final Widget child;

  @override
  State<SwipeAwayPanel> createState() => _SwipeAwayPanelState();
}

class _SwipeAwayPanelState extends State<SwipeAwayPanel>
    with SingleTickerProviderStateMixin {
  /// How far the panel is currently pushed aside, in logical pixels.
  double _dx = 0;

  double _from = 0;
  double _to = 0;

  /// Set once the panel is on its way out, so the animation ends in a pop
  /// rather than at rest.
  bool _leaving = false;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(_onTick);

  /// Enough travel to be meant. Matches the app-wide swipe-back: leaving a
  /// screen should take a little more asking than changing tab.
  static const double _minTravel = 90;
  static const double _minFlick = 500;

  void _onTick() {
    setState(() {
      _dx = lerpDouble(
        _from,
        _to,
        Curves.easeOutCubic.transform(_slide.value),
      )!;
    });
    if (_slide.isCompleted && _leaving && mounted) {
      // The route's own reverse transition runs from here, on a panel already
      // off the screen, so there is nothing left to see of it.
      context.pop();
    }
  }

  void _animateTo(double target) {
    _from = _dx;
    _to = target;
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        if (_leaving) return;
        _slide.stop();
      },
      onHorizontalDragUpdate: (DragUpdateDetails d) {
        if (_leaving) return;
        setState(() => _dx += d.primaryDelta ?? 0);
      },
      onHorizontalDragEnd: (DragEndDetails d) {
        if (_leaving) return;
        final double velocity = d.velocity.pixelsPerSecond.dx;
        final bool travelled = _dx.abs() > _minTravel;
        final bool flicked = velocity.abs() > _minFlick;
        if (!travelled && !flicked) {
          _animateTo(0);
          return;
        }
        // Off the edge it was heading for — the flick wins over the distance,
        // so a fast reversal does not throw the panel the wrong way.
        final double direction = flicked ? velocity.sign : _dx.sign;
        _leaving = true;
        _animateTo(direction * width);
      },
      child: Transform.translate(offset: Offset(_dx, 0), child: widget.child),
    );
  }
}
