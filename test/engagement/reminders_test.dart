import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/profile/widgets/reminders_section.dart';
import 'package:optionsschool/notifications/reminder_service.dart';
import 'package:optionsschool/providers/reminder_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reminder contract under CLAUDE.md rule 9, now that there are three of
/// them and the default is ON: the OS permission prompt is the real consent
/// gate, a decline sticks, an explicit "off" is never overridden, an existing
/// install is not opted into the newer kinds by an update, and unsupported
/// platforms say so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeReminderService> pump(
    WidgetTester tester, {
    bool supported = true,
    bool permissionGranted = true,
    ReminderSettings? stored,
    String? storedRaw,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (storedRaw != null)
        'reminders.settings': storedRaw
      else if (stored != null)
        'reminders.settings': jsonEncode(stored.toJson()),
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeReminderService service = _FakeReminderService(
      supported: supported,
      permissionGranted: permissionGranted,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reminderServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: RemindersSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  SwitchListTile switchFor(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );

  testWidgets('first run turns all three on once permission is granted', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester);

    expect(service.scheduled.keys, containsAll(ReminderKind.values));
    expect(switchFor(tester, 'Lesson reminder').value, isTrue);
    expect(switchFor(tester, 'Daily game').value, isTrue);
    expect(switchFor(tester, 'Practice market').value, isTrue);
  });

  testWidgets('the three sit at different times of day', (
    WidgetTester tester,
  ) async {
    // Spread out on purpose: three notifications arriving together is one app
    // nagging three times, which is the thing rule 9 rules out.
    final _FakeReminderService service = await pump(tester);

    expect(service.scheduled[ReminderKind.dailyGame]!.hour, 9);
    expect(service.scheduled[ReminderKind.market]!.hour, 12);
    expect(service.scheduled[ReminderKind.lesson]!.hour, 18);

    final Set<int> hours = service.scheduled.values
        .map((({int hour, int minute}) t) => t.hour)
        .toSet();
    expect(hours.length, 3, reason: 'no two reminders share an hour');
  });

  testWidgets('a declined OS permission leaves them all off', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(
      tester,
      permissionGranted: false,
    );

    expect(service.scheduled, isEmpty);
    expect(switchFor(tester, 'Lesson reminder').value, isFalse);
    expect(switchFor(tester, 'Daily game').value, isFalse);

    // One refusal, not three dialogs: the permission is app-wide.
    expect(service.attempts, 1);

    await tester.tap(find.text('Lesson reminder'));
    await tester.pumpAndSettle();
    expect(service.scheduled, isEmpty);
    expect(
      find.textContaining('Notifications are blocked'),
      findsOneWidget,
      reason: 'the learner is told why nothing happened',
    );
  });

  testWidgets('an explicit off is remembered — never re-enabled at launch', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(
      tester,
      stored: const ReminderSettings(
        lesson: ReminderSlot(enabled: false, hour: 7, minute: 30),
      ),
    );

    expect(service.attempts, 0, reason: 'a stored choice is final');
    expect(switchFor(tester, 'Lesson reminder').value, isFalse);
  });

  testWidgets('an existing install is not opted into the newer reminders', (
    WidgetTester tester,
  ) async {
    // Exactly what an install from before the other two kinds wrote: the flat
    // lesson keys and nothing else. Waking up to two more notifications a day
    // because the app updated is not a choice the update gets to make.
    final _FakeReminderService service = await pump(
      tester,
      storedRaw: jsonEncode(<String, dynamic>{
        'enabled': true,
        'hour': 18,
        'minute': 0,
      }),
    );

    expect(service.attempts, 0, reason: 'a stored choice is final');
    expect(switchFor(tester, 'Lesson reminder').value, isTrue);
    expect(switchFor(tester, 'Daily game').value, isFalse);
    expect(switchFor(tester, 'Practice market').value, isFalse);
  });

  testWidgets('turning one off leaves the others scheduled', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester);
    expect(service.scheduled.length, 3);

    await tester.tap(find.text('Daily game'));
    await tester.pumpAndSettle();

    expect(service.scheduled.containsKey(ReminderKind.dailyGame), isFalse);
    expect(service.scheduled.containsKey(ReminderKind.lesson), isTrue);
    expect(service.scheduled.containsKey(ReminderKind.market), isTrue);
    expect(switchFor(tester, 'Daily game').value, isFalse);
    expect(switchFor(tester, 'Lesson reminder').value, isTrue);
  });

  testWidgets('an unsupported platform says so instead of pretending', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester, supported: false);

    expect(find.byType(SwitchListTile), findsNothing);
    expect(service.attempts, 0);
    expect(
      find.textContaining('Available in the iOS and Android apps'),
      findsOneWidget,
    );
  });

  test('no two reminder kinds share a notification id or channel', () {
    // The OS keys a pending notification on its id, so a collision would mean
    // one reminder silently replacing another.
    final Set<int> ids = ReminderKind.values.map((ReminderKind k) => k.id).toSet();
    final Set<String> channels = ReminderKind.values
        .map((ReminderKind k) => k.channelId)
        .toSet();

    expect(ids.length, ReminderKind.values.length);
    expect(channels.length, ReminderKind.values.length);
  });
}

class _FakeReminderService implements ReminderService {
  _FakeReminderService({
    required this.supported,
    required this.permissionGranted,
  });

  final bool supported;
  final bool permissionGranted;

  /// What is currently scheduled, by kind.
  final Map<ReminderKind, ({int hour, int minute})> scheduled =
      <ReminderKind, ({int hour, int minute})>{};
  final Map<ReminderKind, String> titles = <ReminderKind, String>{};
  final Map<ReminderKind, String> bodies = <ReminderKind, String>{};
  int attempts = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> scheduleDaily({
    required ReminderKind kind,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    attempts++;
    if (!permissionGranted) return false;
    scheduled[kind] = (hour: hour, minute: minute);
    titles[kind] = title;
    bodies[kind] = body;
    return true;
  }

  @override
  Future<void> cancel(ReminderKind kind) async => scheduled.remove(kind);
}
