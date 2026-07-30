import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/education_level.dart';
import '../repositories/profile_repo.dart';
import 'disclaimer_store.dart';
import 'local_auth_repo.dart';

/// Profile storage backed by the same on-device account records the local auth
/// stub writes, so a username/education-level edit survives a restart.
class LocalProfileRepo implements ProfileRepo {
  LocalProfileRepo(this._prefs, this._auth);

  final SharedPreferences _prefs;
  final LocalAuthRepo _auth;

  @override
  Future<AppUser?> loadProfile(String userId) async => _auth.findById(userId);

  @override
  Future<AppUser> updateProfile({
    required String userId,
    String? username,
    EducationLevel? educationLevel,
  }) async {
    final AppUser? existing = _auth.findById(userId);
    if (existing == null) {
      throw StateError('No local profile for $userId');
    }

    final AppUser updated = existing.copyWith(
      username: username?.trim(),
      educationLevel: educationLevel,
    );
    await _auth.persistProfile(updated);
    return updated;
  }

  @override
  Future<bool> hasAcceptedDisclaimer() async =>
      DisclaimerStore(_prefs).accepted;

  @override
  Future<void> setDisclaimerAccepted({required bool accepted}) =>
      DisclaimerStore(_prefs).setAccepted(accepted);
}
