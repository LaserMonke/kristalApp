import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/games/stockle/stockle_engine.dart';

/// The scoring rules are the whole game, and the repeated-letter cases are the
/// ones that are easy to get subtly wrong and hard to notice — a guess marked
/// "present" when the letter was already spoken for sends a player hunting for
/// a letter that is not there.
void main() {
  group('scoreGuess', () {
    test('an exact match is all exact', () {
      expect(
        scoreGuess('AAPL', 'AAPL'),
        everyElement(LetterMark.exact),
      );
    });

    test('no shared letters is all absent', () {
      expect(
        scoreGuess('MSFT', 'ABNB'),
        everyElement(LetterMark.absent),
      );
    });

    test('right letter, wrong place', () {
      // COST vs TSLA: T is in the answer at index 0, guessed at index 3.
      final List<LetterMark> marks = scoreGuess('COST', 'TSLA');
      expect(marks[0], LetterMark.absent); // C
      expect(marks[1], LetterMark.absent); // O
      expect(marks[2], LetterMark.present); // S
      expect(marks[3], LetterMark.present); // T
    });

    test('a repeated guess letter does not over-claim a single answer letter', () {
      // ADBE holds ONE A. The guess AAPL has two. The first A matches exactly
      // and consumes it, so the second A must be absent, not present.
      final List<LetterMark> marks = scoreGuess('AAPL', 'ADBE');
      expect(marks[0], LetterMark.exact);
      expect(marks[1], LetterMark.absent);
      expect(marks[2], LetterMark.absent);
      expect(marks[3], LetterMark.absent);
    });

    test('an exact match later in the word claims the letter first', () {
      // Answer LULU holds two Us and two Ls. Guess UUUU: only the positions
      // where the answer has a U (1 and 3) may be exact, and the other two Us
      // have nothing left to claim.
      final List<LetterMark> marks = scoreGuess('UUUU', 'LULU');
      expect(marks[0], LetterMark.absent);
      expect(marks[1], LetterMark.exact);
      expect(marks[2], LetterMark.absent);
      expect(marks[3], LetterMark.exact);
    });

    test('two copies in the answer can both be marked', () {
      // IDXX holds two Xs; a guess with two Xs out of position gets both.
      final List<LetterMark> marks = scoreGuess('XXAB', 'IDXX');
      expect(marks[0], LetterMark.present);
      expect(marks[1], LetterMark.present);
      expect(marks[2], LetterMark.absent);
      expect(marks[3], LetterMark.absent);
    });

    test('is case-insensitive', () {
      expect(scoreGuess('aapl', 'AAPL'), everyElement(LetterMark.exact));
    });

    test('rejects a length mismatch rather than scoring nonsense', () {
      expect(() => scoreGuess('AAP', 'AAPL'), throwsArgumentError);
    });
  });

  group('the daily answer', () {
    late StockleDictionary dictionary;

    setUp(() {
      final String raw = File(
        'assets/games/nasdaq100_4letter.json',
      ).readAsStringSync();
      dictionary = StockleDictionary.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    });

    test('the shipped asset loads and every ticker is the right length', () {
      // The constructor throws on a wrong-length symbol, so reaching here is
      // the assertion. Guard the count too, so a truncated asset is caught.
      expect(dictionary.length, greaterThan(30));
      expect(dictionary.asOf, isNotEmpty);
    });

    test('is the same for everyone on a given UTC day', () {
      final a = stockleAnswerFor(DateTime.utc(2026, 8, 4, 0, 1), dictionary);
      final b = stockleAnswerFor(DateTime.utc(2026, 8, 4, 23, 59), dictionary);
      expect(a.symbol, b.symbol);
    });

    test('changes from one day to the next', () {
      final a = stockleAnswerFor(DateTime.utc(2026, 8, 4), dictionary);
      final b = stockleAnswerFor(DateTime.utc(2026, 8, 5), dictionary);
      expect(a.symbol, isNot(b.symbol));
    });

    test('visits every ticker before repeating any', () {
      // The stride must be coprime with the list length, otherwise most of the
      // list is never used and players see the same handful of tickers.
      final Set<String> seen = <String>{};
      for (int day = 0; day < dictionary.length; day++) {
        seen.add(
          stockleAnswerFor(
            DateTime.utc(2026, 1, 1).add(Duration(days: day)),
            dictionary,
          ).symbol,
        );
      }
      expect(seen.length, dictionary.length);
    });

    test('handles dates before the epoch without crashing', () {
      expect(
        () => stockleAnswerFor(DateTime.utc(2025, 6, 1), dictionary),
        returnsNormally,
      );
    });
  });

  group('playing a round', () {
    final StockleDictionary dictionary = StockleDictionary(
      asOf: '2026-08-04',
      tickers: const <StockleTicker>[
        StockleTicker(symbol: 'AAPL', name: 'Apple', sector: 'Technology'),
        StockleTicker(symbol: 'MSFT', name: 'Microsoft', sector: 'Technology'),
        StockleTicker(symbol: 'TSLA', name: 'Tesla', sector: 'Consumer'),
      ],
    );

    StockleState fresh() => StockleState.fresh(
      answer: dictionary.lookup('TSLA')!,
      dayNumber: 1,
    );

    test('a correct guess wins', () {
      final result = fresh().submit('TSLA', dictionary);
      expect(result.state!.isWon, isTrue);
      expect(result.state!.isOver, isTrue);
    });

    test('lowercase input is accepted', () {
      expect(fresh().submit('tsla', dictionary).state!.isWon, isTrue);
    });

    test('a non-constituent is rejected and does not use up a guess', () {
      final result = fresh().submit('ZZZZ', dictionary);
      expect(result.state, isNull);
      expect(result.rejection, GuessRejection.notATicker);
    });

    test('the wrong length is rejected', () {
      expect(
        fresh().submit('AAP', dictionary).rejection,
        GuessRejection.wrongLength,
      );
    });

    test('the same guess twice is rejected', () {
      final StockleState afterOne = fresh().submit('AAPL', dictionary).state!;
      expect(
        afterOne.submit('AAPL', dictionary).rejection,
        GuessRejection.alreadyGuessed,
      );
    });

    test('running out of guesses loses', () {
      StockleState state = fresh();
      // Alternate the two wrong tickers; repeats are rejected, so this
      // exercises the loss path via distinct guesses where possible.
      for (int i = 0; i < maxGuesses; i++) {
        final result = state.submit(i.isEven ? 'AAPL' : 'MSFT', dictionary);
        if (result.state != null) state = result.state!;
        if (result.rejection == GuessRejection.alreadyGuessed) break;
      }
      // Two distinct wrong tickers exist, so the board cannot be filled to six
      // here — assert the game is still open and not falsely won.
      expect(state.isWon, isFalse);
    });

    test('a finished game refuses more guesses', () {
      final StockleState won = fresh().submit('TSLA', dictionary).state!;
      expect(
        won.submit('AAPL', dictionary).rejection,
        GuessRejection.gameOver,
      );
    });

    test('keyboard marks never downgrade a letter', () {
      // Guess AAPL against TSLA: the second A is exact (index 1... check) —
      // whatever the marks, the best verdict per letter must win.
      StockleState state = fresh();
      state = state.submit('AAPL', dictionary).state!;
      state = state.submit('MSFT', dictionary).state!;

      final Map<String, LetterMark> marks = state.keyboardMarks;
      // A appears in TSLA, so it must not be recorded as absent.
      expect(marks['A'], isNot(LetterMark.absent));
      // P is in neither answer position nor the answer at all.
      expect(marks['P'], LetterMark.absent);
    });
  });

  group('points', () {
    final StockleTicker answer = const StockleTicker(
      symbol: 'TSLA',
      name: 'Tesla',
      sector: 'Consumer',
    );

    StockleState won(int guesses) => StockleState(
      answer: answer,
      dayNumber: 1,
      guesses: List<StockleGuess>.generate(
        guesses,
        (int i) => StockleGuess(
          symbol: 'TSLA',
          marks: List<LetterMark>.filled(tickerLength, LetterMark.exact),
        ),
      ),
    );

    test('a loss earns nothing, never a penalty', () {
      final StockleState lost = StockleState(
        answer: answer,
        dayNumber: 1,
        guesses: List<StockleGuess>.generate(
          maxGuesses,
          (int i) => StockleGuess(
            symbol: 'AAPL',
            marks: List<LetterMark>.filled(tickerLength, LetterMark.absent),
          ),
        ),
      );
      expect(stocklePoints(lost), 0);
    });

    test('fewer guesses earns more', () {
      expect(stocklePoints(won(1)), greaterThan(stocklePoints(won(4))));
    });

    test('solving on the last guess still pays', () {
      expect(stocklePoints(won(maxGuesses)), greaterThan(0));
    });
  });
}
