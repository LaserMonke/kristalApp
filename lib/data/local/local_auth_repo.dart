import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/education_level.dart';
import '../repositories/auth_repo.dart';

/// Device-only mock authentication so the app is fully usable offline in
/// Part A of the build (no server exists yet).
///
/// SECURITY NOTE: passwords here are salted-and-hashed only to avoid storing
/// them in plain text on the device; this is NOT real authentication and gives
/// no protection against anyone with device access. It exists purely so the
/// sign-in flow is exercisable before Supabase Auth replaces it in Phase 6.
/// Nothing sensitive is stored, and no credential ever leaves the device.
class LocalAuthRepo implements AuthRepo {
  LocalAuthRepo(this._prefs);

  final SharedPreferences _prefs;

  static const String _accountsKey = 'auth.accounts';
  static const String _sessionKey = 'auth.session_user_id';

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppUser?> restoreSession() async {
    final String? userId = _prefs.getString(_sessionKey);
    if (userId == null) return null;

    final Map<String, dynamic> accounts = _readAccounts();
    final Map<String, dynamic>? record = accounts.values
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? account) => account?['id'] == userId,
          orElse: () => null,
        );
    if (record == null) return null;

    _currentUser = AppUser.fromJson(record);
    _controller.add(_currentUser);
    return _currentUser;
  }

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) async {
    final String key = _normalise(username);
    _validate(username: username, password: password);

    final Map<String, dynamic> accounts = _readAccounts();
    if (accounts.containsKey(key)) {
      throw const AuthException(
        'That username is already taken on this device.',
      );
    }

    final AppUser user = AppUser(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      username: username.trim(),
      educationLevel: educationLevel,
      createdAt: DateTime.now(),
    );

    accounts[key] = <String, dynamic>{
      ...user.toJson(),
      'password_hash': _hash(password, user.id),
    };
    await _writeAccounts(accounts);
    await _startSession(user);
    return user;
  }

  @override
  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async {
    final Map<String, dynamic> accounts = _readAccounts();
    final Map<String, dynamic>? record =
        accounts[_normalise(username)] as Map<String, dynamic>?;

    if (record == null || record['password_hash'] != _hash(password, record['id'] as String)) {
      throw const AuthException('Incorrect username or password.');
    }

    final AppUser user = AppUser.fromJson(record);
    await _startSession(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove(_sessionKey);
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    final AppUser? user = _currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }

    final Map<String, dynamic> accounts = _readAccounts();
    // Match on id, not on the username key: a profile edit can have moved the
    // record to a different key since sign-in.
    final String? key = accounts.keys.cast<String?>().firstWhere(
      (String? k) => (accounts[k] as Map<String, dynamic>)['id'] == user.id,
      orElse: () => null,
    );

    if (key != null) {
      accounts.remove(key);
      await _writeAccounts(accounts);
    }

    // The credential record is gone; end the session too so the app cannot
    // keep showing a signed-in user that no longer exists.
    await signOut();
  }

  /// Persist an updated profile back into the account record.
  Future<void> persistProfile(AppUser user) async {
    final Map<String, dynamic> accounts = _readAccounts();
    final String? key = accounts.keys.cast<String?>().firstWhere(
      (String? k) => (accounts[k] as Map<String, dynamic>)['id'] == user.id,
      orElse: () => null,
    );
    if (key == null) return;

    final Map<String, dynamic> record =
        accounts[key] as Map<String, dynamic>;
    final Map<String, dynamic> updated = <String, dynamic>{
      ...record,
      ...user.toJson(),
    };

    accounts.remove(key);
    accounts[_normalise(user.username)] = updated;
    await _writeAccounts(accounts);

    if (_currentUser?.id == user.id) {
      _currentUser = user;
      _controller.add(user);
    }
  }

  AppUser? findById(String userId) {
    final Map<String, dynamic> accounts = _readAccounts();
    for (final dynamic record in accounts.values) {
      final Map<String, dynamic> account = record as Map<String, dynamic>;
      if (account['id'] == userId) return AppUser.fromJson(account);
    }
    return null;
  }

  Future<void> _startSession(AppUser user) async {
    await _prefs.setString(_sessionKey, user.id);
    _currentUser = user;
    _controller.add(user);
  }

  void _validate({required String username, required String password}) {
    if (username.trim().length < 3) {
      throw const AuthException('Username must be at least 3 characters.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }
  }

  Map<String, dynamic> _readAccounts() {
    final String raw = _prefs.getString(_accountsKey) ?? '{}';
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _writeAccounts(Map<String, dynamic> accounts) {
    return _prefs.setString(_accountsKey, jsonEncode(accounts));
  }

  String _normalise(String username) => username.trim().toLowerCase();

  /// Non-cryptographic digest — see the security note on this class. Real
  /// password handling arrives with Supabase Auth in Phase 6.
  String _hash(String password, String salt) {
    int hash = 0x1505;
    for (final int unit in '$salt::$password'.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16);
  }

  void dispose() => _controller.close();
}
