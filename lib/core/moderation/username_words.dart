/// Word rules for usernames — the part of the username check that is about
/// MEANING rather than shape.
///
/// A username here is not private. It appears on the leaderboard next to every
/// other learner, and it is printed on the certificate, so it is the one piece
/// of user-authored text this app shows to other people. The store rating and
/// the audience make that worth filtering: an app rated for young users that
/// broadcasts whatever a stranger typed is a policy problem before it is a
/// taste problem, and CLAUDE.md rule 6 says to keep this strictly educational.
///
/// Reserved names matter for a second reason. The leaderboard carries clearly
/// labelled bots (rule 7); letting someone register "bot" or "moderator" would
/// undo that labelling by hand.
///
/// HONEST LIMITS. No blocklist catches everything, and this one is short. It
/// stops the lazy cases — typing a slur, or leetspeak around it — and it will
/// miss a determined person who spells something a way nobody anticipated. It
/// is a speed bump, not a guarantee, and it is the reason the same check runs
/// again in the database (see the username-moderation migration): a modified
/// client can skip everything here.
///
/// Pure Dart: no Flutter imports, so every rule is unit-testable on its own.
library;

/// The verdict on a username's wording.
enum UsernameWordVerdict {
  /// Nothing objectionable found.
  clean,

  /// Contains, or evades its way to, a blocked term.
  blocked,

  /// Impersonates the app, its staff, or the labelled leaderboard bots.
  reserved,
}

abstract final class UsernameWords {
  /// Terms blocked ANYWHERE inside the name.
  ///
  /// Only terms that do not appear inside ordinary English words belong here —
  /// anything that does goes in [wordTerms] instead, or "classic" gets blocked
  /// for containing a word it merely spells across a boundary.
  static const List<String> substringTerms = <String>[
    'fuck',
    'shit',
    'cunt',
    'bitch',
    'whore',
    'nigger',
    'nigga',
    'faggot',
    'retard',
    'kike',
    'wetback',
    'tranny',
    'molest',
    'pedo',
    'rapist',
    'nazi',
    'hitler',
    'incest',
    'bestiality',
    'goatse',
    'kiddyfiddler',
  ];

  /// Terms blocked only as a WHOLE word inside the name.
  ///
  /// These are the ones that hide inside innocent words — "ass" in "assess",
  /// "spic" in "auspicious", "coon" in "cocoon", "hell" in "shell". Splitting
  /// the name into words first means `bigass` and `big_ass` are caught while
  /// `assess` and `Scunthorpe` are left alone.
  static const List<String> wordTerms = <String>[
    'ass',
    'arse',
    'rape',
    'spic',
    'chink',
    'coon',
    'dyke',
    'fag',
    'homo',
    'slut',
    'dick',
    'cock',
    'prick',
    'wank',
    'twat',
    'bastard',
    'piss',
    'crap',
    'tits',
    'boob',
    'anal',
    'kkk',
    'kys',
  ];

  /// Real words that contain a blocked term and are nobody's fault.
  ///
  /// The Scunthorpe problem, named for the English town whose name a naive
  /// filter refuses. Matched against the WHOLE name, so `scunthorpe` is allowed
  /// while `scunthorpecunt` is still caught. Short, and meant to grow whenever
  /// a real person is wrongly refused — that is a bug report, not a curiosity.
  static const List<String> allowedNames = <String>[
    'scunthorpe',
    'penistone',
    'clitheroe',
    'shiitake',
    'shitake',
    'cockfosters',
    'lightwater',
  ];

  /// Names nobody may register, because using one is a claim about who you are.
  ///
  /// Matched against the whole name. The bot entries protect rule 7's promise
  /// that a labelled bot is never mistaken for a person; the app's own names
  /// stop someone posing as an announcement account.
  static const List<String> reservedNames = <String>[
    'admin',
    'administrator',
    'moderator',
    'mod',
    'staff',
    'team',
    'support',
    'help',
    'helpdesk',
    'official',
    'system',
    'root',
    'owner',
    'bot',
    'bots',
    'optionsschool',
    'stockoptionsacademy',
    'anonymous',
    'guest',
    'deleted',
    'null',
    'undefined',
    'everyone',
  ];

  /// Characters people substitute for letters when working around a filter.
  /// Folded before matching, so `sh1t` and `b4stard` are read as what they are.
  static const Map<String, String> _leet = <String, String>{
    '0': 'o',
    '1': 'i',
    '!': 'i',
    '|': 'i',
    '3': 'e',
    '4': 'a',
    '@': 'a',
    '5': 's',
    r'$': 's',
    '7': 't',
    '+': 't',
    '8': 'b',
    '9': 'g',
  };

  /// The name reduced to bare lowercase letters, with leet substitutions undone.
  ///
  /// Used for the substring pass, where separators are exactly what someone
  /// hides behind: `f.u.c.k` and `sh_it` collapse onto the same letters.
  static String normalise(String username) {
    final StringBuffer out = StringBuffer();
    for (final String char in username.toLowerCase().split('')) {
      final String folded = _leet[char] ?? char;
      final int code = folded.codeUnitAt(0);
      // a-z only; everything else is a separator and simply disappears.
      if (folded.length == 1 && code >= 0x61 && code <= 0x7a) {
        out.write(folded);
      }
    }
    return out.toString();
  }

  /// Runs of the same letter squeezed to one, so `fuuuck` reads as `fuck`.
  ///
  /// Applied to the name only, never to the terms — collapsing both sides
  /// would turn `coon` into `con` and start matching innocent words.
  static String collapseRuns(String value) {
    final StringBuffer out = StringBuffer();
    String? previous;
    for (final String char in value.split('')) {
      if (char != previous) out.write(char);
      previous = char;
    }
    return out.toString();
  }

  /// The name split into the words a reader would see.
  ///
  /// Splits on separators, on digit runs, and on camelCase humps, so
  /// `bigAss`, `big_ass` and `big2ass` all yield `ass` while `assess` stays
  /// whole. Leet folding runs afterwards on each word: splitting first is what
  /// keeps `big2ass` apart, since folding turns some digits into letters.
  static List<String> words(String username) {
    final List<String> raw = username
        // camelCase hump: insert a break between a lower and an upper.
        .replaceAllMapped(
          RegExp('([a-z])([A-Z])'),
          (Match m) => '${m[1]} ${m[2]}',
        )
        .split(RegExp('[^A-Za-z0-9!|@\$+]+'))
        .where((String part) => part.isNotEmpty)
        .toList();

    // A digit is ambiguous: in `b4stard` it stands in for a letter, in
    // `big2ass` it is a separator. Both readings are produced and both are
    // checked, because guessing wrong in either direction lets one through.
    final List<String> out = <String>[];
    for (final String part in raw) {
      final String whole = normalise(part);
      if (whole.isNotEmpty) out.add(whole);

      for (final String piece in part.split(RegExp('[0-9]+'))) {
        final String folded = normalise(piece);
        if (folded.isNotEmpty && folded != whole) out.add(folded);
      }
    }
    return out;
  }

  /// The verdict for [username].
  static UsernameWordVerdict verdict(String username) {
    final String flat = normalise(username);
    if (flat.isEmpty) return UsernameWordVerdict.clean;

    final String squeezed = collapseRuns(flat);

    if (reservedNames.contains(flat) || reservedNames.contains(squeezed)) {
      return UsernameWordVerdict.reserved;
    }

    // An exact known-innocent word beats the term lists. Checked after the
    // reserved names so the exception list can never hand out a staff name.
    if (allowedNames.contains(flat)) return UsernameWordVerdict.clean;

    for (final String term in substringTerms) {
      if (flat.contains(term) || squeezed.contains(term)) {
        return UsernameWordVerdict.blocked;
      }
    }

    for (final String word in words(username)) {
      final String squeezedWord = collapseRuns(word);
      for (final String term in wordTerms) {
        // The squeezed form only counts when the original was at least as long
        // as the term, so `as` is not read as a squeezed `ass`.
        if (word == term ||
            (word.length >= term.length && squeezedWord == term)) {
          return UsernameWordVerdict.blocked;
        }
      }
    }

    return UsernameWordVerdict.clean;
  }

  /// Null when [username] is acceptable, otherwise a reason safe to show.
  ///
  /// The message never repeats the offending word back: quoting it would put
  /// the thing we are filtering on screen, and a learner who typed it by
  /// accident does not need it spelled out.
  static String? check(String username) => switch (verdict(username)) {
    UsernameWordVerdict.clean => null,
    UsernameWordVerdict.reserved =>
      'That username is reserved. Please choose another.',
    UsernameWordVerdict.blocked =>
      'Please choose a different username — this one shows on the '
          'leaderboard for everyone.',
  };
}
