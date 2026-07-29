import '../../pricing/black_scholes.dart' show OptionType;
import '../../pricing/payoff.dart';
import 'quiz.dart';

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
    this.questions = const <QuizQuestion>[],
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

  /// The graded Q&A that follows the deck. Empty means this lesson has none,
  /// and the unlock gate falls back to "read the cards" on its own.
  final List<QuizQuestion> questions;

  /// Expert review trail required by CLAUDE.md ("reviewed by/date per lesson").
  /// Null means NOT yet reviewed by someone with real derivatives knowledge,
  /// and the UI says so rather than staying quiet about it.
  final String? reviewedBy;
  final DateTime? reviewedOn;

  bool get hasQuiz => questions.isNotEmpty;

  int get quizQuestionCount => questions.length;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawCards = json['cards'] as List<dynamic>? ?? <dynamic>[];
    final String? reviewedOn = json['reviewed_on'] as String?;

    return Lesson(
      id: json['id'] as String,
      order: json['order'] as int,
      title: json['title'] as String,
      summary: json['summary'] as String,
      estimatedMinutes: json['estimated_minutes'] as int? ?? 3,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedOn: reviewedOn == null ? null : DateTime.tryParse(reviewedOn),
      questions: <QuizQuestion>[
        for (final dynamic q
            in json['questions'] as List<dynamic>? ?? <dynamic>[])
          QuizQuestion.fromJson(q as Map<String, dynamic>),
      ],
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
      'explore' => ExploreCard.fromJson(json),
      'pricer_explore' => PricerExploreCard.fromJson(json),
      'choice' => ChoiceCard.fromJson(json),
      'compare' => CompareCard.fromJson(json),
      'equation' => EquationCard.fromJson(json),
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
  const TitleCard({
    required this.title,
    required this.subtitle,
    this.kicker,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String? kicker;

  /// Name from the fixed icon set in `lesson_icons.dart`. Decorative only —
  /// nothing is ever communicated by the icon alone.
  final String? icon;

  @override
  String get semanticLabel => '$title. $subtitle';

  factory TitleCard.fromJson(Map<String, dynamic> json) => TitleCard(
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    kicker: json['kicker'] as String?,
    icon: json['icon'] as String?,
  );
}

/// The workhorse: a short heading, a paragraph or two, optional bullets.
class TextCard extends LessonCard {
  const TextCard({
    required this.heading,
    required this.body,
    this.bullets = const <String>[],
    this.icon,
    this.highlight,
  });

  final String heading;
  final String body;
  final List<String> bullets;
  final String? icon;

  /// One line worth pulling out of the body and setting in a tinted panel —
  /// the sentence a learner should leave the card with.
  final String? highlight;

  @override
  String get semanticLabel => <String>[
    heading,
    body,
    ...bullets,
    ?highlight,
  ].join('. ');

  factory TextCard.fromJson(Map<String, dynamic> json) => TextCard(
    heading: json['heading'] as String,
    body: json['body'] as String,
    icon: json['icon'] as String?,
    highlight: json['highlight'] as String?,
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
    this.icon,
  });

  final String term;
  final String definition;
  final String? example;
  final String? icon;

  @override
  String get semanticLabel =>
      '$term. $definition${example == null ? '' : '. For example, $example'}';

  factory TermCard.fromJson(Map<String, dynamic> json) => TermCard(
    term: json['term'] as String,
    definition: json['definition'] as String,
    example: json['example'] as String?,
    icon: json['icon'] as String?,
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

/// A payoff diagram the learner drives.
///
/// Same maths as [PayoffCard], but the underlying price — and optionally the
/// strike and the premium — are on sliders, so the shape of the curve is
/// something the learner discovers rather than reads. Nothing here is a
/// forecast: it is the same idealised expiry arithmetic, evaluated live.
class ExploreCard extends LessonCard {
  const ExploreCard({
    required this.heading,
    required this.prompt,
    required this.legs,
    required this.spotMin,
    required this.spotMax,
    required this.spotStart,
    this.adjustStrike = false,
    this.adjustPremium = false,
    this.currencySymbol = r'$',
  });

  final String heading;
  final String prompt;

  /// The starting position. Slider changes are applied to the first option
  /// leg, so the learner edits a contract rather than an abstract curve.
  final List<StrategyLeg> legs;

  final double spotMin;
  final double spotMax;

  /// Where the price marker sits before the learner touches anything.
  final double spotStart;

  final bool adjustStrike;
  final bool adjustPremium;
  final String currencySymbol;

  @override
  String get semanticLabel =>
      'Interactive payoff explorer. $heading. $prompt Use the sliders to '
      'change the position; the profit or loss at expiry is read out below '
      'the chart.';

  factory ExploreCard.fromJson(Map<String, dynamic> json) => ExploreCard(
    heading: json['heading'] as String,
    prompt: json['prompt'] as String,
    spotMin: (json['spot_min'] as num).toDouble(),
    spotMax: (json['spot_max'] as num).toDouble(),
    spotStart: (json['spot_start'] as num).toDouble(),
    adjustStrike: json['adjust_strike'] as bool? ?? false,
    adjustPremium: json['adjust_premium'] as bool? ?? false,
    currencySymbol: json['currency_symbol'] as String? ?? r'$',
    legs: <StrategyLeg>[
      for (final dynamic leg in json['legs'] as List<dynamic>)
        _legFromJson(leg as Map<String, dynamic>),
    ],
  );
}

/// Which figure a [PricerExploreCard] puts in the spotlight.
///
/// The card always shows the full price and every Greek — this only decides
/// which tile is visually emphasised, so the lesson text and the number the
/// learner is watching agree with each other.
enum PricerGreek { price, delta, gamma, vega, theta, rho }

/// A live Black-Scholes-Merton quote the learner drives with sliders.
///
/// Unlike [ExploreCard] — which replays the *at-expiry* payoff arithmetic
/// from `lib/pricing/payoff.dart` — this card calls the pricing model itself
/// (`lib/pricing/black_scholes.dart`) with whatever inputs the learner has
/// set, live. It is how the Black-Scholes and Greeks lessons make an
/// otherwise abstract formula something a learner drags around and watches
/// react, rather than a wall of symbols to take on faith.
class PricerExploreCard extends LessonCard {
  const PricerExploreCard({
    required this.heading,
    required this.prompt,
    required this.optionType,
    required this.strike,
    required this.volatility,
    required this.timeToExpiry,
    required this.rate,
    required this.spotMin,
    required this.spotMax,
    required this.spotStart,
    this.focus = PricerGreek.price,
    this.adjustVolatility = false,
    this.adjustTimeToExpiry = false,
    this.currencySymbol = r'$',
  }) : assert(spotMax > spotMin, 'spotMax must exceed spotMin'),
       assert(strike > 0, 'strike must be positive'),
       assert(volatility > 0, 'volatility must be positive'),
       assert(timeToExpiry > 0, 'timeToExpiry must be positive');

  final String heading;
  final String prompt;
  final OptionType optionType;

  /// Fixed for this card — only the market inputs below move.
  final double strike;

  /// Starting volatility; itself draggable when [adjustVolatility] is true.
  final double volatility;

  /// Starting time to expiry, in years; draggable when [adjustTimeToExpiry].
  final double timeToExpiry;

  /// Risk-free rate. Fixed — Rho is covered, but with a slider on every
  /// card the learner would be juggling five at once.
  final double rate;

  final double spotMin;
  final double spotMax;
  final double spotStart;

  final PricerGreek focus;
  final bool adjustVolatility;
  final bool adjustTimeToExpiry;
  final String currencySymbol;

  @override
  String get semanticLabel =>
      'Interactive pricer. $heading. $prompt Drag the sliders to change the '
      'market inputs; the theoretical price and the Greeks are read out live.';

  factory PricerExploreCard.fromJson(Map<String, dynamic> json) =>
      PricerExploreCard(
        heading: json['heading'] as String,
        prompt: json['prompt'] as String,
        optionType: switch (json['option_type'] as String) {
          'call' => OptionType.call,
          'put' => OptionType.put,
          final String other =>
            throw FormatException('Unknown option type "$other"'),
        },
        strike: (json['strike'] as num).toDouble(),
        volatility: (json['volatility'] as num).toDouble(),
        timeToExpiry: (json['time_to_expiry'] as num).toDouble(),
        rate: (json['rate'] as num).toDouble(),
        spotMin: (json['spot_min'] as num).toDouble(),
        spotMax: (json['spot_max'] as num).toDouble(),
        spotStart: (json['spot_start'] as num).toDouble(),
        focus: switch (json['focus'] as String? ?? 'price') {
          'delta' => PricerGreek.delta,
          'gamma' => PricerGreek.gamma,
          'vega' => PricerGreek.vega,
          'theta' => PricerGreek.theta,
          'rho' => PricerGreek.rho,
          _ => PricerGreek.price,
        },
        adjustVolatility: json['adjust_volatility'] as bool? ?? false,
        adjustTimeToExpiry: json['adjust_time'] as bool? ?? false,
        currencySymbol: json['currency_symbol'] as String? ?? r'$',
      );
}

/// A tap-to-check question inside the reel.
///
/// Deliberately unscored — the graded Q&A is a separate engine. This is a
/// self-check that makes the learner commit to an answer before the
/// explanation appears, which is what makes the explanation stick.
class ChoiceCard extends LessonCard {
  const ChoiceCard({
    required this.question,
    required this.options,
    this.prompt,
  });

  final String question;

  /// Optional framing line above the question.
  final String? prompt;
  final List<ChoiceOption> options;

  @override
  String get semanticLabel =>
      'Quick check. $question. Options: '
      '${options.map((ChoiceOption o) => o.text).join('; ')}.';

  factory ChoiceCard.fromJson(Map<String, dynamic> json) => ChoiceCard(
    question: json['question'] as String,
    prompt: json['prompt'] as String?,
    options: <ChoiceOption>[
      for (final dynamic o in json['options'] as List<dynamic>)
        ChoiceOption.fromJson(o as Map<String, dynamic>),
    ],
  );
}

/// One answer, with the reason it is right or wrong.
///
/// Every option carries an explanation, including the wrong ones — a learner
/// who picks wrongly needs the reasoning more than one who picks correctly.
class ChoiceOption {
  const ChoiceOption({
    required this.text,
    required this.isCorrect,
    required this.explanation,
  });

  final String text;
  final bool isCorrect;
  final String explanation;

  factory ChoiceOption.fromJson(Map<String, dynamic> json) => ChoiceOption(
    text: json['text'] as String,
    isCorrect: json['correct'] as bool? ?? false,
    explanation: json['explanation'] as String,
  );
}

/// Two positions side by side.
///
/// Options are a two-sided contract, and most beginner confusion is really
/// confusion about which side is being described — so the sides get drawn
/// next to each other rather than on consecutive cards.
class CompareCard extends LessonCard {
  const CompareCard({
    required this.heading,
    required this.left,
    required this.right,
    this.footnote,
  });

  final String heading;
  final ComparePanel left;
  final ComparePanel right;
  final String? footnote;

  @override
  String get semanticLabel =>
      '$heading. ${left.semanticLabel} ${right.semanticLabel}'
      '${footnote == null ? '' : ' $footnote'}';

  factory CompareCard.fromJson(Map<String, dynamic> json) => CompareCard(
    heading: json['heading'] as String,
    footnote: json['footnote'] as String?,
    left: ComparePanel.fromJson(json['left'] as Map<String, dynamic>),
    right: ComparePanel.fromJson(json['right'] as Map<String, dynamic>),
  );
}

/// How a compare panel is tinted. Never the only signal — each panel is also
/// labelled and captioned (CLAUDE.md accessibility rule).
enum PanelTone { gain, loss, neutral }

class ComparePanel {
  const ComparePanel({
    required this.label,
    required this.tagline,
    required this.points,
    this.icon,
    this.tone = PanelTone.neutral,
  });

  final String label;
  final String tagline;
  final List<String> points;
  final String? icon;
  final PanelTone tone;

  String get semanticLabel => '$label: $tagline. ${points.join('. ')}.';

  factory ComparePanel.fromJson(Map<String, dynamic> json) => ComparePanel(
    label: json['label'] as String,
    tagline: json['tagline'] as String,
    icon: json['icon'] as String?,
    tone: switch (json['tone'] as String? ?? 'neutral') {
      'gain' => PanelTone.gain,
      'loss' => PanelTone.loss,
      _ => PanelTone.neutral,
    },
    points: <String>[
      for (final dynamic p in json['points'] as List<dynamic>? ?? <dynamic>[])
        p as String,
    ],
  );
}

/// A formula, broken into labelled pieces instead of one dense line.
///
/// Reads a raw equation like `C = S x N(d1) - K x e^(-rT) x N(d2)` and gives
/// each meaningful piece its own caption, so the shape of the formula and
/// what each part stands for land at the same time rather than the reader
/// having to hold the whole thing in their head first and decode it after.
class EquationCard extends LessonCard {
  const EquationCard({
    required this.heading,
    required this.terms,
    this.footnote,
  });

  final String heading;
  final List<EquationTerm> terms;

  /// The plain-English restatement of what the whole equation says.
  final String? footnote;

  @override
  String get semanticLabel =>
      '$heading. ${terms.map((EquationTerm t) => t.spoken).join(' ')}'
      '${footnote == null ? '' : ' $footnote'}';

  factory EquationCard.fromJson(Map<String, dynamic> json) => EquationCard(
    heading: json['heading'] as String,
    footnote: json['footnote'] as String?,
    terms: <EquationTerm>[
      for (final dynamic t in json['terms'] as List<dynamic>)
        EquationTerm.fromJson(t as Map<String, dynamic>),
    ],
  );
}

/// One piece of an [EquationCard].
///
/// A term with no [caption] renders as a plain connector (`=`, `x`, `-`) at
/// a smaller size; a term WITH a caption renders as a labelled tile, so the
/// reader's eye lands on the pieces that carry meaning.
class EquationTerm {
  const EquationTerm({required this.text, this.caption, this.tone = PanelTone.neutral});

  final String text;
  final String? caption;
  final PanelTone tone;

  /// Screen-reader phrasing: the symbol, and what it means if it has one.
  String get spoken => caption == null ? text : '$text — $caption.';

  factory EquationTerm.fromJson(Map<String, dynamic> json) => EquationTerm(
    text: json['text'] as String,
    caption: json['caption'] as String?,
    tone: switch (json['tone'] as String? ?? 'neutral') {
      'gain' => PanelTone.gain,
      'loss' => PanelTone.loss,
      _ => PanelTone.neutral,
    },
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
