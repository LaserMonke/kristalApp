import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/lesson_progress.dart';
import '../engagement/levels.dart';
import '../engagement/streak.dart';
import 'auth_controller.dart';
import 'lesson_providers.dart';
import 'progress_controller.dart';
import 'repository_providers.dart';

/// The learner's daily streak. Rebuilds on user change so streaks never leak
/// between accounts; [StreakState.initial] when signed out or never active.
class StreakController extends AsyncNotifier<StreakState> {
  @override
  Future<StreakState> build() async {
    final AppUser? user = ref.watch(currentUserProvider);
    if (user == null) return StreakState.initial;
    return await ref.watch(progressRepoProvider).loadStreak(user.id) ??
        StreakState.initial;
  }

  /// Called by the progress controller whenever real learning happens (a new
  /// card, a finished deck, a completed Q&A). Idempotent within a day.
  Future<StreakEvent> registerActivity() async {
    final String? userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return StreakEvent.unchanged;

    final StreakState current = state.value ?? StreakState.initial;
    final StreakResult result = current.register(DateTime.now());
    if (result.event == StreakEvent.unchanged) return result.event;

    await ref
        .read(progressRepoProvider)
        .saveStreak(userId: userId, streak: result.state);
    state = AsyncValue<StreakState>.data(result.state);
    return result.event;
  }
}

final AsyncNotifierProvider<StreakController, StreakState>
streakControllerProvider = AsyncNotifierProvider<StreakController, StreakState>(
  StreakController.new,
);

/// Lifetime points, derived from the per-lesson records rather than stored
/// separately — one source of truth, nothing to reconcile.
final Provider<int> totalPointsProvider = Provider<int>((Ref ref) {
  final Map<String, LessonProgress>? all = ref
      .watch(progressControllerProvider)
      .value;
  if (all == null) return 0;
  return all.values.fold<int>(
    0,
    (int sum, LessonProgress p) => sum + p.pointsEarned,
  );
});

final Provider<Level> levelProvider = Provider<Level>(
  (Ref ref) => levelForPoints(ref.watch(totalPointsProvider)),
);

/// Where the learner stands relative to the completion certificate: earned by
/// finishing every lesson's Q&A — mastery of the material, not points.
class CertificateStatus {
  const CertificateStatus({
    required this.finishedLessons,
    required this.totalLessons,
    this.earnedOn,
  });

  final int finishedLessons;
  final int totalLessons;

  /// When the last required lesson was finished; null until earned.
  final DateTime? earnedOn;

  bool get earned => totalLessons > 0 && finishedLessons == totalLessons;
}

final FutureProvider<CertificateStatus> certificateStatusProvider =
    FutureProvider<CertificateStatus>((Ref ref) async {
      final List<LessonNode> nodes = await ref.watch(lessonPathProvider.future);
      final List<LessonNode> finished = nodes
          .where((LessonNode n) => n.isFinished)
          .toList();

      DateTime? earnedOn;
      if (nodes.isNotEmpty && finished.length == nodes.length) {
        for (final LessonNode node in finished) {
          final DateTime? done = node.progress.completedAt;
          if (done != null && (earnedOn == null || done.isAfter(earnedOn))) {
            earnedOn = done;
          }
        }
        earnedOn ??= DateTime.now();
      }

      return CertificateStatus(
        finishedLessons: finished.length,
        totalLessons: nodes.length,
        earnedOn: earnedOn,
      );
    });
