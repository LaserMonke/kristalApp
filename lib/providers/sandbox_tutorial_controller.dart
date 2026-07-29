import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

/// Whether the learner has already seen the Sandbox's one-time walkthrough.
///
/// A simple persisted UI flag, not a domain concept — same pattern as
/// [ThemeController] rather than the repository-interface pattern used for
/// data that Phase 6 swaps onto Supabase (auth, progress).
class SandboxTutorialController extends Notifier<bool> {
  static const String _key = 'sandbox.tutorial_seen';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> markSeen() async {
    state = true;
    await _prefs.setBool(_key, true);
  }
}

final NotifierProvider<SandboxTutorialController, bool> sandboxTutorialSeenProvider =
    NotifierProvider<SandboxTutorialController, bool>(SandboxTutorialController.new);
