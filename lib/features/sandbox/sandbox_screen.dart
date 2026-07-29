import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/theme_toggle_button.dart';
import '../../providers/lesson_providers.dart';
import '../../providers/sandbox_tutorial_controller.dart';
import 'single_option_pricer_view.dart';
import 'strategy_pricer_view.dart';
import 'widgets/sandbox_tutorial.dart';
import 'widgets/strategy_locked_panel.dart';

/// The Sandbox tab — the Phase 4 interactive pricer. "Single option" prices
/// one call or put live; "Strategy" composes named multi-leg strategies and
/// shows the combined payoff, once the Strategies lesson has unlocked it.
/// Phase 9 adds the fake-money practice market behind these.
class SandboxScreen extends ConsumerStatefulWidget {
  const SandboxScreen({super.key});

  @override
  ConsumerState<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends ConsumerState<SandboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
  }

  void _maybeShowTutorial() {
    if (!mounted) return;
    if (ref.read(sandboxTutorialSeenProvider)) return;
    SandboxTutorial.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> strategiesUnlocked = ref.watch(
      strategiesLessonCompletedProvider,
    );
    final bool unlocked = strategiesUnlocked.value ?? false;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sandbox'),
          actions: <Widget>[
            IconButton(
              tooltip: 'How the Sandbox works',
              icon: const Icon(Icons.help_outline),
              onPressed: () => SandboxTutorial.show(context),
            ),
            const ThemeToggleButton(),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            tabs: <Widget>[
              const Tab(text: 'Single option'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Strategy'),
                    if (!unlocked) ...<Widget>[
                      const SizedBox(width: 6),
                      const Icon(Icons.lock_outline, size: 14),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            const SingleOptionPricerView(),
            unlocked ? const StrategyPricerView() : const StrategyLockedPanel(),
          ],
        ),
      ),
    );
  }
}
