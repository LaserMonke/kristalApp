import 'package:flutter/material.dart';

import '../../core/widgets/theme_toggle_button.dart';
import 'single_option_pricer_view.dart';
import 'strategy_pricer_view.dart';

/// The Practice tab — the Phase 4 interactive pricer. "Single option" prices
/// one call or put live; "Strategy" composes named multi-leg strategies and
/// shows the combined payoff. Phase 9 adds the fake-money practice market
/// behind these, once unlocked.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Practice'),
          actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Single option'),
              Tab(text: 'Strategy'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[SingleOptionPricerView(), StrategyPricerView()],
        ),
      ),
    );
  }
}
