import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/lesson_resume_store.dart';
import '../data/models/app_user.dart';
import '../data/models/lesson_resume.dart';
import 'auth_controller.dart';
import 'repository_providers.dart';

/// Every lesson bookmark for the signed-in learner, keyed by lesson id.
///
/// Synchronous, unlike `ProgressController`: the bookmarks come straight out
/// of shared_preferences, which is already loaded. The lesson player has to
/// know which card to open on before it builds its first frame, so an async
/// read here would show card one and then jump.
///
/// Rebuilt when the user changes, so one learner's bookmark never opens
/// another learner's lesson part-way through.
class LessonResumeController extends Notifier<Map<String, LessonResume>> {
  LessonResumeStore get _store => ref.read(lessonResumeStoreProvider);
  String? get _userId => ref.read(currentUserProvider)?.id;

  @override
  Map<String, LessonResume> build() {
    final AppUser? user = ref.watch(currentUserProvider);
    if (user == null) return <String, LessonResume>{};
    return ref.watch(lessonResumeStoreProvider).readAll(user.id);
  }

  LessonResume? forLesson(String lessonId) => state[lessonId];

  /// Remembers the card that is on screen. Called on every swipe, which is why
  /// nothing here touches the network.
  Future<void> saveCard({required String lessonId, required int cardIndex}) =>
      _update(lessonId, (LessonResume r) => r.copyWith(cardIndex: cardIndex));

  /// Remembers a Q&A run in progress — the question, the answers given so far,
  /// and the shuffle that produced the order they were given in.
  Future<void> saveQuiz({required String lessonId, required QuizResume quiz}) =>
      _update(lessonId, (LessonResume r) => r.copyWith(quiz: quiz));

  /// Drops the card bookmark, leaving any Q&A bookmark alone. Used when a deck
  /// is finished: reopening a lesson that has been read through should start at
  /// the top, not on its last card.
  Future<void> clearCard(String lessonId) =>
      _update(lessonId, (LessonResume r) => r.copyWith(cardIndex: 0));

  /// Drops the Q&A bookmark: the run it described is over, either finished or
  /// restarted, and replaying it would put the learner back in a run that has
  /// already been scored.
  Future<void> clearQuiz(String lessonId) =>
      _update(lessonId, (LessonResume r) => r.copyWith(clearQuiz: true));

  /// Wipes every bookmark for the current learner (Settings → reset progress).
  Future<void> clearAll() async {
    final String? userId = _userId;
    if (userId == null) return;

    await _store.clear(userId);
    state = <String, LessonResume>{};
  }

  Future<void> _update(
    String lessonId,
    LessonResume Function(LessonResume) change,
  ) async {
    final String? userId = _userId;
    if (userId == null) return;

    final LessonResume updated = change(
      state[lessonId] ?? LessonResume(lessonId: lessonId),
    );
    final Map<String, LessonResume> next = <String, LessonResume>{
      ...state,
      lessonId: updated,
    }..removeWhere((String _, LessonResume r) => r.isEmpty);

    state = next;
    await _store.writeAll(userId: userId, bookmarks: next);
  }
}

final NotifierProvider<LessonResumeController, Map<String, LessonResume>>
lessonResumeControllerProvider =
    NotifierProvider<LessonResumeController, Map<String, LessonResume>>(
      LessonResumeController.new,
    );
