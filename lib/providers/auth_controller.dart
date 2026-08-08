import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/education_level.dart';
import '../data/repositories/auth_repo.dart';
import '../data/repositories/profile_repo.dart';
import 'repository_providers.dart';
import 'saved_login_controller.dart';

/// Session state for the whole app.
///
/// `null` data = signed out. Loading while the persisted session is restored,
/// which is why the router waits on this before deciding where to send the
/// learner (see `app_router.dart`).
class AuthController extends AsyncNotifier<AppUser?> {
  AuthRepo get _repo => ref.read(authRepoProvider);

  @override
  Future<AppUser?> build() async {
    final AuthRepo repo = ref.watch(authRepoProvider);

    final Stream<AppUser?> changes = repo.authStateChanges();
    final subscription = changes.listen((AppUser? user) {
      state = AsyncValue<AppUser?>.data(user);
    });
    ref.onDispose(subscription.cancel);

    return repo.restoreSession();
  }

  Future<void> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) async {
    // Deliberately NO transient `loading` here: the sign-in screen shows its
    // own progress spinner, and flipping the controller to loading would trip
    // the router's startup gate (`auth.isLoading`) and bounce this screen to
    // the intro mid-submit. The guard sets data on success, error on failure.
    state = await AsyncValue.guard<AppUser?>(
      () => _repo.signUp(
        username: username,
        password: password,
        educationLevel: educationLevel,
      ),
    );
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    // No transient `loading` — see the note in [signUp].
    state = await AsyncValue.guard<AppUser?>(
      () => _repo.signIn(username: username, password: password),
    );
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncValue<AppUser?>.data(null);
  }

  /// Deletes the account permanently, then ends the session.
  ///
  /// Rethrows [AuthException] so the caller can tell the learner the account
  /// still exists. State is only cleared once the delete has actually
  /// succeeded — a failed delete must leave them signed in and unchanged,
  /// rather than looking like it worked.
  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    // The account is gone, so a saved sign-in for it can only ever offer a
    // door that no longer opens. Cleared here rather than in the screen so it
    // cannot be missed — unlike [signOut], which deliberately leaves it: being
    // able to get back in with one tap is the whole reason it was saved.
    await ref.read(savedLoginControllerProvider.notifier).forget();
    state = const AsyncValue<AppUser?>.data(null);
  }

  Future<void> updateProfile({
    String? username,
    EducationLevel? educationLevel,
  }) async {
    final AppUser? user = state.value;
    if (user == null) return;

    final ProfileRepo profiles = ref.read(profileRepoProvider);
    final AppUser updated = await profiles.updateProfile(
      userId: user.id,
      username: username,
      educationLevel: educationLevel,
    );
    state = AsyncValue<AppUser?>.data(updated);
  }
}

final AsyncNotifierProvider<AuthController, AppUser?> authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

/// Convenience: the signed-in user, or null while loading/signed out.
final Provider<AppUser?> currentUserProvider = Provider<AppUser?>(
  (Ref ref) => ref.watch(authControllerProvider).value,
);
