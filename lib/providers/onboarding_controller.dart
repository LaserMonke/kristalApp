import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/profile_repo.dart';
import 'repository_providers.dart';

/// Whether the learner has acknowledged the educational-only disclaimer.
///
/// CLAUDE.md rule 1: shown clearly at onboarding, before any lesson content,
/// and kept reachable from Settings afterwards.
class OnboardingController extends AsyncNotifier<bool> {
  ProfileRepo get _repo => ref.read(profileRepoProvider);

  @override
  Future<bool> build() => ref.watch(profileRepoProvider).hasAcceptedDisclaimer();

  Future<void> accept() async {
    await _repo.setDisclaimerAccepted(accepted: true);
    state = const AsyncValue<bool>.data(true);
  }
}

final AsyncNotifierProvider<OnboardingController, bool>
onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);
