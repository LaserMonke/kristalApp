import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/profile/widgets/reminders_section.dart';
import 'package:optionsschool/notifications/reminder_service.dart';
import 'package:optionsschool/providers/reminder_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reminder contract under CLAUDE.md rule 9, now that the default is ON:
/// the OS permission prompt is the real consent gate, a decline sticks, an
/// explicit "off" is never overridden, and unsupported platforms say so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeReminderService> pump(
    WidgetTester tester, {
    bool supported = true,
    bool permissionGranted = true,
    ReminderSettings? stored,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (stored != null) 'reminders.settings': jsonEncode(stored.toJson()),
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
          home: Scaffold(body: RemindersSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  SwitchListTile toggleOf(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byType(SwitchListTile));

  testWidgets('first run turns the reminder on once permission is granted', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester);

    expect(service.scheduled, isTrue);
    expect(service.hour, 18, reason: 'default early-evening slot');
    expect(toggleOf(tester).value, isTrue);
    expect(find.text('Reminder time'), findsOneWidget);
  });

  testWidgets('a declined OS permission leaves the reminder off', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(
      tester,
      permissionGranted: false,
    );

    expect(service.scheduled, isFalse);
    expect(toggleOf(tester).value, isFalse);

    // Trying the switch by hand explains why nothing happens.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(service.scheduled, isFalse);
    expect(toggleOf(tester).value, isFalse);
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
      stored: const ReminderSettings(enabled: false, hour: 7, minute: 30),
    );

    expect(service.attempts, 0, reason: 'a stored "off" is final');
    expect(toggleOf(tester).value, isFalse);
  });

  testWidgets('turning the reminder off cancels the schedule', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester);
    expect(service.scheduled, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(service.scheduled, isFalse);
    expect(toggleOf(tester).value, isFalse);
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
}

class _FakeReminderService implements ReminderService {
  _FakeReminderService({
    required this.supported,
    required this.permissionGranted,
  });

  final bool supported;
  final bool permissionGranted;

  bool scheduled = false;
  int attempts = 0;
  int? hour;
  int? minute;
  String? title;
  String? body;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    attempts++;
    if (!permissionGranted) return false;
    scheduled = true;
    this.hour = hour;
    this.minute = minute;
    this.title = title;
    this.body = body;
    return true;
  }

  @override
  Future<void> cancel() async => scheduled = false;
}
