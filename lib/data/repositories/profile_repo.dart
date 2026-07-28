import '../models/app_user.dart';
import '../models/education_level.dart';

/// Profile data that is not authentication state: display name, education
/// level, and app preferences that should follow the user across devices once
/// the Supabase implementation lands (Phase 6).
abstract interface class ProfileRepo {
  Future<AppUser?> loadProfile(String userId);

  Future<AppUser> updateProfile({
    required String userId,
    String? username,
    EducationLevel? educationLevel,
  });

  /// True once the learner has seen and acknowledged the educational-only
  /// disclaimer (CLAUDE.md rule 1). Device-scoped, not per-user, so it is
  /// shown once per install rather than once per account.
  Future<bool> hasAcceptedDisclaimer();

  Future<void> setDisclaimerAccepted({required bool accepted});
}
