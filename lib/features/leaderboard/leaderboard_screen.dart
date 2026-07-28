import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_panel.dart';
import '../../core/widgets/theme_toggle_button.dart';

/// The Ranks tab — leaderboard across real learners (Phase 7).
///
/// Per CLAUDE.md rule 7, any bot entries used to pad early rankings must be
/// labelled as bots; they are never presented as real people.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranks'),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
      ),
      body: const PlaceholderPanel(
        icon: Icons.leaderboard_outlined,
        title: 'Leaderboard',
        body:
            'Weekly and all-time standings once accounts sync to the server. '
            'Any practice bots will be labelled as bots, never as real people.',
        phase: 'Phase 7',
      ),
    );
  }
}
