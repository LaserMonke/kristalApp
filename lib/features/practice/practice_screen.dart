import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_panel.dart';
import '../../core/widgets/theme_toggle_button.dart';

/// The Practice tab — interactive pricer (Phase 4) and, once unlocked, the
/// fake-money practice market (Phase 9).
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
      ),
      body: const PlaceholderPanel(
        icon: Icons.tune_outlined,
        title: 'Interactive pricer',
        body:
            'Move spot, strike, volatility, time and rate, and watch the price, '
            'the Greeks and the payoff diagram respond.',
        phase: 'Phase 4',
      ),
    );
  }
}
