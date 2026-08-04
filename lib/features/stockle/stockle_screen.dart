import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/disclaimer_text.dart';
import '../../games/stockle/stockle_engine.dart';
import '../../providers/stockle_providers.dart';
import 'widgets/stockle_grid.dart';
import 'widgets/stockle_hint.dart';
import 'widgets/stockle_keyboard.dart';
import 'widgets/stockle_result.dart';

/// Stockle — one NASDAQ-100 ticker a day, six guesses.
///
/// The point is not the game. Finishing opens an overview of the company
/// behind the ticker, which is the part that teaches something.
class StockleScreen extends ConsumerStatefulWidget {
  const StockleScreen({super.key});

  @override
  ConsumerState<StockleScreen> createState() => _StockleScreenState();
}

class _StockleScreenState extends ConsumerState<StockleScreen> {
  String _typed = '';

  /// Whether the player has asked to see today's hint. Not persisted: it costs
  /// nothing to tap again, and a hint the player never wanted should not
  /// reappear on its own after a restart.
  bool _hintRevealed = false;

  void _onLetter(String letter) {
    if (_typed.length >= tickerLength) return;
    setState(() => _typed += letter);
  }

  void _onBackspace() {
    if (_typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  Future<void> _onSubmit() async {
    final String attempt = _typed;
    final GuessRejection? rejection = await ref
        .read(stockleProvider.notifier)
        .guess(attempt);

    if (!mounted) return;

    if (rejection != null) {
      // Keep the letters on screen — a rejected guess is usually a typo, and
      // wiping the row would make the player retype the whole thing.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(rejection.message),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    setState(() => _typed = '');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<StockleDictionary> dictionary = ref.watch(
      stockleDictionaryProvider,
    );
    final StockleState? game = ref.watch(stockleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stockle'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to play',
            onPressed: () => _showHowToPlay(context),
          ),
        ],
      ),
      body: dictionary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _LoadFailed(error: error),
        data: (StockleDictionary dict) {
          if (game == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: <Widget>[
                        Text(
                          'Guess today’s NASDAQ-100 ticker',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$tickerLength letters · $maxGuesses tries · '
                          'a new one every day',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        StockleGrid(game: game, typed: _typed),
                        if (!game.isOver) ...<Widget>[
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: StockleHintPanel(
                              game: game,
                              revealed: _hintRevealed,
                              onReveal: () =>
                                  setState(() => _hintRevealed = true),
                            ),
                          ),
                        ],
                        if (game.isOver) ...<Widget>[
                          const SizedBox(height: 20),
                          StockleResult(game: game),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (!game.isOver)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: StockleKeyboard(
                      marks: game.keyboardMarks,
                      canSubmit: _typed.length == tickerLength,
                      canDelete: _typed.isNotEmpty,
                      onLetter: _onLetter,
                      onBackspace: _onBackspace,
                      onSubmit: _onSubmit,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showHowToPlay(BuildContext context) {
    final int listSize =
        ref.read(stockleDictionaryProvider).value?.length ?? 0;
    final String asOf =
        ref.read(stockleDictionaryProvider).value?.asOf ?? 'unknown';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'How to play',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Guess the $tickerLength-letter ticker in $maxGuesses tries. '
                'Each guess must be a ticker from the list.\n\n'
                'After each guess the tiles show how close you were. A filled '
                'tile with a ring means the letter is in the right place. A '
                'half-filled tile means the letter is in the ticker but '
                'somewhere else. An empty tile means the letter is not in it '
                'at all.\n\n'
                'After $guessesBeforeHint guesses a hint unlocks: the '
                'company’s sector and the first letter of its name. It is '
                'there if you want it, and taking it costs no points.\n\n'
                'Solve it and you earn points, the same as getting a lesson '
                'question right. Miss it and you lose nothing.\n\n'
                'The puzzle changes at midnight UTC, and everyone gets the '
                'same ticker.',
              ),
              const SizedBox(height: 16),
              Text(
                'The list holds $listSize NASDAQ-100 companies whose ticker is '
                '$tickerLength letters, as of $asOf. Index membership changes, '
                'so the list can fall behind. It is a game list, not a '
                'reference index, and nothing here is a suggestion to buy or '
                'sell anything.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              const DisclaimerBanner(text: Disclaimers.noAdviceShort),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.grid_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'Today’s puzzle could not be loaded.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The ticker list is bundled with the app, so this is a bug '
              'rather than a connection problem.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
