import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/lifecycle/resume_refresher.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_controller.dart';

/// Root widget: themes + router. Everything else hangs off the router.
class OptionsSchoolApp extends ConsumerWidget {
  const OptionsSchoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeControllerProvider);

    return ResumeRefresher(
      child: MaterialApp.router(
        title: 'Stock Options Academy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) =>
            _SwipeBackAnywhere(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Swipe right anywhere on a pushed screen to go back.
///
/// The Cupertino page transition already gives a drag-to-dismiss, but only
/// from a ~20px strip at the screen edge, which is easy to miss and awkward on
/// a large phone. This catches the same gesture anywhere across the screen.
///
/// It sits ABOVE the router, so every gesture inside the app gets first claim
/// and this only ever sees what nothing else wanted:
///   - the sideways tab swiping in the shell still switches tabs, because that
///     detector is a descendant and wins the arena;
///   - the pricer sliders, the payoff diagram's draggable spot marker and the
///     inner TabBarViews all keep their drags for the same reason;
///   - the Cupertino edge drag still handles edge starts, with its live
///     follow-the-finger transition.
///
/// And it does nothing at all unless there is something to pop, so on the
/// shell's own tabs — where nothing has been pushed — it stays out of the way.
class _SwipeBackAnywhere extends StatefulWidget {
  const _SwipeBackAnywhere({required this.child});

  final Widget child;

  @override
  State<_SwipeBackAnywhere> createState() => _SwipeBackAnywhereState();
}

class _SwipeBackAnywhereState extends State<_SwipeBackAnywhere> {
  double _dragged = 0;

  /// Deliberately longer than the shell's tab swipe. Going back is harder to
  /// undo than changing tab, so it should take a little more asking.
  static const double _minTravel = 90;
  static const double _minFlick = 500;

  void _maybePop() {
    final NavigatorState? navigator = rootNavigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragged = 0,
      onHorizontalDragUpdate: (DragUpdateDetails d) =>
          _dragged += d.primaryDelta ?? 0,
      onHorizontalDragEnd: (DragEndDetails d) {
        final double velocity = d.velocity.pixelsPerSecond.dx;
        // Rightward only. Leftward means "forward", and there is nothing
        // forward to go to.
        final bool travelled = _dragged > _minTravel;
        final bool flicked = velocity > _minFlick && _dragged > 0;
        if (travelled || flicked) _maybePop();
      },
      child: widget.child,
    );
  }
}
