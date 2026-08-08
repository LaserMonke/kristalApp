import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/auth/device_unlock.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/repositories/auth_repo.dart';
import 'package:optionsschool/data/repositories/saved_login_store.dart';
import 'package:optionsschool/features/auth/sign_in_screen.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:optionsschool/providers/saved_login_controller.dart';

/// Signing back in from the device that remembers you.
///
/// The rule under all of it: signing out must NOT throw the saved credential
/// away — being able to get straight back in is the whole point — but anything
/// that makes it wrong or unwanted must.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the device can offer', () {
    test('no screen lock means the feature is not offered at all', () async {
      final _FakeStore store = _FakeStore(
        const SavedLogin(username: 'sam', password: 'lesson1'),
      );
      final ProviderContainer container = _container(
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.none),
      );
      addTearDown(container.dispose);

      final SavedLoginState state = await container.read(
        savedLoginControllerProvider.future,
      );

      expect(state.canOffer, isFalse);
      expect(
        state.hasSavedLogin,
        isFalse,
        reason: 'nothing to gate the password behind, so do not offer it',
      );
      expect(
        store.saved,
        isNotNull,
        reason:
            'a lock switched off temporarily must not destroy the '
            'credential — the learner cannot undo that',
      );
    });

    test('a lock with no biometric enrolled still counts', () async {
      final ProviderContainer container = _container(
        store: _FakeStore(const SavedLogin(username: 'sam', password: 'x')),
        unlock: _FakeUnlock(DeviceLockKind.passcode),
      );
      addTearDown(container.dispose);

      final SavedLoginState state = await container.read(
        savedLoginControllerProvider.future,
      );
      expect(state.canOffer, isTrue);
      expect(state.username, 'sam');
    });
  });

  group('signing in with the saved credential', () {
    test('unlocks, then signs in', () async {
      final _FakeAuthRepo auth = _FakeAuthRepo();
      final _FakeUnlock unlock = _FakeUnlock(DeviceLockKind.fingerprint);
      final ProviderContainer container = _container(
        store: _FakeStore(
          const SavedLogin(username: 'sam', password: 'lesson1'),
        ),
        unlock: unlock,
        auth: auth,
      );
      addTearDown(container.dispose);

      await container.read(savedLoginControllerProvider.future);
      final bool ok = await container
          .read(savedLoginControllerProvider.notifier)
          .signIn();

      expect(ok, isTrue);
      expect(unlock.prompts, 1);
      expect(auth.attempted, <String>['sam:lesson1']);
      expect(container.read(currentUserProvider)?.username, 'sam');
    });

    test(
      'a dismissed prompt signs nobody in and keeps the credential',
      () async {
        final _FakeAuthRepo auth = _FakeAuthRepo();
        final _FakeStore store = _FakeStore(
          const SavedLogin(username: 'sam', password: 'lesson1'),
        );
        final ProviderContainer container = _container(
          store: store,
          unlock: _FakeUnlock(DeviceLockKind.face, passes: false),
          auth: auth,
        );
        addTearDown(container.dispose);

        await container.read(savedLoginControllerProvider.future);
        final bool ok = await container
            .read(savedLoginControllerProvider.notifier)
            .signIn();

        // "Changed my mind" is an ordinary outcome, not a failure to report.
        expect(ok, isFalse);
        expect(auth.attempted, isEmpty);
        expect(store.saved, isNotNull);
      },
    );

    test(
      'a password changed elsewhere is reported and the credential dropped',
      () async {
        final _FakeAuthRepo auth = _FakeAuthRepo(accept: false);
        final _FakeStore store = _FakeStore(
          const SavedLogin(username: 'sam', password: 'stale'),
        );
        final ProviderContainer container = _container(
          store: store,
          unlock: _FakeUnlock(DeviceLockKind.fingerprint),
          auth: auth,
        );
        addTearDown(container.dispose);

        await container.read(savedLoginControllerProvider.future);

        await expectLater(
          container.read(savedLoginControllerProvider.notifier).signIn(),
          throwsA(isA<AuthException>()),
        );
        // Keeping it would offer a button that can never succeed.
        expect(store.saved, isNull);
        expect(
          container.read(savedLoginControllerProvider).value?.hasSavedLogin,
          isFalse,
        );
      },
    );
  });

  group('when the credential is kept and dropped', () {
    test('signing out keeps it — that is what it is for', () async {
      final _FakeStore store = _FakeStore(null);
      final ProviderContainer container = _container(
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
      );
      addTearDown(container.dispose);

      await container.read(savedLoginControllerProvider.future);
      await container
          .read(savedLoginControllerProvider.notifier)
          .remember(username: 'sam', password: 'lesson1');

      await container.read(authControllerProvider.notifier).signOut();

      expect(store.saved?.username, 'sam');
      expect(
        container.read(savedLoginControllerProvider).value?.username,
        'sam',
      );
    });

    test('deleting the account drops it', () async {
      final _FakeStore store = _FakeStore(
        const SavedLogin(username: 'sam', password: 'lesson1'),
      );
      final ProviderContainer container = _container(
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
      );
      addTearDown(container.dispose);

      await container.read(savedLoginControllerProvider.future);
      await container.read(authControllerProvider.notifier).deleteAccount();

      expect(store.saved, isNull);
    });

    test('a device with no lock never writes a credential', () async {
      final _FakeStore store = _FakeStore(null);
      final ProviderContainer container = _container(
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.none),
      );
      addTearDown(container.dispose);

      await container.read(savedLoginControllerProvider.future);
      await container
          .read(savedLoginControllerProvider.notifier)
          .remember(username: 'sam', password: 'lesson1');

      expect(store.saved, isNull);
    });
  });

  group('the sign-in screen', () {
    testWidgets('offers the saved account by name, and unlocks into it', (
      WidgetTester tester,
    ) async {
      final _FakeAuthRepo auth = _FakeAuthRepo();
      final _FakeUnlock unlock = _FakeUnlock(DeviceLockKind.fingerprint);

      await _pumpSignIn(
        tester,
        store: _FakeStore(
          const SavedLogin(username: 'sam', password: 'lesson1'),
        ),
        unlock: unlock,
        auth: auth,
      );

      // Names whose account it is: a phone gets handed round, and unlocking
      // into somebody else's progress would be worse than typing a password.
      expect(find.text('sam'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(find.text('Sign in with your fingerprint'), findsOneWidget);
      // The form is out of the way entirely.
      expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);

      await tester.tap(find.text('Sign in with your fingerprint'));
      await tester.pumpAndSettle();

      expect(unlock.prompts, 1);
      expect(auth.attempted, <String>['sam:lesson1']);
    });

    testWidgets('a stale saved sign-in explains itself and falls back', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(
        const SavedLogin(username: 'sam', password: 'stale'),
      );

      await _pumpSignIn(
        tester,
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
        auth: _FakeAuthRepo(accept: false),
      );

      await tester.tap(find.text('Sign in with your fingerprint'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer works'), findsOneWidget);
      // Dropped, and the learner is put in front of the form rather than a
      // button that cannot work.
      expect(store.saved, isNull);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });

    testWidgets('offers to save a sign-in typed by hand', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(null);

      await _pumpSignIn(
        tester,
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
        auth: _FakeAuthRepo(),
      );

      expect(find.text('Stay signed in on this phone'), findsOneWidget);
      // Says where the password goes, in the same breath as asking.
      expect(find.textContaining('kept on this device only'), findsOneWidget);

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'sam',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'lesson1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(store.saved?.username, 'sam');
      expect(store.saved?.password, 'lesson1');
    });

    testWidgets('turning the switch off saves nothing', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(null);

      await _pumpSignIn(
        tester,
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
        auth: _FakeAuthRepo(),
      );

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'sam',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'lesson1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(store.saved, isNull);
    });

    testWidgets('a device with no screen lock is never offered the switch', (
      WidgetTester tester,
    ) async {
      await _pumpSignIn(
        tester,
        store: _FakeStore(null),
        unlock: _FakeUnlock(DeviceLockKind.none),
        auth: _FakeAuthRepo(),
      );

      expect(find.text('Stay signed in on this phone'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('somebody else signing in clears the previous credential', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(
        const SavedLogin(username: 'sam', password: 'lesson1'),
      );

      await _pumpSignIn(
        tester,
        store: store,
        unlock: _FakeUnlock(DeviceLockKind.fingerprint),
        auth: _FakeAuthRepo(),
      );

      await tester.tap(find.text('Sign in as someone else'));
      await tester.pumpAndSettle();
      // Turn the offer to save off, so the only thing under test is that
      // sam's credential does not survive somebody else signing in.
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'alex',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'lesson1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        store.saved,
        isNull,
        reason: 'leaving sam saved would offer their account to alex',
      );
    });
  });
}

// ---------------------------------------------------------------- harness

ProviderContainer _container({
  required _FakeStore store,
  required _FakeUnlock unlock,
  _FakeAuthRepo? auth,
}) {
  return ProviderContainer(
    overrides: [
      savedLoginStoreProvider.overrideWithValue(store),
      deviceUnlockProvider.overrideWithValue(unlock),
      authRepoProvider.overrideWithValue(auth ?? _FakeAuthRepo()),
    ],
  );
}

Future<void> _pumpSignIn(
  WidgetTester tester, {
  required _FakeStore store,
  required _FakeUnlock unlock,
  required _FakeAuthRepo auth,
}) async {
  // Taller than the 800x600 default: the sign-up form with the education
  // picker runs past the fold there, and a control the test cannot reach is a
  // harness problem, not a layout one.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedLoginStoreProvider.overrideWithValue(store),
        deviceUnlockProvider.overrideWithValue(unlock),
        authRepoProvider.overrideWithValue(auth),
      ],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeStore implements SavedLoginStore {
  _FakeStore(this.saved);

  SavedLogin? saved;

  @override
  Future<String?> readUsername() async => saved?.username;

  @override
  Future<SavedLogin?> read() async => saved;

  @override
  Future<void> save(SavedLogin login) async => saved = login;

  @override
  Future<void> clear() async => saved = null;
}

class _FakeUnlock implements DeviceUnlock {
  _FakeUnlock(this.kind, {this.passes = true});

  final DeviceLockKind kind;
  final bool passes;

  /// How many times the system prompt was raised.
  int prompts = 0;

  @override
  Future<DeviceLockKind> lockKind() async => kind;

  @override
  Future<bool> confirm(String reason) async {
    prompts++;
    return passes;
  }
}

class _FakeAuthRepo implements AuthRepo {
  _FakeAuthRepo({this.accept = true});

  /// Whether the credentials offered are the right ones.
  final bool accept;

  /// Every `username:password` pair this repo was asked to sign in with.
  final List<String> attempted = <String>[];

  AppUser? _user;
  final StreamController<AppUser?> _changes =
      StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => _changes.stream;

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async {
    attempted.add('$username:$password');
    if (!accept) throw const AuthException('Wrong username or password.');
    return _user = _userNamed(username);
  }

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) async => _user = _userNamed(username);

  @override
  Future<void> signOut() async => _user = null;

  @override
  Future<void> deleteAccount() async => _user = null;

  static AppUser _userNamed(String username) => AppUser(
    id: 'id-$username',
    username: username,
    educationLevel: EducationLevel.undergraduate,
    createdAt: DateTime(2026),
  );
}
