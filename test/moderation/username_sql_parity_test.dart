import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/moderation/username_words.dart';

/// The blocklist exists twice — once in Dart for a friendly refusal, once in
/// Postgres because that is the copy a modified client cannot skip. Two copies
/// drift. This reads the migration and fails when they do.
void main() {
  test('the SQL blocklist matches the Dart one', () {
    final File migration = File(
      'supabase/migrations/20260808140000_username_moderation.sql',
    );
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'username moderation migration is missing',
    );

    final String sql = migration.readAsStringSync();

    // Matches the seeded rows: ('term', 'kind').
    final RegExp row = RegExp(
      r"\('([a-z]+)',\s*'(substring|word|reserved|allowed)'\)",
    );
    final Map<String, Set<String>> seeded = <String, Set<String>>{
      'substring': <String>{},
      'word': <String>{},
      'reserved': <String>{},
      'allowed': <String>{},
    };
    for (final RegExpMatch match in row.allMatches(sql)) {
      seeded[match.group(2)!]!.add(match.group(1)!);
    }

    expect(seeded['substring'], UsernameWords.substringTerms.toSet());
    expect(seeded['word'], UsernameWords.wordTerms.toSet());
    expect(seeded['reserved'], UsernameWords.reservedNames.toSet());
    expect(seeded['allowed'], UsernameWords.allowedNames.toSet());
  });
}
