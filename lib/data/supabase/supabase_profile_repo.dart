import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../local/disclaimer_store.dart';
import '../models/app_user.dart';
import '../models/education_level.dart';
import '../repositories/auth_repo.dart';
import '../repositories/profile_repo.dart';
import 'account_identity.dart';
import 'supabase_auth_repo.dart';
import 'supabase_error_messages.dart';
import 'supabase_tables.dart';

/// Profiles stored in Postgres, so a username or education-level edit follows
/// the learner to a new device (Phase 6).
///
/// Row Level Security means every statement here is implicitly scoped to
/// `auth.uid()`: passing someone else's [userId] returns nothing and updates
/// nothing rather than leaking a row.
///
/// The disclaimer flag stays on the DEVICE — see [DisclaimerStore] for why.
class SupabaseProfileRepo implements ProfileRepo {
  // Named parameters for a readable call site; the fields stay private so
  // nothing outside can reach the raw client. `prefer_initializing_formals`
  // suggests `this._client`, which the language does not allow for a private
  // named parameter.
  const SupabaseProfileRepo({
    required sb.SupabaseClient client,
    required DisclaimerStore disclaimers,
    SupabaseAuthRepo? auth,
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _disclaimers = disclaimers,
       // ignore: prefer_initializing_formals
       _auth = auth;

  final sb.SupabaseClient _client;
  final DisclaimerStore _disclaimers;

  /// Optional: lets a profile edit refresh the cached session user.
  final SupabaseAuthRepo? _auth;

  @override
  Future<AppUser?> loadProfile(String userId) async {
    final Map<String, dynamic>? row = await _client
        .from(Db.profiles)
        .select()
        .eq('id', userId)
        .maybeSingle();

    return row == null ? null : appUserFromProfileRow(row);
  }

  @override
  Future<AppUser> updateProfile({
    required String userId,
    String? username,
    EducationLevel? educationLevel,
  }) async {
    final Map<String, dynamic> patch = <String, dynamic>{};

    if (username != null) {
      final String trimmed = username.trim();
      final String? problem = UsernameRule.validateNew(trimmed);
      if (problem != null) throw AuthException(problem);
      patch['username'] = trimmed;
    }
    if (educationLevel != null) {
      patch['education_level'] = educationLevel.name;
    }

    if (patch.isEmpty) {
      final AppUser? unchanged = await loadProfile(userId);
      if (unchanged == null) throw StateError('No profile for $userId');
      return unchanged;
    }

    final Map<String, dynamic> row;
    try {
      row = await _client
          .from(Db.profiles)
          .update(patch)
          .eq('id', userId)
          .select()
          .single();
    } on sb.PostgrestException catch (error) {
      // 23505 = unique violation, i.e. profiles_username_lower_key.
      if (error.code == '23505') {
        throw const AuthException('That username is already taken.');
      }
      if (isOfflineError(error)) {
        throw const AuthException(
          'Can’t reach the server. Your profile wasn’t changed.',
        );
      }
      rethrow;
    }

    // NOTE: the username lives in two places — the `profiles` row (source of
    // truth, updated above) and the sign-up metadata baked into the auth user.
    // The synthetic sign-in address is derived from the ORIGINAL username and
    // is deliberately left alone: rewriting it would change the credential the
    // learner signs in with. So a renamed learner keeps signing in under the
    // name they registered with. Surface that in the UI when profile editing
    // ships; do not silently change how someone logs in.
    final AppUser updated = appUserFromProfileRow(row);
    _auth?.cacheUser(updated);
    return updated;
  }

  @override
  Future<bool> hasAcceptedDisclaimer() async => _disclaimers.accepted;

  @override
  Future<void> setDisclaimerAccepted({required bool accepted}) =>
      _disclaimers.setAccepted(accepted);
}
