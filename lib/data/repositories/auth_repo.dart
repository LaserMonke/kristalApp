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

  /// Permanently deletes the signed-in account and everything attached to it,
  /// then ends the session.
  ///
  /// Required by Google Play for any app that offers account creation. Unlike
  /// [signOut] this MUST fail loudly: telling a learner their account is gone
  /// when the server never heard the request is the one outcome worse than an
  /// error message, because we hold no email and cannot follow up.
  ///
  /// There is no undo and no recovery — with no address on file we cannot even
  /// verify a change of mind. Callers must confirm before calling.
  Future<void> deleteAccount();
}

/// Auth failure with a message safe to show a learner verbatim.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
