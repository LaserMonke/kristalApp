import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/app_user.dart';
import '../models/education_level.dart';
import '../repositories/auth_repo.dart';
import 'account_identity.dart';
import 'supabase_error_messages.dart';
import 'supabase_tables.dart';

/// Real authentication against Supabase Auth (Phase 6), behind the same
/// [AuthRepo] interface as the Phase 0 device-only stub. Nothing above the
/// repository layer changes when this is swapped in.
///
/// WHAT LEAVES THE DEVICE: a username, a coarse education band, a password (to
/// Supabase's own hasher — never to us, never stored by us), and learning
/// progress. No email, no birthdate, no contacts, no analytics identifiers
/// (CLAUDE.md rule 6). Supabase Auth needs *some* address, so we derive an
/// unroutable one from the username — see [emailForUsername].
///
/// NO PASSWORD RESET: with no real email there is nowhere to send a reset link.
/// The sign-in screen says so rather than implying recovery exists.
class SupabaseAuthRepo implements AuthRepo {
  SupabaseAuthRepo(this._client) {
    _authSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthState,
      // A dropped realtime/auth socket must not take the app down; the learner
      // keeps the session they already have.
      onError: (Object error) =>
          debugPrint('Auth state stream error: ${error.runtimeType}'),
    );
  }

  final sb.SupabaseClient _client;

  late final StreamSubscription<sb.AuthState> _authSubscription;

  final StreamController<AppUser?> _users =
      StreamController<AppUser?>.broadcast();

  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Stream<AppUser?> authStateChanges() => _users.stream;

  /// Supabase restores any persisted session while `Supabase.initialize` runs,
  /// so by the time this is called the session (if any) is already in hand.
  @override
  Future<AppUser?> restoreSession() async {
    final sb.User? authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final AppUser user = await _resolveUser(authUser);
    _emit(user);
    return user;
  }

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) async {
    final String? problem = UsernameRule.validate(username);
    if (problem != null) throw AuthException(problem);
    final String? weak = PasswordRule.validate(password);
    if (weak != null) throw AuthException(weak);

    // Asked up front so a taken name reads as "already taken" instead of the
    // raw unique-index violation the sign-up trigger would otherwise raise.
    if (!await _isUsernameAvailable(username)) {
      throw const AuthException('That username is already taken.');
    }

    final sb.AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: emailForUsername(username),
        password: password,
        // Read by the `handle_new_user` trigger, which writes the profile row.
        data: <String, dynamic>{
          'username': username.trim(),
          'education_level': educationLevel.name,
        },
      );
    } catch (error) {
      throw AuthException(signUpErrorMessage(error));
    }

    final sb.User? authUser = response.user;
    if (authUser == null) {
      throw const AuthException(
        'Couldn’t create the account right now. Please try again.',
      );
    }
    if (response.session == null) {
      // The project still has "Confirm email" enabled. There is no mailbox to
      // confirm, so sign-up can never complete until it is turned off
      // (DEPLOY.md §1a).
      throw const AuthException(
        'Sign-up is misconfigured: this backend is waiting on an email '
        'confirmation that cannot arrive. Turn off "Confirm email" for the '
        'Email provider in Supabase.',
      );
    }

    final AppUser user = await _resolveUser(authUser);
    _emit(user);
    return user;
  }

  @override
  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async {
    // A username that could never have been registered still gets the generic
    // message — we don't confirm which names exist.
    if (UsernameRule.validate(username) != null) {
      throw const AuthException('Incorrect username or password.');
    }

    final sb.AuthResponse response;
    try {
      response = await _client.auth.signInWithPassword(
        email: emailForUsername(username),
        password: password,
      );
    } catch (error) {
      throw AuthException(signInErrorMessage(error));
    }

    final sb.User? authUser = response.user;
    if (authUser == null) {
      throw const AuthException('Incorrect username or password.');
    }

    final AppUser user = await _resolveUser(authUser);
    _emit(user);
    return user;
  }

  /// Signing out NEVER fails.
  ///
  /// A learner who taps "Sign out" on a shared phone must end up signed out
  /// whatever the network is doing; throwing here would leave them logged in
  /// while looking like it worked. So the server call is best-effort and the
  /// local session is cleared unconditionally.
  @override
  Future<void> signOut() async {
    try {
      // Global first: revokes the refresh token server-side, so a stolen token
      // dies with the sign-out.
      await _client.auth.signOut();
    } catch (error) {
      debugPrint('Global sign-out failed (${error.runtimeType}); local only.');
      try {
        // Clears this device's stored session; the refresh token is left to
        // expire on its own.
        await _client.auth.signOut(scope: sb.SignOutScope.local);
      } catch (_) {
        // Nothing left to try — the emit below still ends the session in-app.
      }
    } finally {
      _emit(null);
    }
  }

  /// Deleting an account, unlike signing out, FAILS LOUDLY.
  ///
  /// `delete_own_account()` takes no arguments — the server reads the caller's
  /// id from the JWT, so this cannot be aimed at another account. The profile,
  /// progress and streak rows cascade from the auth.users delete.
  ///
  /// If the server call throws we rethrow and leave the session alone. A
  /// learner who is told "deleted" while their data is still on the server has
  /// no way to find out otherwise: there is no email on file, so we cannot
  /// write to them, and they cannot sign in to check.
  @override
  Future<void> deleteAccount() async {
    if (_currentUser == null) {
      throw const AuthException('You are not signed in.');
    }

    try {
      await _client.rpc<void>('delete_own_account');
    } catch (error) {
      throw AuthException(deleteAccountErrorMessage(error));
    }

    // The account is gone, so the session cannot be revoked server-side any
    // more. signOut() is best-effort by design and never throws, which is what
    // we want here — the delete already succeeded.
    await signOut();
  }

  /// Keeps [currentUser] in step after a profile edit written by
  /// [SupabaseProfileRepo]. Not part of [AuthRepo] — the controller already has
  /// the updated user; this only stops the cached copy going stale.
  void cacheUser(AppUser user) {
    if (_currentUser?.id != user.id) return;
    _emit(user);
  }

  void _emit(AppUser? user) {
    _currentUser = user;
    if (!_users.isClosed) _users.add(user);
  }

  void _handleAuthState(sb.AuthState authState) {
    switch (authState.event) {
      case sb.AuthChangeEvent.signedOut:
        _emit(null);

      case sb.AuthChangeEvent.signedIn:
      case sb.AuthChangeEvent.initialSession:
      case sb.AuthChangeEvent.userUpdated:
        final sb.User? authUser = authState.session?.user;
        if (authUser == null) {
          // A null session here is startup with nobody signed in — emit that
          // ONCE. It must never undo a sign-in that just happened: the
          // `initialSession` event can arrive asynchronously, after an
          // interactive sign-in has already emitted a user, and downgrading
          // back to null is exactly the "have to sign in twice" bug. Only an
          // explicit `signedOut` ends an established session.
          if (_currentUser == null) _emit(null);
          return;
        }
        // Sign-in/sign-up already emitted a fully resolved user; re-resolving
        // here would only duplicate it.
        if (_currentUser?.id == authUser.id) return;
        _resolveUser(authUser).then(_emit).catchError((Object _) {});

      case sb.AuthChangeEvent.tokenRefreshed:
      case sb.AuthChangeEvent.passwordRecovery:
      case sb.AuthChangeEvent.mfaChallengeVerified:
      // ignore: deprecated_member_use
      case sb.AuthChangeEvent.userDeleted:
        // Session housekeeping — the learner's identity is unchanged.
        break;
    }
  }

  /// The [AppUser] for an authenticated Supabase user.
  ///
  /// Prefers the `profiles` row (the source of truth, editable in the app) and
  /// falls back to the sign-up metadata carried in the JWT. That fallback is
  /// what lets a learner open the app on a plane: the session is local, so the
  /// profile read fails but the identity is still known.
  Future<AppUser> _resolveUser(sb.User authUser) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(Db.profiles)
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      if (row != null) return appUserFromProfileRow(row);

      // No row: the sign-up trigger is missing or was added after this account.
      // Heal it from metadata so the rest of the app has something to key on.
      final AppUser fromToken = _userFromToken(authUser);
      await _client.from(Db.profiles).upsert(<String, dynamic>{
        'id': fromToken.id,
        'username': fromToken.username,
        'education_level': fromToken.educationLevel.name,
      });
      return fromToken;
    } catch (error) {
      debugPrint('Profile unavailable (${error.runtimeType}); using session.');
      return _userFromToken(authUser);
    }
  }

  AppUser _userFromToken(sb.User authUser) {
    final Map<String, dynamic> meta =
        authUser.userMetadata ?? const <String, dynamic>{};

    return AppUser(
      id: authUser.id,
      username:
          (meta['username'] as String?)?.trim().nullIfEmpty ??
          usernameFromEmail(authUser.email) ??
          'learner',
      educationLevel: EducationLevel.fromName(meta['education_level'] as String?),
      createdAt:
          DateTime.tryParse(authUser.createdAt)?.toLocal() ?? DateTime.now(),
    );
  }

  Future<bool> _isUsernameAvailable(String username) async {
    try {
      final dynamic taken = await _client.rpc<dynamic>(
        Db.usernameAvailableFn,
        params: <String, dynamic>{'candidate': username.trim()},
      );
      // Anything other than an explicit `false` is treated as available: if the
      // helper function is missing we must not block sign-up, and the unique
      // index still has the final say.
      return taken != false;
    } catch (error) {
      if (isOfflineError(error)) {
        throw AuthException(signUpErrorMessage(error));
      }
      debugPrint('username_available unavailable: ${error.runtimeType}');
      return true;
    }
  }

  void dispose() {
    _authSubscription.cancel();
    _users.close();
  }
}

/// Builds an [AppUser] from a `profiles` row. Shared with [SupabaseProfileRepo].
AppUser appUserFromProfileRow(Map<String, dynamic> row) {
  return AppUser(
    id: row['id'] as String,
    username: (row['username'] as String?)?.trim() ?? 'learner',
    educationLevel: EducationLevel.fromName(row['education_level'] as String?),
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

extension _NullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
