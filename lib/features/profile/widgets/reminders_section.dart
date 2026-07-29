import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../notifications/reminder_service.dart';
import '../../../providers/reminder_controller.dart';

/// The opt-in daily reminder (CLAUDE.md rule 9: encourage learning, never
/// guilt). Off by default, one notification a day at a chosen time, and the
/// off switch is exactly as prominent as the on switch.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ReminderService service = ref.watch(reminderServiceProvider);
    final ReminderSettings settings =
        ref.watch(reminderControllerProvider).value ?? ReminderSettings.off;

    if (!service.isSupported) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: const Text('Daily reminder'),
          subtitle: const Text(
            'Available in the iOS and Android apps, not on this platform.',
          ),
        ),
      );
    }

    final TimeOfDay time = TimeOfDay(
      hour: settings.hour,
      minute: settings.minute,
    );

    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Daily reminder'),
            subtitle: const Text(
              'One notification a day, at a time you choose. Off by default.',
            ),
            value: settings.enabled,
            onChanged: (bool on) => _toggle(context, ref, on: on),
          ),
          if (settings.enabled) ...<Widget>[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Reminder time'),
              subtitle: Text(time.format(context)),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _pickTime(context, ref, current: time),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Reminders only ever invite you to learn — no urgency, no '
              'guilt, and switching off costs nothing.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
      await controller.disable();
      return;
    }

    final ReminderSettings settings =
        ref.read(reminderControllerProvider).value ?? ReminderSettings.off;
    final bool enabled = await controller.enable(
      hour: settings.hour,
      minute: settings.minute,
    );
    if (!enabled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for this app. Allow them in system '
            'settings to use the reminder.',
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
      helpText: 'Daily reminder time',
    );
    if (picked == null) return;

    // Re-enabling reschedules at the new time.
    await ref
        .read(reminderControllerProvider.notifier)
        .enable(hour: picked.hour, minute: picked.minute);
  }
}
