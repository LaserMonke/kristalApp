import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';

/// App-bar button opening the Settings screen (`Routes.profile`).
///
/// Lives as the leading widget on every tab's app bar so Settings — the
/// disclaimers, the data-collection notice and sign-out — is always one tap
/// away, not only from Home.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => context.push(Routes.profile),
    );
  }
}
