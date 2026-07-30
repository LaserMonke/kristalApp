import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/engagement/points.dart';

/// The points rules exist TWICE: in Dart (for the offline cache and the UI) and
/// as a generated column in Postgres (the authority, and what the leaderboard
/// ranks on). If the two drift, a learner sees one score in Settings and a
/// different one on the leaderboard.
///
/// This test reads the migration and holds the SQL to the Dart constants, so
/// changing one without the other fails the build instead of shipping.
void main() {
  const String migration =
      'supabase/migrations/20260730120000_phase6_init.sql';

  late String pointsExpression;

  setUpAll(() {
    final File file = File(migration);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$migration is the schema of record — do not rename it silently',
    );

    final RegExpMatch? match = RegExp(
      r'points_earned\s+integer generated always as \((.*?)\) stored',
      dotAll: true,
    ).firstMatch(file.readAsStringSync());

    expect(
      match,
      isNotNull,
      reason: 'points_earned must stay a generated column: a client-supplied '
          'score could be inflated, which would make the leaderboard a lie',
    );
    pointsExpression = match!.group(1)!;
  });

  test('the SQL deck bonus matches deckCompletionPoints', () {
    expect(
      pointsExpression,
      contains('when lesson_completed then $deckCompletionPoints'),
    );
  });

  test('the SQL per-answer award matches pointsPerCorrectAnswer', () {
    expect(
      pointsExpression,
      contains('correct_answers * $pointsPerCorrectAnswer'),
    );
  });

  test('the SQL perfect-quiz bonus matches perfectQuizBonus', () {
    expect(
      pointsExpression,
      contains('correct_answers = total_questions then $perfectQuizBonus'),
    );
  });

  test('a worked example agrees with the Dart implementation', () {
    // 20 deck + 4 correct × 10 + 15 perfect = 75, which is what the SQL
    // expression above computes for the same row.
    expect(
      lessonPoints(deckCompleted: true, correctAnswers: 4, totalQuestions: 4),
      75,
    );
    // No perfect bonus when a question was missed.
    expect(
      lessonPoints(deckCompleted: true, correctAnswers: 3, totalQuestions: 4),
      50,
    );
  });
}
