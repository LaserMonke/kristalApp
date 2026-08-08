/// A learner's sign-in, kept on ONE device so they can get back in without
/// retyping it.
///
/// This is the credential itself, not a session: signing out revokes the
/// Supabase session, and the whole point of saving is that signing back in
/// afterwards costs one tap. So what is stored is the username and password,
/// and getting at the password is gated behind the device's own lock (see
/// `DeviceUnlock`).
///
/// HOW SAFE IS THIS, HONESTLY. The credential is written through the platform
/// keystore — AES-GCM under a hardware-backed key on Android, the Keychain
/// pinned to this device on iOS — so it is encrypted at rest and does not
/// travel in a backup to a new phone. The unlock prompt is an app-level gate,
/// not a key binding: it stops someone holding the learner's unlocked phone,
/// which is the threat that actually applies here. It would not stop an
/// attacker who had already fully compromised the device. That is a
/// proportionate bar for an account that unlocks lesson progress and nothing
/// else — no payment details, no email, nothing to steal but a streak — and
/// it is the same bar every "stay signed in" switch in the app store clears.
/// It would NOT be the right bar for a brokerage, which this is not
/// (CLAUDE.md: the app is educational only and never touches real money).
library;

/// The credential pair, only ever held in memory long enough to sign in.
class SavedLogin {
  const SavedLogin({required this.username, required this.password});

  final String username;
  final String password;
}

/// Device-local storage for one saved sign-in.
///
/// One at a time, deliberately: a phone belongs to a person, and offering a
/// list of accounts to unlock would turn a shared family device into a way to
/// browse other people's sign-ins.
abstract interface class SavedLoginStore {
  /// The saved username, or null when this device has none.
  ///
  /// Readable without the unlock prompt, because the sign-in screen has to be
  /// able to say WHO it is offering to sign in before asking for a fingerprint.
  /// The password is the part worth protecting.
  Future<String?> readUsername();

  /// The full credential. Callers must have passed the device unlock first —
  /// this does not prompt on its own.
  Future<SavedLogin?> read();

  Future<void> save(SavedLogin login);

  /// Forgets the saved sign-in. Safe to call when there is none.
  Future<void> clear();
}
