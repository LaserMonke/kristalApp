import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_controller.dart';

/// App-bar button cycling system → light → dark → system.
///
/// CLAUDE.md requires both themes with a toggle; keeping it in the app bar of
/// every tab means it is always one tap away.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeControllerProvider);

    final (IconData icon, String label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_outlined, 'Theme: system'),
      ThemeMode.light => (Icons.light_mode_outlined, 'Theme: light'),
      ThemeMode.dark => (Icons.dark_mode_outlined, 'Theme: dark'),
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: '$label — tap to change',
      onPressed: () => ref.read(themeControllerProvider.notifier).toggle(),
    );
  }
}
