import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/saved_login_store.dart';

/// [SavedLoginStore] over the platform keystore.
///
/// Not shared_preferences, unlike everything else in this folder: the rest of
/// what the app keeps on device is progress and settings, and this is a
/// password.
class SecureSavedLoginStore implements SavedLoginStore {
  const SecureSavedLoginStore(this._storage);

  final FlutterSecureStorage _storage;

  /// The storage this app writes credentials through.
  ///
  /// Android takes the default: AES-GCM under an RSA-wrapped key held in the
  /// Android Keystore. The plugin can also bind the key itself to a biometric
  /// prompt, which is stronger — but that path needs API 28+ and raises its
  /// OWN system prompt, which would mean a learner authenticating twice for one
  /// tap. The gate lives in `DeviceUnlock` instead, so it behaves the same on
  /// every device and prompts exactly once.
  ///
  /// iOS pins the item to this device and to first-unlock: it is unavailable
  /// while the phone is locked, and — the reason for `_this_device` — it is
  /// excluded from iCloud and from an encrypted backup restored onto different
  /// hardware. A saved sign-in should not follow someone onto a phone they no
  /// longer own.
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _usernameKey = 'saved_login.username';
  static const String _passwordKey = 'saved_login.password';

  @override
  Future<String?> readUsername() => _storage.read(key: _usernameKey);

  @override
  Future<SavedLogin?> read() async {
    final String? username = await _storage.read(key: _usernameKey);
    final String? password = await _storage.read(key: _passwordKey);
    // Half a credential is no credential. A partial write (killed mid-save, or
    // a keystore that reset itself after an OS upgrade) should read as "nothing
    // saved" rather than as an empty password the server will reject.
    if (username == null || password == null) return null;
    return SavedLogin(username: username, password: password);
  }

  @override
  Future<void> save(SavedLogin login) async {
    await _storage.write(key: _usernameKey, value: login.username);
    await _storage.write(key: _passwordKey, value: login.password);
  }

  @override
  Future<void> clear() async {
    // Only this app's two keys, never `deleteAll`: the learner's other
    // device-local state is not ours to drop here.
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
