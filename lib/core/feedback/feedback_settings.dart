import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';

/// Whether the app vibrates on significant actions.
///
/// On by default — a short tick confirming a trade filled or an answer landed
/// is genuinely useful, and it is the kind of feedback people expect. Off in
/// one tap from Settings, because haptics are unpleasant for some learners and
/// nothing in the app may depend on feeling them (CLAUDE.md rule 9,
/// accessibility).
class HapticsController extends Notifier<bool> {
  static const String _key = 'haptics_enabled_v1';

  @override
  bool build() => _readFlag(ref, _key, fallback: true);

  Future<void> set(bool enabled) async {
    state = enabled;
    await _writeFlag(ref, _key, enabled);
  }
}

final NotifierProvider<HapticsController, bool> hapticsEnabledProvider =
    NotifierProvider<HapticsController, bool>(HapticsController.new);

/// Whether the intro chime plays when the app opens.
///
/// On by default so the app has an identity when it starts, off in one tap.
/// It plays once per launch and never anywhere else — no sound is attached to
/// streaks, reminders or anything else that could nag.
class IntroSoundController extends Notifier<bool> {
  static const String _key = 'intro_sound_enabled_v1';

  @override
  bool build() => _readFlag(ref, _key, fallback: true);

  Future<void> set(bool enabled) async {
    state = enabled;
    await _writeFlag(ref, _key, enabled);
  }
}

final NotifierProvider<IntroSoundController, bool> introSoundEnabledProvider =
    NotifierProvider<IntroSoundController, bool>(IntroSoundController.new);

/// Storage is optional for these two settings, and only these two.
///
/// A buzz and a chime are decoration: a screen that shows a quiz question must
/// not fail to build because preferences are unavailable. Everywhere else in
/// the app a missing store is a real error and should surface as one — here it
/// just means "use the default".
bool _readFlag(Ref ref, String key, {required bool fallback}) {
  try {
    return ref.watch(sharedPreferencesProvider).getBool(key) ?? fallback;
  } catch (_) {
    return fallback;
  }
}

Future<void> _writeFlag(Ref ref, String key, bool value) async {
  try {
    await ref.read(sharedPreferencesProvider).setBool(key, value);
  } catch (_) {
    // Setting stays in memory for this session; nothing else depends on it.
  }
}
