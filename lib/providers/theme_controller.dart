import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

/// Light / dark / follow-system, persisted on device.
class ThemeController extends Notifier<ThemeMode> {
  static const String _key = 'settings.theme_mode';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ThemeMode build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere(
      (ThemeMode mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_key, mode.name);
  }

  /// Cycles system → light → dark → system, for the app-bar toggle.
  Future<void> toggle() {
    return set(switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    });
  }
}

final NotifierProvider<ThemeController, ThemeMode> themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
