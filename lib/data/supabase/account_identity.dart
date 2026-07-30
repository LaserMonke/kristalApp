/// Maps a learner's USERNAME onto the credentials Supabase Auth expects.
///
/// Supabase Auth's password provider is keyed on an email address, but this app
/// deliberately does not ask for one: the audience may include under-18 users,
/// so we collect the minimum data needed (CLAUDE.md rule 6). Instead each
/// account gets a synthetic address derived from the username, in the reserved
/// `.invalid` TLD (RFC 2606) so it provably cannot route to a real mailbox.
/// Nothing is ever emailed, and no learner ever sees or types this address.
///
/// Consequence to keep in mind: there is no email, so there is no
/// "reset my password" link. A forgotten password means a new account — say so
/// honestly rather than implying recovery exists.
///
/// [usernameDomain] is part of every account's stored identity. Changing it
/// would orphan every existing account, so treat it as frozen.
///
/// Pure Dart: no Flutter and no Supabase imports, so it is unit-testable on its
/// own.
library;

const String usernameDomain = 'users.optionsschool.invalid';

/// Why a username was rejected, in wording safe to show a learner verbatim.
class UsernameRule {
  const UsernameRule._();

  static const int minLength = 3;
  static const int maxLength = 24;

  /// Letters, digits, and the three separators that are safe in an email
  /// local part. No spaces, no unicode look-alikes — two learners should never
  /// be able to pick names that read identically on a leaderboard.
  static final RegExp _allowed = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$');

  /// Null when [username] is acceptable, otherwise the reason why not.
  static String? validate(String username) {
    final String trimmed = username.trim();

    if (trimmed.length < minLength) {
      return 'Username must be at least $minLength characters.';
    }
    if (trimmed.length > maxLength) {
      return 'Username must be $maxLength characters or fewer.';
    }
    if (!_allowed.hasMatch(trimmed)) {
      return 'Use letters, numbers, dots, dashes or underscores — starting '
          'and ending with a letter or number.';
    }
    if (trimmed.contains('..')) {
      return 'Username cannot contain two dots in a row.';
    }
    return null;
  }
}

/// The case-insensitive key for a username. "Alice" and "alice" are one person,
/// matching the `profiles_username_lower_key` index in the schema.
String normaliseUsername(String username) => username.trim().toLowerCase();

/// The synthetic Supabase Auth address for [username].
///
/// Throws [ArgumentError] on a username that failed [UsernameRule.validate] —
/// callers validate first so the learner sees the specific reason instead.
String emailForUsername(String username) {
  final String? problem = UsernameRule.validate(username);
  if (problem != null) throw ArgumentError.value(username, 'username', problem);
  return '${normaliseUsername(username)}@$usernameDomain';
}

/// Recovers the username from a synthetic address, for reading an existing
/// session back. Returns null for anything that is not one of ours.
String? usernameFromEmail(String? email) {
  if (email == null) return null;
  const String suffix = '@$usernameDomain';
  if (!email.endsWith(suffix)) return null;
  final String local = email.substring(0, email.length - suffix.length);
  return local.isEmpty ? null : local;
}

/// Minimum password length. Matches the sign-in form's own validator and the
/// Supabase project's Auth setting — keep all three in step (DEPLOY.md §1a).
const int minPasswordLength = 6;
