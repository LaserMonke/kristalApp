/// Where a learner's data actually lives, in one place.
///
/// The app runs in two modes — on-device only, or synced to the Supabase
/// backend — and CLAUDE.md rule 8 (data honesty) means the copy has to say
/// which one is in force rather than describing whichever mode was true when
/// the sentence was written. Every screen that mentions storage reads from
/// here, keyed on `isCloudBackedProvider`.
library;

abstract final class DataLocation {
  // ------------------------------------------------------------ sign-in

  static const String accountsLocal =
      'Accounts are stored on this device only — nothing is uploaded.';

  static const String accountsCloud =
      'Your account and progress are saved to the OptionsSchool server so they '
      'follow you to a new device. We hold no email address, so a forgotten '
      'password cannot be reset — keep it somewhere safe.';

  static String accounts({required bool cloudBacked}) =>
      cloudBacked ? accountsCloud : accountsLocal;

  // ------------------------------------------------------------ settings

  static const String collectedLocal =
      'Username and education level. Stored on this device.';

  static const String collectedCloud =
      'Username and education level. Synced to your account.';

  static String collected({required bool cloudBacked}) =>
      cloudBacked ? collectedCloud : collectedLocal;

  /// The long form, shown in Settings → "Data we collect".
  static const String privacyLocal =
      'A username, a password you choose, and a coarse education level. '
      'Nothing else — no email, no date of birth, no contacts, no advertising '
      'identifiers.\n\n'
      'All of it stays on this device. Nothing is sent anywhere.';

  static const String privacyCloud =
      'A username, a password you choose, and a coarse education level. '
      'Nothing else — no email, no date of birth, no contacts, no advertising '
      'identifiers.\n\n'
      'Those three things and your learning progress (lessons finished, Q&A '
      'scores, points, streak) are stored on our server so your account works '
      'on more than one device. Your password is never stored by us in a '
      'readable form. Only you can read your own rows.\n\n'
      'Your progress is also kept on this device, so the app works offline and '
      'syncs when you are back online.\n\n'
      'Visible to other learners: your username and your point total, on the '
      'Ranks leaderboard. Nothing else about you is shared — not your study '
      'level, not which lessons you got wrong.\n\n'
      'A full privacy policy will be published and linked here before release '
      '— data now leaves the device, so that is a requirement, not a plan.';

  static String privacy({required bool cloudBacked}) =>
      cloudBacked ? privacyCloud : privacyLocal;

  // ------------------------------------------------------------ reset

  static const String resetLocal =
      'Lesson progress, Q&A scores, points and your streak on this device will '
      'be wiped. This cannot be undone.';

  static const String resetCloud =
      'Lesson progress, Q&A scores, points and your streak will be wiped on '
      'this device and on the server. This cannot be undone.';

  static String reset({required bool cloudBacked}) =>
      cloudBacked ? resetCloud : resetLocal;
}
