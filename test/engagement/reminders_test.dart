import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/profile/widgets/reminders_section.dart';
import 'package:optionsschool/notifications/reminder_service.dart';
import 'package:optionsschool/providers/reminder_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reminder rules that CLAUDE.md rule 9 hangs on: strictly opt-in, honest
/// about platform limits, and a declined OS permission leaves everything off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeReminderService> pump(
    WidgetTester tester, {
    bool supported = true,
    bool permissionGranted = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  testWidgets('the reminder is off by default', (WidgetTester tester) async {
    final _FakeReminderService service = await pump(tester);

    final SwitchListTile toggle = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggle.value, isFalse);
    expect(service.scheduled, isFalse);
    expect(find.text('Reminder time'), findsNothing);
  });

  testWidgets('opting in schedules one daily reminder', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(service.scheduled, isTrue);
    expect(service.hour, 18, reason: 'default early-evening slot');
    expect(find.text('Reminder time'), findsOneWidget);
  });

  testWidgets('a declined OS permission leaves the reminder off', (
    WidgetTester tester,
  ) async {
    final _FakeReminderService service = await pump(
      tester,
      permissionGranted: false,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(service.scheduled, isFalse);
    final SwitchListTile toggle = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggle.value, isFalse);
    expect(
      find.textContaining('Notifications are blocked'),
      findsOneWidget,
      reason: 'the learner is told why nothing happened',
    );
  });

  testWidgets('an unsupported platform says so instead of pretending', (
    WidgetTester tester,
  ) async {
    await pump(tester, supported: false);

    expect(find.byType(SwitchListTile), findsNothing);
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
  int? hour;
  int? minute;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> scheduleDaily({required int hour, required int minute}) async {
    if (!permissionGranted) return false;
    scheduled = true;
    this.hour = hour;
    this.minute = minute;
    return true;
  }

  @override
  Future<void> cancel() async => scheduled = false;
}
