import 'education_level.dart';

/// How the app is pitched for one learner, derived from their education level.
///
/// One place decides everything personalisation touches — path order, Q&A
/// difficulty, reminder wording — so the answer to "what does a high-schooler
/// see?" is a single readable table rather than scattered conditionals.
///
/// Two rules constrain this and are worth stating plainly:
///
/// Nothing is ever HIDDEN. Every learner can reach every lesson and every
/// question; the level only changes what is put in front of them first and
/// what is asked by default. Locking a sixteen-year-old out of the Heston
/// lesson would be patronising, and it would quietly change what the
/// completion certificate means.
///
/// Risk copy is never softened. The downside of an option does not depend on
/// who is reading (CLAUDE.md rule 2), so no level gets a gentler warning — a
/// beginner arguably needs it stated more plainly, not less.
class LearningProfile {
  const LearningProfile({
    required this.level,
    required this.depth,
    required this.usesAdvancedOrder,
    required this.asksStretchQuestions,
    required this.pitch,
    required this.reminderTitle,
    required this.reminderBody,
  });

  final EducationLevel level;

  /// How deep the material goes, 1 to 4.
  ///
  /// Cards and questions carry a depth range, so this genuinely changes what
  /// is on screen: a level-1 learner gets extra scaffolding cards and is
  /// spared the derivations, a level-4 learner gets the derivations and is
  /// spared the scaffolding. It is the difference between "the same lesson,
  /// reordered" and a lesson actually pitched at someone.
  ///
  /// The ladder puts postgraduate highest: an early-career learner has the
  /// numeracy but, by their own description, is new to derivatives, while a
  /// postgraduate has met the formal machinery. Nobody is capped — see
  /// [showsDeepDives] for what a learner can still choose to read.
  final int depth;

  /// Whether the deeper cards are shown inline. When false they are not
  /// deleted — the lesson player offers them behind a "Go deeper" control, so
  /// curiosity is never punished by the level someone ticked at sign-up.
  bool get showsDeepDives => depth >= 3;

  /// Whether the path follows each lesson's advanced ordering, which brings
  /// the exotics and stochastic-vol material forward instead of leaving it at
  /// the end.
  final bool usesAdvancedOrder;

  /// Whether the harder questions are included in the graded Q&A by default.
  /// When false they are still available — they are just not required to
  /// finish a lesson.
  final bool asksStretchQuestions;

  /// One line for the UI: how lessons are currently pitched.
  final String pitch;

  /// Reminder copy. Never a profit promise, never guilt (CLAUDE.md rules 3 & 9)
  /// — the wording changes register, not pressure.
  final String reminderTitle;
  final String reminderBody;

  static LearningProfile forLevel(EducationLevel level) => switch (level) {
    EducationLevel.highSchool => const LearningProfile(
      level: EducationLevel.highSchool,
      depth: 1,
      usesAdvancedOrder: false,
      asksStretchQuestions: false,
      pitch:
          'Pitched for high school: the foundations first, worked through '
          'slowly. The advanced lessons come last — they are open whenever '
          'you want them.',
      reminderTitle: 'Ready for a few cards?',
      reminderBody:
          'A lesson takes about five minutes. Go at your pace — this reminder '
          'turns off in Settings.',
    ),
    EducationLevel.undergraduate => const LearningProfile(
      level: EducationLevel.undergraduate,
      depth: 2,
      usesAdvancedOrder: false,
      asksStretchQuestions: true,
      pitch:
          'Pitched for undergraduates: the full path in order, including the '
          'harder Q&A questions.',
      reminderTitle: 'A few minutes of options study?',
      reminderBody:
          'One lesson card at a time. Your pace — this reminder is off '
          'anytime in Settings.',
    ),
    EducationLevel.postgraduate => const LearningProfile(
      level: EducationLevel.postgraduate,
      depth: 4,
      usesAdvancedOrder: true,
      asksStretchQuestions: true,
      pitch:
          'Pitched for postgraduates: the models and exotics come earlier, '
          'and every question is asked.',
      reminderTitle: 'Pick up where you left off?',
      reminderBody:
          'The next lesson is waiting. Turn this reminder off in Settings '
          'whenever it stops being useful.',
    ),
    EducationLevel.earlyCareer => const LearningProfile(
      level: EducationLevel.earlyCareer,
      depth: 3,
      usesAdvancedOrder: true,
      asksStretchQuestions: true,
      pitch:
          'Pitched for early career: straight to the pricing and strategy '
          'material, with every question asked.',
      reminderTitle: 'Ten minutes on derivatives?',
      reminderBody:
          'Short lessons that fit around a working day. Off in Settings '
          'whenever you like.',
    ),
    EducationLevel.other => const LearningProfile(
      level: EducationLevel.other,
      depth: 2,
      usesAdvancedOrder: false,
      asksStretchQuestions: true,
      pitch: 'The full path in order, with every question asked.',
      reminderTitle: 'A few minutes of options study?',
      reminderBody:
          'One lesson card at a time. Your pace — this reminder is off '
          'anytime in Settings.',
    ),
  };
}
