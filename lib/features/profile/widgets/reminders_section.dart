import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../notifications/reminder_service.dart';
import '../../../providers/reminder_controller.dart';

/// The daily reminders (CLAUDE.md rule 9: encourage learning, never guilt).
///
/// Three of them, spread across the day, each switched and timed on its own.
/// On by default on a fresh install behind the OS permission prompt; an
/// explicit "off" is never overridden, and an existing install is never
/// opted into the two newer ones by an update.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ReminderService service = ref.watch(reminderServiceProvider);
    final ReminderSettings settings =
        ref.watch(reminderControllerProvider).value ?? ReminderSettings.off;

    if (!service.isSupported) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('Reminders'),
          subtitle: Text(
            'Available in the iOS and Android apps, not on this platform.',
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: <Widget>[
          for (final ReminderKind kind in ReminderKind.values) ...<Widget>[
            if (kind != ReminderKind.values.first) const Divider(height: 1),
            _ReminderTile(kind: kind, slot: settings.slot(kind)),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Reminders only ever invite you — no urgency, no guilt, no '
              'counting what you missed. Switching any of them off costs '
              'nothing.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.kind, required this.slot});

  final ReminderKind kind;
  final ReminderSlot slot;

  static const Map<ReminderKind, (String, String, IconData)> _labels =
      <ReminderKind, (String, String, IconData)>{
        ReminderKind.lesson: (
          'Lesson reminder',
          'A nudge to pick up where you left off.',
          Icons.school_outlined,
        ),
        ReminderKind.dailyGame: (
          'Daily game',
          'Stockle, when the new ticker goes up.',
          Icons.grid_view_outlined,
        ),
        ReminderKind.market: (
          'Practice market',
          'A look at your simulated portfolio.',
          Icons.show_chart_outlined,
        ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (String title, String subtitle, IconData icon) = _labels[kind]!;
    final TimeOfDay time = TimeOfDay(hour: slot.hour, minute: slot.minute);

    return Column(
      children: <Widget>[
        SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          value: slot.enabled,
          onChanged: (bool on) => _toggle(context, ref, on: on),
        ),
        if (slot.enabled)
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Time'),
            subtitle: Text(time.format(context)),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _pickTime(context, ref, current: time),
          ),
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    final ReminderController controller = ref.read(
      reminderControllerProvider.notifier,
    );
    if (!on) {
      await controller.disable(kind);
      return;
    }

    final bool enabled = await controller.enable(
      kind,
      hour: slot.hour,
      minute: slot.minute,
    );
    if (!enabled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for this app. Allow them in system '
            'settings to use reminders.',
          ),
        ),
      );
    }
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref, {
    required TimeOfDay current,
  }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'Reminder time',
    );
    if (picked == null) return;

    // Re-enabling reschedules at the new time.
    await ref
        .read(reminderControllerProvider.notifier)
        .enable(kind, hour: picked.hour, minute: picked.minute);
  }
}
