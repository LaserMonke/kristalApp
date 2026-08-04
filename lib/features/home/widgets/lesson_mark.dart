import 'package:flutter/material.dart';

/// The glyph shown at the centre of the Home hero.
///
/// Either a Material icon or a piece of text, because the honest mark for some
/// lessons is a letter rather than a picture: the Greeks are Δ, volatility is
/// σ. Approximating those with a generic chart icon would say less.
@immutable
class LessonMark {
  const LessonMark.icon(this.icon, {required this.label})
    : glyph = null;

  const LessonMark.glyph(this.glyph, {required this.label}) : icon = null;

  final IconData? icon;
  final String? glyph;

  /// What the mark stands for, in words, for a screen reader. The mark itself
  /// is decoration — the lesson is named in the card directly below it
  /// (CLAUDE.md: nothing is communicated by an icon alone).
  final String label;
}

/// The app's own mark, shown before any lesson is under way and once the whole
/// path is finished.
const LessonMark kDefaultMark = LessonMark.icon(
  Icons.candlestick_chart_outlined,
  label: 'Stock Options Academy',
);

/// Lesson id → the mark that stands for it.
///
/// Keyed on id rather than title so renaming a lesson cannot silently drop it
/// back to the default. Named at compile time because icon fonts are tree-
/// shaken: an icon referenced only by a runtime string is stripped from the
/// release binary and renders as a blank box.
const Map<String, LessonMark> _marks = <String, LessonMark>{
  'what-is-an-option': LessonMark.icon(
    Icons.description_outlined,
    label: 'A contract',
  ),
  'payoff-at-expiry': LessonMark.icon(
    Icons.show_chart,
    label: 'A payoff diagram',
  ),
  'why-use-options': LessonMark.icon(
    Icons.balance_outlined,
    label: 'Weighing uses against risks',
  ),
  'black-scholes-price': LessonMark.icon(
    Icons.functions,
    label: 'A pricing formula',
  ),
  // The lesson is literally about Greek letters, so it gets one.
  'the-greeks': LessonMark.glyph('Δ', label: 'Delta, a Greek letter'),
  'options-strategies': LessonMark.icon(
    Icons.alt_route_outlined,
    label: 'Combining positions',
  ),
  'path-dependent-options': LessonMark.icon(
    Icons.timeline_outlined,
    label: 'A price path',
  ),
  // Sigma is how volatility is written everywhere in the material.
  'volatility-is-not-constant': LessonMark.glyph(
    'σ',
    label: 'Sigma, the symbol for volatility',
  ),
  'structured-products': LessonMark.icon(
    Icons.inventory_2_outlined,
    label: 'A wrapped product',
  ),
};

/// The mark for [lessonId], or the app's own when the lesson is unknown or
/// there is no lesson in progress.
LessonMark markForLesson(String? lessonId) =>
    _marks[lessonId] ?? kDefaultMark;

/// Every id the map covers — so a test can assert the bundled lessons all have
/// one, and that none refers to a lesson that no longer exists.
Iterable<String> get markedLessonIds => _marks.keys;

/// Draws a [LessonMark] inside a [size]-square box, whichever kind it is.
///
/// Both kinds occupy the same square so the wordmark underneath does not shift
/// as the mark changes from lesson to lesson.
class LessonMarkView extends StatelessWidget {
  const LessonMarkView({
    super.key,
    required this.mark,
    required this.size,
    this.color,
  });

  final LessonMark mark;
  final double size;

  /// Defaults to the primary colour, matching the rest of the hero.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? Theme.of(context).colorScheme.primary;

    // A letter's cap height falls well short of its font size, so a glyph set
    // to the icon's size would read noticeably smaller sitting beside one.
    // Just under the full box keeps the two optically level without letting
    // the line box spill past the square.
    final Widget symbol = mark.icon != null
        ? Icon(mark.icon, size: size, color: tint)
        : Text(
            mark.glyph!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.9,
              height: 1,
              fontWeight: FontWeight.w600,
              color: tint,
            ),
          );

    return Semantics(
      label: mark.label,
      // The glyph would otherwise be read out as the bare character 'Δ'.
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: symbol),
      ),
    );
  }
}
