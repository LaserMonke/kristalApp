import 'package:shared_preferences/shared_preferences.dart';

/// Whether this INSTALL has acknowledged the educational-only disclaimer
/// (CLAUDE.md rule 1).
///
/// Deliberately device-scoped rather than per-account, and therefore identical
/// under both the local and the Supabase profile repositories: the disclaimer
/// must be shown before there is any account to attach it to, and switching
/// accounts on a shared phone should not re-gate someone who has already read
/// it. It is still reachable from Settings at any time.
class DisclaimerStore {
  const DisclaimerStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = 'onboarding.disclaimer_accepted';

  bool get accepted => _prefs.getBool(key) ?? false;

  Future<void> setAccepted(bool accepted) => _prefs.setBool(key, accepted);
}
