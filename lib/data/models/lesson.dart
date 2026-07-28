import '../../pricing/payoff.dart';

/// Lesson content as DATA.
///
/// Per CLAUDE.md, lessons are models parsed from bundled JSON — the engine
/// renders them and adding a lesson means adding data, not engine code. The
/// card types below are the vocabulary an author can use; extend the sealed
/// hierarchy (and [LessonCardView]) when a genuinely new kind of card is
/// needed, not for every lesson.
class Lesson {
  const Lesson({
    required this.id,
    required this.order,
    required this.title,
    required this.summary,
    required this.cards,
    this.estimatedMinutes = 3,
    this.quizQuestionCount = 0,
    this.reviewedBy,
    this.reviewedOn,
  });

  final String id;

  /// Position in the learning path. Lower comes first.
  final int order;

  final String title;
  final String summary;
  final List<LessonCard> cards;
  final int estimatedMinutes;

  /// How many Q&A questions this lesson has. Zero until Phase 2 authors them;
  /// the unlock gate reads this so it moves from "finished the cards" to
  /// "finished the Q&A" the moment questions exist, with no engine change.
  final int quizQuestionCount;

  /// Expert review trail required by CLAUDE.md ("reviewed by/date per lesson").
  /// Null means NOT yet reviewed by someone with real derivatives knowledge,
  /// and the UI says so rather than staying quiet about it.
  final String? reviewedBy;
  final DateTime? reviewedOn;

  bool get hasQuiz => quizQuestionCount > 0;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawCards = json['cards'] as List<dynamic>? ?? <dynamic>[];
    final String? reviewedOn = json['reviewed_on'] as String?;

    return Lesson(
      id: json['id'] as String,
      order: json['order'] as int,
      title: json['title'] as String,
      summary: json['summary'] as String,
      estimatedMinutes: json['estimated_minutes'] as int? ?? 3,
      quizQuestionCount:
          (json['questions'] as List<dynamic>?)?.length ??
          (json['question_count'] as int? ?? 0),
      reviewedBy: json['reviewed_by'] as String?,
      reviewedOn: reviewedOn == null ? null : DateTime.tryParse(reviewedOn),
      cards: <LessonCard>[
        for (final dynamic card in rawCards)
          LessonCard.fromJson(card as Map<String, dynamic>),
      ],
    );
  }
}

/// One swipeable card in the reel.
///
/// Sealed so the renderer's switch is exhaustive — a new card type won't
/// compile until it has been given a visual treatment.
sealed class LessonCard {
  const LessonCard();

  factory LessonCard.fromJson(Map<String, dynamic> json) {
    final String type = json['type'] as String;
    return switch (type) {
      'title' => TitleCard.fromJson(json),
      'text' => TextCard.fromJson(json),
      'term' => TermCard.fromJson(json),
      'payoff' => PayoffCard.fromJson(json),
      'warning' => WarningCard.fromJson(json),
      'summary' => SummaryCard.fromJson(json),
      _ => throw FormatException('Unknown lesson card type "$type"'),
    };
  }

  /// Spoken description for screen readers, so a card is never image-only.
  String get semanticLabel;
}

/// Opening card: sets up what the lesson is about.
class TitleCard extends LessonCard {
  const TitleCard({required this.title, required this.subtitle, this.kicker});

  final String title;
  final String subtitle;
  final String? kicker;

  @override
  String get semanticLabel => '$title. $subtitle';

  factory TitleCard.fromJson(Map<String, dynamic> json) => TitleCard(
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    kicker: json['kicker'] as String?,
  );
}

/// The workhorse: a short heading, a paragraph or two, optional bullets.
class TextCard extends LessonCard {
  const TextCard({
    required this.heading,
    required this.body,
    this.bullets = const <String>[],
  });

  final String heading;
  final String body;
  final List<String> bullets;

  @override
  String get semanticLabel => <String>[heading, body, ...bullets].join('. ');

  factory TextCard.fromJson(Map<String, dynamic> json) => TextCard(
    heading: json['heading'] as String,
    body: json['body'] as String,
    bullets: <String>[
      for (final dynamic b in json['bullets'] as List<dynamic>? ?? <dynamic>[])
        b as String,
    ],
  );
}

/// A single piece of vocabulary, given room to land.
class TermCard extends LessonCard {
  const TermCard({
    required this.term,
    required this.definition,
    this.example,
  });

  final String term;
  final String definition;
  final String? example;

  @override
  String get semanticLabel =>
      '$term. $definition${example == null ? '' : '. For example, $example'}';

  factory TermCard.fromJson(Map<String, dynamic> json) => TermCard(
    term: json['term'] as String,
    definition: json['definition'] as String,
    example: json['example'] as String?,
  );
}

/// A payoff diagram drawn from strategy legs.
class PayoffCard extends LessonCard {
  const PayoffCard({
    required this.heading,
    required this.caption,
    required this.legs,
    required this.spotMin,
    required this.spotMax,
    this.currencySymbol = r'$',
  });

  final String heading;
  final String caption;
  final List<StrategyLeg> legs;
  final double spotMin;
  final double spotMax;
  final String currencySymbol;

  @override
  String get semanticLabel => '$heading. $caption';

  factory PayoffCard.fromJson(Map<String, dynamic> json) => PayoffCard(
    heading: json['heading'] as String,
    caption: json['caption'] as String,
    spotMin: (json['spot_min'] as num).toDouble(),
    spotMax: (json['spot_max'] as num).toDouble(),
    currencySymbol: json['currency_symbol'] as String? ?? r'$',
    legs: <StrategyLeg>[
      for (final dynamic leg in json['legs'] as List<dynamic>)
        _legFromJson(leg as Map<String, dynamic>),
    ],
  );
}

StrategyLeg _legFromJson(Map<String, dynamic> json) {
  final String kind = json['kind'] as String;
  final String side = json['side'] as String;

  return StrategyLeg(
    kind: switch (kind) {
      'call' => LegKind.call,
      'put' => LegKind.put,
      'underlying' => LegKind.underlying,
      _ => throw FormatException('Unknown leg kind "$kind"'),
    },
    side: switch (side) {
      'long' => LegSide.long,
      'short' => LegSide.short,
      _ => throw FormatException('Unknown leg side "$side"'),
    },
    strike: (json['strike'] as num? ?? 0).toDouble(),
    premium: (json['premium'] as num? ?? 0).toDouble(),
    quantity: (json['quantity'] as num? ?? 1).toDouble(),
  );
}

/// A risk callout. Never decorative — CLAUDE.md rule 2 requires the downside
/// to be stated plainly in every options lesson, so this card carries weight.
class WarningCard extends LessonCard {
  const WarningCard({
    required this.heading,
    required this.body,
    this.points = const <String>[],
  });

  final String heading;
  final String body;
  final List<String> points;

  @override
  String get semanticLabel =>
      'Risk warning. ${<String>[heading, body, ...points].join('. ')}';

  factory WarningCard.fromJson(Map<String, dynamic> json) => WarningCard(
    heading: json['heading'] as String,
    body: json['body'] as String,
    points: <String>[
      for (final dynamic p in json['points'] as List<dynamic>? ?? <dynamic>[])
        p as String,
    ],
  );
}

/// Closing card: the two or three things worth remembering.
class SummaryCard extends LessonCard {
  const SummaryCard({required this.heading, required this.takeaways});

  final String heading;
  final List<String> takeaways;

  @override
  String get semanticLabel => '$heading. ${takeaways.join('. ')}';

  factory SummaryCard.fromJson(Map<String, dynamic> json) => SummaryCard(
    heading: json['heading'] as String,
    takeaways: <String>[
      for (final dynamic t in json['takeaways'] as List<dynamic>)
        t as String,
    ],
  );
}
