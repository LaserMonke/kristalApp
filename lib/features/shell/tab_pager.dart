import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lays the four tabs out side by side and slides between them.
///
/// `StatefulShellRoute.indexedStack` — what this replaces — swaps the visible
/// branch with no motion at all, so changing tab read as a cut. Here every
/// branch Navigator is kept alive in a [Stack] (so each tab holds its own
/// stack and scroll position, exactly as the IndexedStack did) and simply
/// offset sideways, one screen width apart. Moving between tabs then means
/// moving that offset, which a drag can do live under the finger and a tap on
/// the nav bar can animate.
///
/// The offset is measured in pages, relative to the current branch: 0 shows
/// the current tab, +1 has the next tab fully on screen, -1 the previous. Only
/// the current index comes from the router, so when a drag decides on a new
/// tab it hands over to `goBranch` and then carries the same visual position
/// across the rebuild ([didUpdateWidget]) instead of snapping.
///
/// Two tabs already own the horizontal axis: Learn (Lessons/Ranks) and Sandbox
/// (Single option/Strategy/Advanced) both hold a `TabBarView`. Those win the
/// gesture, which is correct — a swipe inside them should move their tabs. So
/// they are handled the other way round: when their inner tabs run out and the
/// finger keeps going, that overscroll carries on into the next outer tab.
///
/// Anything that claims a horizontal drag for itself still wins outright,
/// because it sits deeper in the tree — the sliders in the pricer, and the
/// draggable spot marker on a payoff diagram.
class TabPager extends StatefulWidget {
  const TabPager({required this.shell, required this.branches, super.key});

  /// The shell, for the current branch index and to change it.
  final StatefulNavigationShell shell;

  /// One Navigator per tab, in branch order. All stay in the tree.
  final List<Widget> branches;

  @override
  State<TabPager> createState() => _TabPagerState();
}

class _TabPagerState extends State<TabPager>
    with SingleTickerProviderStateMixin {
  /// Where the pages sit right now, in screen widths away from the current
  /// branch. Positive means the next tab is coming in from the right.
  double _offset = 0;

  /// Offset the settle animation started from, so it can ease back to 0.
  double _settleFrom = 0;

  /// The branch index this state last drew, to spot a change in
  /// [didUpdateWidget] — `oldWidget.shell` is a fresh object each build and
  /// cannot be trusted to still report the previous index.
  late int _index = widget.shell.currentIndex;

  /// Horizontal overscroll accumulated past the edge of an inner TabBarView.
  double _beyond = 0;
  bool _turned = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(_onSettle);

  /// Fraction of a page that has to be dragged for the tab to change on
  /// release. Below it, the page springs back.
  static const double _commit = 0.28;

  /// Or a flick, which is short but fast, in pixels per second.
  static const double _minFlick = 380;

  /// Overscroll needed before an inner tab hands over to the outer one. Higher
  /// than the deck's, because arriving at the last inner tab and continuing is
  /// a bigger claim than reaching the end of a card.
  static const double _handover = 56;

  int get _count => widget.branches.length;

  void _onSettle() {
    final double eased = Curves.easeOutCubic.transform(_settle.value);
    setState(() => _offset = _settleFrom * (1 - eased));
  }

  void _settleToRest() {
    _settleFrom = _offset;
    if (_settleFrom == 0) return;
    _settle.forward(from: 0);
  }

  /// Moves [direction] tabs along, if there is a tab there.
  void _step(int direction) {
    final int next = _index + direction;
    if (next < 0 || next >= _count) return;
    widget.shell.goBranch(next);
  }

  @override
  void didUpdateWidget(TabPager old) {
    super.didUpdateWidget(old);
    final int now = widget.shell.currentIndex;
    if (now == _index) return;

    // The offset is measured from the current branch, so re-basing it onto the
    // new one keeps every page exactly where it was drawn a frame ago. A drag
    // released at 0.4 of the way to the next tab becomes -0.6 from that tab,
    // and the settle finishes the same movement rather than restarting it.
    _offset += _index - now;
    _index = now;
    _settleToRest();
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
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

  void _onDragStart() {
    _settle.stop();
  }

  void _onDragUpdate(double delta, double width) {
    if (width <= 0) return;
    setState(() {
      // Dragging left moves forward through the tabs.
      _offset = (_offset - delta / width).clamp(
        // Nothing past the first or last tab: there is no page out there, and
        // dragging into the void reads as the app having lost a screen.
        -_index.toDouble(),
        (_count - 1 - _index).toDouble(),
      );
    });
  }

  void _onDragEnd(double velocity) {
    final bool flicked = velocity.abs() > _minFlick;
    final int direction = flicked
        ? (velocity < 0 ? 1 : -1)
        : _offset.abs() > _commit
        ? _offset.sign.toInt()
        : 0;

    final int target = (_index + direction).clamp(0, _count - 1);
    if (direction == 0 || target == _index) {
      _settleToRest();
      return;
    }
    // goBranch comes back through didUpdateWidget, which re-bases the offset
    // and starts the settle from there.
    widget.shell.goBranch(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;

        return NotificationListener<Notification>(
          onNotification: _onScroll,
          child: GestureDetector(
            // Only claims drags that nothing inside wanted.
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _onDragStart(),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _onDragUpdate(d.primaryDelta ?? 0, width),
            onHorizontalDragEnd: (DragEndDetails d) =>
                _onDragEnd(d.velocity.pixelsPerSecond.dx),
            // The pages are moved by a Transform, which a Stack does not count
            // as overflow, so the clip has to be asked for explicitly — without
            // it a half-dragged tab would paint outside the body.
            child: ClipRect(
              child: Stack(
                children: <Widget>[
                  for (int i = 0; i < _count; i++)
                    _page(i, (i - _index - _offset) * width, width),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _page(int i, double dx, double width) {
    // A page more than a screen away cannot be seen. Offstage keeps it in the
    // tree — its Navigator, its state and its scroll position all survive —
    // while skipping its paint and semantics, and the TickerMode stops its
    // animations, so idle tabs cost nothing while another is being used. This
    // is what `StatefulShellRoute.indexedStack` wraps its own children in.
    final bool hidden = dx.abs() >= width;

    return Positioned.fill(
      child: Offstage(
        offstage: hidden,
        child: TickerMode(
          enabled: !hidden,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: widget.branches[i],
          ),
        ),
      ),
    );
  }
}
