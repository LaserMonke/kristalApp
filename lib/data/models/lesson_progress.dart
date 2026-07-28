/// Per-lesson progress record.
///
/// Written by the lesson engine (Phase 1) and the Q&A engine (Phase 2), read by
/// the gating logic that unlocks the next lesson and by the points/streak
/// system (Phase 5).
class LessonProgress {
  const LessonProgress({
    required this.lessonId,
    this.cardsViewed = 0,
    this.lessonCompleted = false,
    this.quizCompleted = false,
    this.correctAnswers = 0,
    this.totalQuestions = 0,
    this.quizAttempts = 0,
    this.pointsEarned = 0,
    this.lastOpenedAt,
    this.completedAt,
  });

  final String lessonId;

  /// How far through the card deck the learner got — lets us resume mid-lesson.
  final int cardsViewed;

  /// Reached the last card.
  final bool lessonCompleted;

  /// Finished the Q&A. The next lesson unlocks on this, not on [lessonCompleted]
  /// (CLAUDE.md build order step 3: gate the next lesson on the Q&A).
  final bool quizCompleted;

  /// Best result so far, not the latest: a retake can raise the recorded score
  /// but never lower it, so revisiting a lesson is never punished.
  final int correctAnswers;
  final int totalQuestions;

  /// How many times the Q&A has been run through. Kept separate from the score
  /// so the results screen can be honest about a score that took three goes.
  final int quizAttempts;

  final int pointsEarned;
  final DateTime? lastOpenedAt;
  final DateTime? completedAt;

  double get score => totalQuestions == 0 ? 0 : correctAnswers / totalQuestions;

  LessonProgress copyWith({
    int? cardsViewed,
    bool? lessonCompleted,
    bool? quizCompleted,
    int? correctAnswers,
    int? totalQuestions,
    int? quizAttempts,
    int? pointsEarned,
    DateTime? lastOpenedAt,
    DateTime? completedAt,
  }) {
    return LessonProgress(
      lessonId: lessonId,
      cardsViewed: cardsViewed ?? this.cardsViewed,
      lessonCompleted: lessonCompleted ?? this.lessonCompleted,
      quizCompleted: quizCompleted ?? this.quizCompleted,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      quizAttempts: quizAttempts ?? this.quizAttempts,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lesson_id': lessonId,
    'cards_viewed': cardsViewed,
    'lesson_completed': lessonCompleted,
    'quiz_completed': quizCompleted,
    'correct_answers': correctAnswers,
    'total_questions': totalQuestions,
    'quiz_attempts': quizAttempts,
    'points_earned': pointsEarned,
    'last_opened_at': lastOpenedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };

  factory LessonProgress.fromJson(Map<String, dynamic> json) {
    return LessonProgress(
      lessonId: json['lesson_id'] as String,
      cardsViewed: json['cards_viewed'] as int? ?? 0,
      lessonCompleted: json['lesson_completed'] as bool? ?? false,
      quizCompleted: json['quiz_completed'] as bool? ?? false,
      correctAnswers: json['correct_answers'] as int? ?? 0,
      totalQuestions: json['total_questions'] as int? ?? 0,
      quizAttempts: json['quiz_attempts'] as int? ?? 0,
      pointsEarned: json['points_earned'] as int? ?? 0,
      lastOpenedAt: DateTime.tryParse(json['last_opened_at'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
    );
  }
}
