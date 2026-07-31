import 'package:flutter/material.dart';

import '../../core/widgets/settings_button.dart';
import '../../core/widgets/theme_toggle_button.dart';
import 'market_view.dart';

/// The Market bottom tab — the Phase 9 fake-money practice market, promoted
/// from a Sandbox sub-tab to its own destination.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SettingsButton(),
        title: const Text('Practice market'),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
      ),
      body: const MarketView(),
    );
  }
}
