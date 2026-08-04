/// Stockle — the daily ticker-guessing game, as pure Dart.
///
/// NO Flutter imports, so every rule here is unit-testable on its own, the
/// same discipline the pricer library follows.
///
/// The game is Wordle's shape with NASDAQ-100 tickers in place of words:
/// [tickerLength] letters, [maxGuesses] attempts, and a per-letter verdict
/// after each guess. Guesses must themselves be tickers in the list, which is
/// the equivalent of Wordle only accepting dictionary words — it keeps the game
/// solvable by reasoning rather than by brute-forcing letters.
library;

const int tickerLength = 4;
const int maxGuesses = 6;

/// How many guesses a player spends before a hint becomes available.
///
/// Three of six: late enough that the hint rescues a stuck player rather than
/// short-cutting the puzzle, early enough that there are still guesses left to
/// spend on what it tells them.
const int guessesBeforeHint = 3;

/// What a single letter position earned.
enum LetterMark {
  /// Right letter, right position.
  exact,

  /// Letter is in the answer, but not here — and not already accounted for by
  /// an exact match or an earlier present mark.
  present,

  /// Not in the answer, or every copy of it is already spoken for.
  absent,
}

/// One ticker in the playable set.
class StockleTicker {
  const StockleTicker({
    required this.symbol,
    required this.name,
    required this.sector,
  });

  factory StockleTicker.fromJson(Map<String, dynamic> json) => StockleTicker(
    symbol: (json['symbol'] as String).toUpperCase(),
    name: json['name'] as String,
    sector: json['sector'] as String? ?? 'Unknown',
  );

  final String symbol;
  final String name;
  final String sector;
}

/// The playable set plus the metadata that keeps it honest.
class StockleDictionary {
  StockleDictionary({
    required this.tickers,
    required this.asOf,
  }) : _bySymbol = <String, StockleTicker>{
         for (final StockleTicker t in tickers) t.symbol: t,
       } {
    // A wrong-length ticker would break the grid and make a puzzle unsolvable,
    // so fail at load rather than at 3am on someone's phone.
    for (final StockleTicker t in tickers) {
      if (t.symbol.length != tickerLength) {
        throw ArgumentError.value(
          t.symbol,
          'symbol',
          'Stockle needs exactly $tickerLength letters',
        );
      }
    }
    if (tickers.length < 2) {
      throw ArgumentError('Stockle needs at least two tickers to rotate.');
    }
  }

  factory StockleDictionary.fromJson(Map<String, dynamic> json) =>
      StockleDictionary(
        tickers: (json['tickers'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(StockleTicker.fromJson)
            .toList(growable: false),
        asOf: json['as_of'] as String? ?? 'unknown',
      );

  final List<StockleTicker> tickers;

  /// When the constituent list was last checked. Surfaced in the UI: index
  /// membership drifts, and claiming otherwise would be the same dishonesty as
  /// an unlabelled delayed price (CLAUDE.md rule 8).
  final String asOf;

  final Map<String, StockleTicker> _bySymbol;

  int get length => tickers.length;

  bool contains(String symbol) => _bySymbol.containsKey(symbol.toUpperCase());

  StockleTicker? lookup(String symbol) => _bySymbol[symbol.toUpperCase()];
}

/// Scores [guess] against [answer], Wordle's two-pass rule.
///
/// The subtlety is repeated letters. A guess of AAPL against ADBE must mark
/// only the FIRST A — the answer holds one A, and the exact-position match
/// consumes it. Doing this in one pass over-reports [LetterMark.present] and
/// makes the game misleading, so exact matches are claimed first and only the
/// leftovers are available to later positions.
List<LetterMark> scoreGuess(String guess, String answer) {
  final String g = guess.toUpperCase();
  final String a = answer.toUpperCase();

  if (g.length != a.length) {
    throw ArgumentError('Guess and answer must be the same length.');
  }

  final List<LetterMark> marks = List<LetterMark>.filled(
    g.length,
    LetterMark.absent,
  );

  // How many of each letter the answer still has to give out.
  final Map<String, int> unclaimed = <String, int>{};

  // Pass 1 — exact positions, which take priority over everything.
  for (int i = 0; i < g.length; i++) {
    if (g[i] == a[i]) {
      marks[i] = LetterMark.exact;
    } else {
      unclaimed[a[i]] = (unclaimed[a[i]] ?? 0) + 1;
    }
  }

  // Pass 2 — wrong position, but only while copies remain.
  for (int i = 0; i < g.length; i++) {
    if (marks[i] == LetterMark.exact) continue;
    final int left = unclaimed[g[i]] ?? 0;
    if (left > 0) {
      marks[i] = LetterMark.present;
      unclaimed[g[i]] = left - 1;
    }
  }

  return marks;
}

/// The day a puzzle belongs to, as a whole number.
///
/// Computed in UTC from a fixed epoch so that every player worldwide gets the
/// same ticker on the same calendar day, and so the answer cannot be fished out
/// early by changing the device clock's timezone.
int stockleDayNumber(DateTime date) {
  final DateTime utcDay = DateTime.utc(date.year, date.month, date.day);
  return utcDay.difference(_epoch).inDays;
}

final DateTime _epoch = DateTime.utc(2026, 1, 1);

/// Picks the ticker for [date].
///
/// Walks the list in strides rather than in order, so consecutive days are not
/// alphabetical neighbours. [_stride] is coprime with the list length (checked
/// below), which makes the walk a full cycle: every ticker is used exactly once
/// before any repeats.
StockleTicker stockleAnswerFor(DateTime date, StockleDictionary dictionary) {
  final int day = stockleDayNumber(date);
  final int n = dictionary.length;
  final int stride = _strideFor(n);

  // Dart's % returns a non-negative result for a positive divisor, so dates
  // before the epoch still land in range.
  return dictionary.tickers[(day * stride) % n];
}

const int _preferredStride = 37;

int _strideFor(int n) {
  // Falls back to 1 (plain order) if the preferred stride shares a factor with
  // the list length, because a shared factor would visit only part of the list
  // and silently starve most tickers.
  return _gcd(_preferredStride, n) == 1 ? _preferredStride : 1;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// Why a guess was rejected, in words safe to show a player verbatim.
enum GuessRejection { wrongLength, notATicker, alreadyGuessed, gameOver }

extension GuessRejectionMessage on GuessRejection {
  String get message => switch (this) {
    GuessRejection.wrongLength => 'Tickers are $tickerLength letters.',
    GuessRejection.notATicker =>
      'Not a NASDAQ-100 ticker in today’s list.',
    GuessRejection.alreadyGuessed => 'You have already tried that one.',
    GuessRejection.gameOver => 'Today’s puzzle is finished.',
  };
}

/// The clue offered once [guessesBeforeHint] guesses have been spent.
///
/// It points at the COMPANY, never at the letters. Revealing a position would
/// turn the remaining rows into fill-in-the-blank and skip the reasoning that
/// is the whole game; naming the sector and the company's initial instead makes
/// the player join a business to its ticker, which is the thing Stockle is
/// there to teach.
class StockleHint {
  const StockleHint({required this.sector, required this.nameInitial});

  final String sector;

  /// First letter of the company's name — not of the ticker.
  final String nameInitial;
}

/// A guess that has been scored.
class StockleGuess {
  const StockleGuess({required this.symbol, required this.marks});

  final String symbol;
  final List<LetterMark> marks;

  bool get isCorrect => marks.every((LetterMark m) => m == LetterMark.exact);
}

/// Immutable snapshot of one day's game.
class StockleState {
  const StockleState({
    required this.answer,
    required this.guesses,
    required this.dayNumber,
  });

  StockleState.fresh({required this.answer, required this.dayNumber})
    : guesses = const <StockleGuess>[];

  final StockleTicker answer;
  final List<StockleGuess> guesses;
  final int dayNumber;

  bool get isWon => guesses.isNotEmpty && guesses.last.isCorrect;

  bool get isLost => !isWon && guesses.length >= maxGuesses;

  bool get isOver => isWon || isLost;

  int get guessesUsed => guesses.length;

  /// The clue, or null while it is still locked.
  ///
  /// Null once the game is over too, because the result panel names the company
  /// outright and a hint alongside it would just be noise. Taking the hint
  /// costs nothing: [stocklePoints] never sees it, so a stuck player is helped
  /// rather than charged for asking (CLAUDE.md rule 9).
  StockleHint? get hint {
    if (isOver || guesses.length < guessesBeforeHint) return null;
    return StockleHint(
      sector: answer.sector,
      nameInitial: answer.name.isEmpty ? '?' : answer.name[0].toUpperCase(),
    );
  }

  /// Best-known verdict per letter across every guess so far, for colouring an
  /// on-screen keyboard. Exact beats present beats absent, so a letter never
  /// downgrades as the game goes on.
  Map<String, LetterMark> get keyboardMarks {
    final Map<String, LetterMark> best = <String, LetterMark>{};
    for (final StockleGuess guess in guesses) {
      for (int i = 0; i < guess.symbol.length; i++) {
        final String letter = guess.symbol[i];
        final LetterMark mark = guess.marks[i];
        final LetterMark? existing = best[letter];
        if (existing == null || _rank(mark) > _rank(existing)) {
          best[letter] = mark;
        }
      }
    }
    return best;
  }

  static int _rank(LetterMark mark) => switch (mark) {
    LetterMark.absent => 0,
    LetterMark.present => 1,
    LetterMark.exact => 2,
  };

  /// Validates [symbol] and returns the new state, or the reason it was
  /// rejected. Never mutates: the caller swaps the state it holds.
  ({StockleState? state, GuessRejection? rejection}) submit(
    String symbol,
    StockleDictionary dictionary,
  ) {
    final String candidate = symbol.trim().toUpperCase();

    if (isOver) {
      return (state: null, rejection: GuessRejection.gameOver);
    }
    if (candidate.length != tickerLength) {
      return (state: null, rejection: GuessRejection.wrongLength);
    }
    if (!dictionary.contains(candidate)) {
      return (state: null, rejection: GuessRejection.notATicker);
    }
    if (guesses.any((StockleGuess g) => g.symbol == candidate)) {
      return (state: null, rejection: GuessRejection.alreadyGuessed);
    }

    final StockleGuess scored = StockleGuess(
      symbol: candidate,
      marks: scoreGuess(candidate, answer.symbol),
    );

    return (
      state: StockleState(
        answer: answer,
        dayNumber: dayNumber,
        guesses: <StockleGuess>[...guesses, scored],
      ),
      rejection: null,
    );
  }
}

/// Points for finishing today's puzzle.
///
/// Fewer guesses earns more, but solving at all is worth most of it — the
/// gradient rewards thinking without punishing a learner who needed the whole
/// board. A loss earns nothing rather than going negative; taking points away
/// for playing would be the kind of dark pattern CLAUDE.md rule 9 rules out.
int stocklePoints(StockleState state) {
  if (!state.isWon) return 0;
  const int base = 20;
  final int speedBonus = (maxGuesses - state.guessesUsed) * 3;
  return base + speedBonus;
}
