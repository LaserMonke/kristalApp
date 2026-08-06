import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/reminder_controller.dart';

/// Bottom-tab scaffold wrapping the four top-level destinations.
///
/// Uses `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack and scroll position when the learner switches away.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The shell only exists once the disclaimer is acknowledged and someone
    // is signed in — the right moment for the reminder controller's one-time
    // first-run setup (default schedule + OS permission prompt), rather than
    // interrupting the disclaimer or sign-in screens.
    ref.watch(reminderControllerProvider);

    return Scaffold(
      body: _SwipeBetweenTabs(
        index: navigationShell.currentIndex,
        count: _destinations.length,
        onGo: (int index) => navigationShell.goBranch(index),
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) => navigationShell.goBranch(
          index,
          // Tapping the active tab pops it back to its root.
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: _destinations
            .map(
              (_Destination d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
                tooltip: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Sideways swiping between the four tabs, in both directions.
///
/// The shell is an `IndexedStack`, not a `PageView` — that is what lets each
/// tab keep its own navigation stack — so there is no page scroll to ride.
/// The gesture is read directly instead and turned into `goBranch`.
///
/// Two tabs already own the horizontal axis: Learn (Lessons/Ranks) and Sandbox
/// (Single option/Strategy/Advanced) both hold a `TabBarView`. Those win the
/// gesture, which is correct — a swipe inside them should move their tabs. So
/// they are handled the other way round: when their inner tabs run out and the
/// finger keeps going, that overscroll carries on into the next outer tab. The
/// same idea as the lesson deck, on the other axis.
///
/// Anything that claims a horizontal drag for itself still wins outright,
/// because it sits deeper in the tree — the sliders in the pricer, and the
/// draggable spot marker on a payoff diagram.
class _SwipeBetweenTabs extends StatefulWidget {
  const _SwipeBetweenTabs({
    required this.index,
    required this.count,
    required this.onGo,
    required this.child,
  });

  final int index;
  final int count;
  final ValueChanged<int> onGo;
  final Widget child;

  @override
  State<_SwipeBetweenTabs> createState() => _SwipeBetweenTabsState();
}

class _SwipeBetweenTabsState extends State<_SwipeBetweenTabs> {
  /// Horizontal distance travelled in the current drag.
  double _dragged = 0;

  /// Horizontal overscroll accumulated past the edge of an inner TabBarView.
  double _beyond = 0;
  bool _turned = false;

  /// Enough travel to be meant, in logical pixels.
  static const double _minTravel = 64;

  /// Or a flick, which is short but fast.
  static const double _minFlick = 380;

  /// Overscroll needed before an inner tab hands over to the outer one. Higher
  /// than the deck's, because arriving at the last inner tab and continuing is
  /// a bigger claim than reaching the end of a card.
  static const double _handover = 56;

  void _step(int direction) {
    final int next = widget.index + direction;
    if (next < 0 || next >= widget.count) return;
    widget.onGo(next);
  }

  bool _onScroll(Notification note) {
    if (note is ScrollStartNotification || note is ScrollEndNotification) {
      _beyond = 0;
      _turned = false;
    } else if (note is OverscrollNotification && !_turned) {
      // Only sideways overscroll, and only from a finger still on the glass.
      if (note.metrics.axis != Axis.horizontal) return false;
      if (note.dragDetails == null) return false;

      _beyond += note.overscroll;
      if (_beyond.abs() > _handover) {
        _turned = true;
        _step(_beyond > 0 ? 1 : -1);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: _onScroll,
      child: GestureDetector(
        // Only claims drags that nothing inside wanted.
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragged = 0,
        onHorizontalDragUpdate: (DragUpdateDetails d) =>
            _dragged += d.primaryDelta ?? 0,
        onHorizontalDragEnd: (DragEndDetails d) {
          final double velocity = d.velocity.pixelsPerSecond.dx;
          final bool travelled = _dragged.abs() > _minTravel;
          final bool flicked = velocity.abs() > _minFlick;
          if (!travelled && !flicked) return;
          // Dragging left moves forward through the tabs.
          _step((travelled ? _dragged : velocity) < 0 ? 1 : -1);
        },
        child: _TabChangeSlide(index: widget.index, child: widget.child),
      ),
    );
  }
}

/// Slides the arriving tab in from the side it came from.
///
/// The shell is an `IndexedStack`: switching branches swaps the visible child
/// with no motion at all, so a swipe felt like a cut rather than a movement and
/// gave no clue which direction had been travelled. Only the incoming tab is
/// animated — the outgoing one is already gone by the time this rebuilds, and
/// faking its exit would mean holding a second copy of a live tab on screen.
///
/// Short and slight on purpose: this runs on every tab change including the
/// nav-bar taps, so it has to stay out of the way of someone moving quickly.
class _TabChangeSlide extends StatefulWidget {
  const _TabChangeSlide({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabChangeSlide> createState() => _TabChangeSlideState();
}

class _TabChangeSlideState extends State<_TabChangeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  /// Which way the new tab travels: positive comes from the right.
  double _from = 1;

  @override
  void didUpdateWidget(_TabChangeSlide old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _from = widget.index > old.index ? 1 : -1;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> eased = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: eased,
      builder: (BuildContext context, Widget? child) {
        final double t = 1 - eased.value;
        return Opacity(
          // Never fully transparent: a tab that blinks out reads as a reload.
          opacity: 1 - t * 0.5,
          child: FractionalTranslation(
            translation: Offset(_from * t * 0.12, 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

const List<_Destination> _destinations = <_Destination>[
  _Destination('Home', Icons.home_outlined, Icons.home),
  _Destination('Learn', Icons.school_outlined, Icons.school),
  _Destination('Sandbox', Icons.tune_outlined, Icons.tune),
  _Destination('Market', Icons.show_chart_outlined, Icons.show_chart),
];

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
