/// Name-and-typo tolerant lookup over [kCompanyCatalog].
///
/// Pure Dart, no Flutter imports, so the ranking can be unit-tested the way
/// the pricer is. Two jobs the provider's own symbol search does not do well:
/// finding a company when the learner types its NAME rather than its ticker,
/// and still finding it when the name is misspelled.
library;

import 'company_catalog.dart';

/// One ranked hit. [score] runs 0..1; higher is a better match. [exact] marks
/// a hit good enough to act on without the learner picking from a list.
class ScoredCompany {
  const ScoredCompany({
    required this.company,
    required this.score,
    required this.exact,
  });

  final Company company;
  final double score;
  final bool exact;
}

/// Below this a hit is noise rather than a suggestion. Tuned so one or two
/// wrong letters in an ordinary company name still surfaces it, while an
/// unrelated word does not drag in half the catalogue.
const double kMatchFloor = 0.62;

/// Company-name suffixes that carry no signal. Stripping them stops "apple
/// inc" scoring worse than "apple", and stops every entry looking alike.
const List<String> _noiseWords = <String>[
  'inc',
  'corp',
  'corporation',
  'co',
  'company',
  'companies',
  'ltd',
  'limited',
  'plc',
  'holdings',
  'group',
  'sa',
  'nv',
  'ag',
  'the',
  'class',
  'trust',
  'etf',
  'fund',
];

/// Lower-case, strip punctuation, drop the noise words. "Coca-Cola Co" and
/// "coca cola" have to normalise to the same thing or name search is a lottery.
String normalizeName(String raw) {
  final String flattened = raw
      .toLowerCase()
      .replaceAll(RegExp(r"[.,&'’\-/!]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final List<String> kept = <String>[
    for (final String word in flattened.split(' '))
      if (word.isNotEmpty && !_noiseWords.contains(word)) word,
  ];
  // If a name is nothing BUT noise words ("The Trust Co"), keep it as it was
  // rather than reducing it to nothing.
  return kept.isEmpty ? flattened : kept.join(' ');
}

/// Levenshtein edit distance — the number of single-character insertions,
/// deletions or substitutions between [a] and [b]. Two rows rather than a full
/// matrix; the strings here are short and the catalogue is small.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
  List<int> current = List<int>.filled(b.length + 1, 0);

  for (int i = 1; i <= a.length; i++) {
    current[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final int deletion = previous[j] + 1;
      final int insertion = current[j - 1] + 1;
      final int substitution = previous[j - 1] + cost;
      current[j] = deletion < insertion
          ? (deletion < substitution ? deletion : substitution)
          : (insertion < substitution ? insertion : substitution);
    }
    final List<int> swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Edit distance rescaled to 0..1, where 1 is identical.
double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final int longest = a.length > b.length ? a.length : b.length;
  if (longest == 0) return 1;
  return 1 - editDistance(a, b) / longest;
}

/// Ranked catalogue matches for [rawQuery], best first.
///
/// Ordering, highest first: the exact ticker, then an exact name, then things
/// the query is a prefix of, then near-misses by edit distance. A learner who
/// knows the ticker gets it at the top; one who half-remembers the name still
/// gets a list worth reading.
List<ScoredCompany> searchCatalog(String rawQuery, {int limit = 15}) {
  final String query = normalizeName(rawQuery);
  if (query.isEmpty) return const <ScoredCompany>[];

  final String tickerQuery = rawQuery.trim().toUpperCase();
  final List<ScoredCompany> hits = <ScoredCompany>[];

  for (final Company company in kCompanyCatalog) {
    final double score = _score(company, query, tickerQuery);
    if (score >= kMatchFloor) {
      hits.add(
        ScoredCompany(
          company: company,
          score: score,
          exact: score >= 0.97,
        ),
      );
    }
  }

  hits.sort((ScoredCompany a, ScoredCompany b) {
    final int byScore = b.score.compareTo(a.score);
    // Ties break on the shorter name: "Visa" should beat "Visa Something Else"
    // when both match equally well.
    return byScore != 0
        ? byScore
        : a.company.name.length.compareTo(b.company.name.length);
  });
  return hits.length > limit ? hits.sublist(0, limit) : hits;
}

double _score(Company company, String query, String tickerQuery) {
  if (company.symbol == tickerQuery) return 1;

  final List<String> targets = <String>[
    normalizeName(company.name),
    for (final String alias in company.aliases) normalizeName(alias),
  ];

  double best = 0;
  for (final String target in targets) {
    final double s = _scoreAgainst(target, query);
    if (s > best) best = s;
  }

  // A short query is treated as a possible ticker fragment too, so "aap"
  // reaches AAPL even though the name says Apple.
  if (query.length >= 2 && company.symbol.toLowerCase().startsWith(query)) {
    const double prefix = 0.9;
    if (prefix > best) best = prefix;
  }
  return best;
}

double _scoreAgainst(String target, String query) {
  if (target == query) return 0.98;
  if (target.startsWith(query)) return 0.93;

  final List<String> tokens = target.split(' ');
  for (final String token in tokens) {
    if (token == query) return 0.9;
    if (token.startsWith(query)) return 0.86;
  }
  if (target.contains(query)) return 0.8;

  // A multi-word query where one word lands squarely: "tesla motors" is Tesla,
  // even though neither string contains the other. Without this the query is
  // only ever compared whole and drifts to whichever name shares its filler
  // word — "motors" would take it to General Motors.
  final List<String> queryTokens = query.split(' ');
  if (queryTokens.length > 1) {
    double bestToken = 0;
    for (final String queryToken in queryTokens) {
      if (queryToken.length < 3) continue;
      for (final String token in tokens) {
        if (token == queryToken && bestToken < 0.84) {
          bestToken = 0.84;
        } else if (token.startsWith(queryToken) && bestToken < 0.79) {
          bestToken = 0.79;
        }
      }
    }
    if (bestToken > 0) return bestToken;
  }

  // Nothing matched literally, so fall back to how close the spelling is.
  // Compared against the whole name AND each word, because a typo usually
  // lands in one word of several ("coca cloa").
  double best = similarity(target, query);
  for (final String token in tokens) {
    final double s = similarity(token, query);
    if (s > best) best = s;
  }

  // Very short queries are dominated by noise at this stage — "ko" is one edit
  // from dozens of words — so only literal matches count for them.
  if (query.length < 4) return 0;
  if (best < kMatchFloor) return 0;

  // Rescale the surviving band into [kMatchFloor, 0.78] so every fuzzy hit
  // still clears the floor it just passed, while sitting below every literal
  // match above — a guess never outranks something the learner actually typed.
  const double ceiling = 0.78;
  return kMatchFloor +
      (best - kMatchFloor) * (ceiling - kMatchFloor) / (1 - kMatchFloor);
}
