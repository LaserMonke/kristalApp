import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/moderation/username_words.dart';
import 'package:optionsschool/data/supabase/account_identity.dart';

/// The username filter, tested from both directions: it has to catch the
/// obvious evasions, and — just as importantly — it has to leave ordinary names
/// alone. A filter that refuses "Cassandra" teaches nothing and annoys someone
/// on their first screen.
void main() {
  group('blocked wording', () {
    test('plain profanity is refused', () {
      for (final String name in <String>[
        'fuckthis',
        'shithead',
        'bigCunt',
        'whoreman',
      ]) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.blocked,
          reason: name,
        );
      }
    });

    test('leetspeak and separators do not get around it', () {
      for (final String name in <String>[
        'f.u.c.k',
        'sh1thead',
        'fuuuuck',
        'F_U_C_K',
        'b4stard',
        'n1gger',
      ]) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.blocked,
          reason: name,
        );
      }
    });

    test('a term hiding behind a word boundary is caught', () {
      for (final String name in <String>['big_ass', 'bigAss', 'big2ass']) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.blocked,
          reason: name,
        );
      }
    });
  });

  group('ordinary names survive', () {
    test('innocent words that merely contain a term are left alone', () {
      // The Scunthorpe problem: a filter that fails these is worse than none.
      for (final String name in <String>[
        'assess',
        'Cassandra',
        'Scunthorpe',
        'classic',
        'cocoon',
        'auspicious',
        'shellfish',
        'grapes',
        'analyst',
        'Dickinson',
        'Hancock',
        'passion',
        'bassist',
      ]) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.clean,
          reason: name,
        );
      }
    });

    test('normal usernames pass', () {
      for (final String name in <String>[
        'alice',
        'trader_joe',
        'Vega42',
        'theta.gang',
        'Mia-Chen',
      ]) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.clean,
          reason: name,
        );
      }
    });
  });

  group('reserved names', () {
    test('staff and app names cannot be claimed', () {
      for (final String name in <String>[
        'admin',
        'Admin',
        'MODERATOR',
        'optionsschool',
        'support',
      ]) {
        expect(
          UsernameWords.verdict(name),
          UsernameWordVerdict.reserved,
          reason: name,
        );
      }
    });

    test('bot is reserved, so a labelled bot cannot be impersonated', () {
      // CLAUDE.md rule 7: a bot on the leaderboard is labelled as one, and a
      // human registering "bot" would undo that labelling by hand.
      expect(UsernameWords.verdict('bot'), UsernameWordVerdict.reserved);
      expect(UsernameWords.verdict('bots'), UsernameWordVerdict.reserved);
      // Only as the WHOLE name — a real name that contains it is fine.
      expect(UsernameWords.verdict('robotics'), UsernameWordVerdict.clean);
    });
  });

  group('messages', () {
    test('a refusal never repeats the word back', () {
      final String? message = UsernameWords.check('fuckthis');
      expect(message, isNotNull);
      expect(message!.toLowerCase(), isNot(contains('fuck')));
    });

    test('a clean name has no message', () {
      expect(UsernameWords.check('alice'), isNull);
    });
  });

  group('where the rule is applied', () {
    test('validateNew refuses a blocked name, validate does not', () {
      // The split matters: validate() is what sign-in and the synthetic
      // address run, so applying the word list there would lock out an account
      // created before a term was added.
      expect(UsernameRule.validateNew('shithead'), isNotNull);
      expect(UsernameRule.validate('shithead'), isNull);
    });

    test('validateNew still enforces the shape rules', () {
      expect(UsernameRule.validateNew('ab'), contains('at least'));
      expect(UsernameRule.validateNew('has space'), contains('letters'));
    });

    test('an existing account keeps a working sign-in address', () {
      // Whatever the word list says today, this must not throw for a name that
      // was registered yesterday.
      expect(emailForUsername('shithead'), 'shithead@$usernameDomain');
    });
  });
}
