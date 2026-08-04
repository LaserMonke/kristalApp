import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../games/stockle/stockle_engine.dart';

/// The board: one row per guess, plus the row being typed.
class StockleGrid extends StatelessWidget {
  const StockleGrid({super.key, required this.game, required this.typed});

  final StockleState game;
  final String typed;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];

    for (final StockleGuess guess in game.guesses) {
      rows.add(_Row(symbol: guess.symbol, marks: guess.marks));
    }

    // The in-progress row, only while there are guesses left.
    if (!game.isOver) {
      rows.add(_Row(symbol: typed, marks: null));
    }

    // Remaining empty rows, so the board does not jump about as it fills.
    final int used = game.guesses.length + (game.isOver ? 0 : 1);
    for (int i = used; i < maxGuesses; i++) {
      rows.add(const _Row(symbol: '', marks: null));
    }

    return Semantics(
      label: 'Guess ${game.guessesUsed} of $maxGuesses used.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          children: <Widget>[
            for (final Widget row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: row,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.symbol, required this.marks});

  final String symbol;

  /// Null while a row is unscored (being typed, or still empty).
  final List<LetterMark>? marks;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < tickerLength; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _Tile(
              letter: i < symbol.length ? symbol[i] : '',
              mark: marks == null ? null : marks![i],
            ),
          ),
      ],
    );
  }
}

/// One letter.
///
/// Colour is never the only signal (CLAUDE.md accessibility rule): an exact
/// match is a filled tile with a thick border, a present letter is outlined
/// with a dashed-looking double border and a corner marker, and an absent
/// letter is flat and dimmed. A colourblind player can read the board from
/// shape alone, and a screen reader gets it in words.
class _Tile extends StatelessWidget {
  const _Tile({required this.letter, required this.mark});

  final String letter;
  final LetterMark? mark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    final Color exact = dark ? AppColors.bluishGreen : AppColors.bluishGreen;
    final Color present = dark ? AppColors.orange : AppColors.orange;

    Color background;
    Color border;
    double borderWidth;
    Color foreground = theme.colorScheme.onSurface;

    switch (mark) {
      case LetterMark.exact:
        background = exact;
        border = exact;
        borderWidth = 2.5;
        foreground = Colors.white;
      case LetterMark.present:
        background = present.withValues(alpha: 0.22);
        border = present;
        borderWidth = 2.5;
      case LetterMark.absent:
        background = theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        );
        border = theme.colorScheme.outline.withValues(alpha: 0.35);
        borderWidth = 1;
        foreground = theme.colorScheme.onSurfaceVariant;
      case null:
        background = Colors.transparent;
        border = letter.isEmpty
            ? theme.colorScheme.outline.withValues(alpha: 0.4)
            : theme.colorScheme.primary;
        borderWidth = letter.isEmpty ? 1 : 2;
    }

    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Text(
                letter,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
            // The second, non-colour signal for a present letter: a corner
            // wedge that an exact match does not have.
            if (mark == LetterMark.present)
              Positioned(
                top: 3,
                right: 3,
                child: Icon(
                  Icons.swap_horiz,
                  size: 13,
                  color: AppColors.orange,
                ),
              ),
            if (mark == LetterMark.exact)
              const Positioned(
                top: 3,
                right: 3,
                child: Icon(Icons.check, size: 13, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  String get _semanticLabel {
    if (letter.isEmpty) return 'Empty';
    return switch (mark) {
      LetterMark.exact => '$letter, correct position',
      LetterMark.present => '$letter, in the ticker but elsewhere',
      LetterMark.absent => '$letter, not in the ticker',
      null => letter,
    };
  }
}
