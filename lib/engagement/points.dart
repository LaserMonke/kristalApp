/// The points scheme (Phase 5). Pure Dart, no Flutter imports.
///
/// Points reward LEARNING, not speed or spending: finishing a card deck, and
/// answering Q&A questions correctly. The recorded score per lesson is the
/// BEST attempt (see LessonProgress), so points are monotonic — retaking a
/// Q&A can raise a lesson's points but never lower them, and revisiting
/// material is never punished.
library;

/// Awarded once, when the learner reaches the last card of a lesson deck.
const int deckCompletionPoints = 20;

/// Awarded per correct Q&A answer, counted on the best attempt.
const int pointsPerCorrectAnswer = 10;

/// A flat bonus for a perfect Q&A — enough to feel earned, small enough that
/// missing it never blocks progress (nothing in the app is gated on points).
const int perfectQuizBonus = 15;

/// Total points a lesson is currently worth, computed from its progress
/// record. Recomputed on every write rather than accumulated, so the stored
/// value can never drift from the rules above.
int lessonPoints({
  required bool deckCompleted,
  required int correctAnswers,
  required int totalQuestions,
}) {
  final int deck = deckCompleted ? deckCompletionPoints : 0;
  final int answers = correctAnswers * pointsPerCorrectAnswer;
  final bool perfect = totalQuestions > 0 && correctAnswers == totalQuestions;
  return deck + answers + (perfect ? perfectQuizBonus : 0);
}
