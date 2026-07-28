import '../models/app_user.dart';
import '../models/education_level.dart';

/// Authentication boundary.
///
/// Phase 0 ships [LocalAuthRepo] (device-only, no network). Phase 6 adds a
/// Supabase implementation behind this same interface — the UI must not change
/// when that swap happens, so keep this surface free of any backend types.
abstract interface class AuthRepo {
  /// The signed-in user, or null. Emits on sign-in/sign-out.
  Stream<AppUser?> authStateChanges();

  /// Current user without waiting on the stream.
  AppUser? get currentUser;

  /// Restore a previously persisted session, if any.
  Future<AppUser?> restoreSession();

  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  });

  Future<AppUser> signIn({
    required String username,
    required String password,
  });

  Future<void> signOut();
}

/// Auth failure with a message safe to show a learner verbatim.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
