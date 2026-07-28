import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/education_level.dart';
import '../data/repositories/auth_repo.dart';
import '../data/repositories/profile_repo.dart';
import 'repository_providers.dart';

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
    state = const AsyncValue<AppUser?>.loading();
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
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard<AppUser?>(
      () => _repo.signIn(username: username, password: password),
    );
  }

  Future<void> signOut() async {
    await _repo.signOut();
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
