import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-tab scaffold wrapping the four top-level destinations.
///
/// Uses `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack and scroll position when the learner switches away.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
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
  _Destination('Learn', Icons.school_outlined, Icons.school),
  _Destination('Sandbox', Icons.tune_outlined, Icons.tune),
  _Destination('Ranks', Icons.leaderboard_outlined, Icons.leaderboard),
  _Destination('Profile', Icons.person_outline, Icons.person),
];

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
