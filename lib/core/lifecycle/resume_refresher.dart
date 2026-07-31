import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/market_providers.dart';

/// Refetches anything time-sensitive when the app comes back to the foreground.
///
/// The market feed polls on a timer, and the OS stops timers the moment the app
/// is backgrounded. Without this, reopening the app leaves the last prices
/// fetched before it was put down sitting on screen — possibly hours old, and
/// indistinguishable from current ones — until the loop happens to tick again.
/// Positions would be marked against them, so the portfolio would be wrong too,
/// not just the quote list.
///
/// Invalidating the quote provider restarts its loop, which fetches
/// immediately. It is `autoDispose`, so when the Market tab is not open there
/// is nothing alive to invalidate and this costs nothing.
class ResumeRefresher extends ConsumerStatefulWidget {
  const ResumeRefresher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ResumeRefresher> createState() => _ResumeRefresherState();
}

class _ResumeRefresherState extends ConsumerState<ResumeRefresher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(quotesProvider);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
