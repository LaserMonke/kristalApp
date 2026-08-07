import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/reminder_controller.dart';

/// Bottom-tab scaffold wrapping the four top-level destinations.
///
/// Each tab keeps its own navigation stack and scroll position when the
/// learner switches away. The sideways sliding between them lives in
/// `TabPager`, the shell route's Navigator container.
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
      body: navigationShell,
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
