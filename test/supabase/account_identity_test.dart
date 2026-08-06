import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/supabase/account_identity.dart';

/// The username → Supabase-credential mapping. Pure Dart, so tested directly.
///
/// Two things here are load-bearing for privacy and for accounts continuing to
/// work: no real email is ever involved, and the derived address is stable.
void main() {
  group('username rules', () {
    test('accepts ordinary names', () {
      for (final String name in <String>[
        'ana',
        'Ana',
        'ana.lee',
        'ana_lee',
        'ana-lee',
        'a1b2c3',
        'twentyfourcharacters1234',
      ]) {
        expect(UsernameRule.validate(name), isNull, reason: name);
      }
    });

    test('rejects names that are too short or too long', () {
      expect(UsernameRule.validate('ab'), contains('at least 3'));
      expect(UsernameRule.validate('a' * 25), contains('24 characters'));
    });

    test('rejects characters that would break the derived address', () {
      for (final String name in <String>[
        'ana lee', // space
        'ana@lee', // second @
        'ana+lee',
        'añalee', // non-ASCII
        '.ana', // leading separator
        'ana.', // trailing separator
        'ana..lee', // consecutive dots
      ]) {
        expect(UsernameRule.validate(name), isNotNull, reason: name);
      }
    });

    test('trims before judging length', () {
      expect(UsernameRule.validate('  ana  '), isNull);
      expect(UsernameRule.validate('  a  '), isNotNull);
    });
  });

  group('derived credentials', () {
    test('never uses a routable domain — nothing can be emailed to a learner', () {
      // .invalid is reserved by RFC 2606 and can never resolve.
      expect(usernameDomain, endsWith('.invalid'));
      expect(emailForUsername('ana'), 'ana@$usernameDomain');
    });

    test('is case-insensitive, so one name is one account', () {
      expect(emailForUsername('Ana'), emailForUsername('ana'));
      expect(emailForUsername('  ANA '), emailForUsername('ana'));
      expect(normaliseUsername(' Ana '), 'ana');
    });

    test('round-trips back to the username', () {
      expect(usernameFromEmail(emailForUsername('ana.lee')), 'ana.lee');
    });

    test('ignores addresses that are not ours', () {
      expect(usernameFromEmail('ana@example.com'), isNull);
      expect(usernameFromEmail(null), isNull);
      expect(usernameFromEmail('@$usernameDomain'), isNull);
    });

    test('refuses to derive an address from an invalid username', () {
      expect(
        () => emailForUsername('ana lee'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PasswordRule', () {
    test('accepts a password with length, a letter and a number', () {
      expect(PasswordRule.validate('hunter2x1'), isNull);
      expect(PasswordRule.validate('a1b2c3'), isNull);
    });

    test('names the specific thing that is missing', () {
      // The whole reason this exists: "could not create the account" told a
      // learner nothing, so each branch has to say what to change.
      expect(PasswordRule.validate('ab1'), contains('6 characters'));
      expect(PasswordRule.validate('12345678'), contains('letter'));
      expect(PasswordRule.validate('password'), contains('number'));
    });

    test('the description names every rule it enforces', () {
      // A description that drifts from the checks is worse than none: the form
      // would promise one thing and reject on another.
      expect(PasswordRule.describe, contains('$minPasswordLength'));
      expect(PasswordRule.describe, contains('letter'));
      expect(PasswordRule.describe, contains('number'));
    });

    test('an empty password fails on length, not on a crash', () {
      expect(PasswordRule.validate(''), isNotNull);
    });
  });
}
