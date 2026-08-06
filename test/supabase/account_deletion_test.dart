import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/local_auth_repo.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/repositories/auth_repo.dart';
import 'package:optionsschool/data/supabase/supabase_error_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Account deletion is a Google Play requirement for any app that offers
/// account creation, and it is irreversible — this app holds no email address,
/// so a wrong outcome cannot be corrected afterwards. These tests pin the two
/// things that matter: it really removes the account, and a FAILED delete never
/// looks like a successful one.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<LocalAuthRepo> repoWithAccount() async {
    final LocalAuthRepo repo = LocalAuthRepo(
      await SharedPreferences.getInstance(),
    );
    await repo.signUp(
      username: 'learner',
      password: 'hunter2x1',
      educationLevel: EducationLevel.undergraduate,
    );
    return repo;
  }

  group('deleting an account on-device', () {
    test('removes the credentials, so the password no longer signs in', () async {
      final LocalAuthRepo repo = await repoWithAccount();

      await repo.deleteAccount();

      expect(repo.currentUser, isNull);
      await expectLater(
        repo.signIn(username: 'learner', password: 'hunter2x1'),
        throwsA(isA<AuthException>()),
      );
      repo.dispose();
    });

    test('frees the username for a new sign-up', () async {
      final LocalAuthRepo repo = await repoWithAccount();
      await repo.deleteAccount();

      // Nothing should be left holding the name. A "username taken" here would
      // mean a record survived the delete.
      final user = await repo.signUp(
        username: 'learner',
        password: 'different1',
        educationLevel: EducationLevel.highSchool,
      );

      expect(user.username, 'learner');
      repo.dispose();
    });

    test('ends the session', () async {
      final LocalAuthRepo repo = await repoWithAccount();
      await repo.deleteAccount();

      // A restored session must not resurrect a deleted account.
      expect(await repo.restoreSession(), isNull);
      repo.dispose();
    });

    test('refuses when nobody is signed in', () async {
      final LocalAuthRepo repo = LocalAuthRepo(
        await SharedPreferences.getInstance(),
      );

      await expectLater(
        repo.deleteAccount(),
        throwsA(isA<AuthException>()),
      );
      repo.dispose();
    });

    test('deletes the right record after a username change', () async {
      final LocalAuthRepo repo = await repoWithAccount();
      final user = repo.currentUser!;

      // persistProfile re-keys the record by the new username. Deleting by the
      // sign-in name would miss it and silently leave the account behind.
      await repo.persistProfile(user.copyWith(username: 'renamed'));
      await repo.deleteAccount();

      await expectLater(
        repo.signIn(username: 'renamed', password: 'hunter2x1'),
        throwsA(isA<AuthException>()),
      );
      repo.dispose();
    });
  });

  group('failure messages say plainly that nothing was deleted', () {
    test('offline', () {
      final String message = deleteAccountErrorMessage(
        sb.AuthRetryableFetchException(message: 'no route to host'),
      );

      expect(message, contains('NOT deleted'));
      expect(message.toLowerCase(), contains('connection'));
    });

    test('expired session', () {
      final String message = deleteAccountErrorMessage(
        sb.PostgrestException(message: 'Not signed in.', code: '28000'),
      );

      expect(message, contains('NOT deleted'));
      expect(message.toLowerCase(), contains('sign in again'));
    });

    test('an unrecognised failure still promises nothing was removed', () {
      final String message = deleteAccountErrorMessage(
        StateError('something unexpected'),
      );

      // The learner cannot check for themselves — no email, and a live account
      // looks identical to a failed delete. So even the fallback is explicit.
      expect(message.toLowerCase(), contains('nothing was deleted'));
    });
  });
}
