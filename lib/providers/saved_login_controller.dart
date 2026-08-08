import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/device_unlock.dart';
import '../data/repositories/auth_repo.dart';
import '../data/repositories/saved_login_store.dart';
import 'auth_controller.dart';
import 'repository_providers.dart';

/// Whether this device can sign the learner back in, and as whom.
class SavedLoginState {
  const SavedLoginState({required this.lock, required this.username});

  static const SavedLoginState unavailable = SavedLoginState(
    lock: DeviceLockKind.none,
    username: null,
  );

  final DeviceLockKind lock;

  /// Who the saved sign-in belongs to, or null when there is none to offer.
  final String? username;

  /// Whether saving a sign-in is worth offering at all. False on a device with
  /// no screen lock, where there would be nothing to gate the password behind.
  bool get canOffer => lock != DeviceLockKind.none;

  bool get hasSavedLogin => username != null;
}

/// The saved sign-in on this device.
///
/// Survives signing out — that is the entire point. It is cleared when the
/// learner turns it off, when the saved password stops working, and when the
/// account is deleted.
class SavedLoginController extends AsyncNotifier<SavedLoginState> {
  SavedLoginStore get _store => ref.read(savedLoginStoreProvider);
  DeviceUnlock get _unlock => ref.read(deviceUnlockProvider);

  @override
  Future<SavedLoginState> build() async {
    final DeviceLockKind lock = await ref
        .watch(deviceUnlockProvider)
        .lockKind();

    // A device whose screen lock has been turned off since the credential was
    // saved: stop offering it, but do not delete it. Locks get switched off
    // temporarily, and quietly destroying the learner's saved sign-in for it
    // would be a surprise they cannot undo.
    if (lock == DeviceLockKind.none) return SavedLoginState.unavailable;

    return SavedLoginState(
      lock: lock,
      username: await ref.watch(savedLoginStoreProvider).readUsername(),
    );
  }

  /// Saves the credential the learner just signed in with.
  Future<void> remember({
    required String username,
    required String password,
  }) async {
    final DeviceLockKind lock = state.value?.lock ?? await _unlock.lockKind();
    if (lock == DeviceLockKind.none) return;

    await _store.save(SavedLogin(username: username, password: password));
    state = AsyncValue<SavedLoginState>.data(
      SavedLoginState(lock: lock, username: username),
    );
  }

  Future<void> forget() async {
    await _store.clear();
    state = AsyncValue<SavedLoginState>.data(
      SavedLoginState(
        lock: state.value?.lock ?? DeviceLockKind.none,
        username: null,
      ),
    );
  }

  /// Signs in with the saved credential, after the device lock has released it.
  ///
  /// Returns false when the learner dismissed the unlock prompt — an ordinary
  /// "changed my mind", which the screen should treat as nothing having
  /// happened rather than as a failure.
  ///
  /// Throws [AuthException] when the saved credential itself is no longer good
  /// (the password was changed on another device, or the account is gone). The
  /// saved sign-in is dropped in that case, because it will never work again
  /// and leaving it would offer the learner a button that cannot succeed.
  Future<bool> signIn() async {
    final String? username = state.value?.username;
    if (username == null) return false;

    if (!await _unlock.confirm('Sign in to Stock Options Academy')) {
      return false;
    }

    final SavedLogin? saved = await _store.read();
    if (saved == null) {
      await forget();
      throw const AuthException(
        'The saved sign-in for this device could not be read. '
        'Sign in with your password once and it will be saved again.',
      );
    }

    final AuthController auth = ref.read(authControllerProvider.notifier);
    await auth.signIn(username: saved.username, password: saved.password);

    // AuthController records a failed sign-in as an error state rather than
    // throwing, so a bad saved password would otherwise look like success.
    if (ref.read(authControllerProvider).error != null) {
      await forget();
      throw const AuthException(
        'Your saved sign-in no longer works — the password may have been '
        'changed on another device. Sign in with your password to save it '
        'again.',
      );
    }
    return true;
  }
}

final AsyncNotifierProvider<SavedLoginController, SavedLoginState>
savedLoginControllerProvider =
    AsyncNotifierProvider<SavedLoginController, SavedLoginState>(
      SavedLoginController.new,
    );
