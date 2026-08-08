import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/quiz.dart';

/// Renders one graded question and reports the verdict upward.
///
/// The switch is exhaustive over the sealed [QuizQuestion] hierarchy, so a new
/// question type forces a visual treatment to be written rather than silently
/// rendering nothing.
///
/// A question is answered ONCE. Unlike the ungraded quick-check inside a
/// lesson deck, the learner cannot cycle through options until one lights up
/// green — that would measure persistence, not understanding.
class QuizQuestionView extends StatelessWidget {
  const QuizQuestionView({
    required this.question,
    required this.verdict,
    required this.onAnswer,
    required this.answerController,
    required this.onSubmitAnswer,
    this.selectedChoice,
    super.key,
  });

  final QuizQuestion question;

  /// Null until answered, then whether it was right.
  final bool? verdict;

  /// The choice the learner already picked, for a multiple-choice question
  /// being restored from a bookmark. Which tile was tapped is not recoverable
  /// from [verdict] alone — several wrong answers can share a verdict — so a
  /// resumed run has to be told.
  final int? selectedChoice;

  final void Function({required bool correct, required int choiceIndex})
  onAnswer;

  /// Owned by the screen so the pinned footer button can read and submit it.
  /// A short-answer field must never depend on a button that scrolls with the
  /// content — the keyboard would cover it and the answer could not be sent.
  final TextEditingController answerController;

  final VoidCallback onSubmitAnswer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      container: true,
      label: question.semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (question.setup != null) ...<Widget>[
            _SetupPanel(text: question.setup!),
            const SizedBox(height: 16),
          ],
          Text(question.prompt, style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          switch (question) {
            final MultipleChoiceQuestion q => _MultipleChoiceView(
              question: q,
              verdict: verdict,
              initialSelection: selectedChoice,
              onAnswer: onAnswer,
            ),
            final NumericQuestion q => _NumericView(
              question: q,
              verdict: verdict,
              controller: answerController,
              onSubmit: onSubmitAnswer,
            ),
          },
          if (verdict != null && question.teachingNote != null) ...<Widget>[
            const SizedBox(height: 14),
            _TeachingNote(text: question.teachingNote!),
          ],
        ],
      ),
    );
  }
}

/// The given facts, set apart from the question so the learner can see at a
/// glance which numbers they have been handed.
class _SetupPanel extends StatelessWidget {
  const _SetupPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'THE SETUP',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

class _MultipleChoiceView extends StatefulWidget {
  const _MultipleChoiceView({
    required this.question,
    required this.verdict,
    required this.initialSelection,
    required this.onAnswer,
  });

  final MultipleChoiceQuestion question;
  final bool? verdict;

  /// The tile to start out selected, when this question is being restored.
  final int? initialSelection;

  final void Function({required bool correct, required int choiceIndex})
  onAnswer;

  @override
  State<_MultipleChoiceView> createState() => _MultipleChoiceViewState();
}

class _MultipleChoiceViewState extends State<_MultipleChoiceView> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    // A resumed question comes back with its answer already given. The tile is
    // still locked by the verdict, so this only restores what is shown.
    _selected = widget.initialSelection;
  }

  void _choose(int index) {
    // Both guards are needed. The parent's verdict only arrives on the next
    // rebuild, so two taps in the same frame would otherwise record the first
    // answer while the panel explained the second.
    if (_selected != null || widget.verdict != null) return;

    setState(() => _selected = index);
    widget.onAnswer(
      correct: widget.question.isCorrectChoice(index),
      choiceIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool answered = widget.verdict != null;
    final int? selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < widget.question.choices.length; i++)
          _ChoiceTile(
            choice: widget.question.choices[i],
            index: i,
            isSelected: selected == i,
            isRevealed: answered,
            onTap: () => _choose(i),
          ),
        if (answered && selected != null) ...<Widget>[
          const SizedBox(height: 6),
          _Verdict(
            correct: widget.question.isCorrectChoice(selected),
            explanation: widget.question.choices[selected].explanation,
            // Getting it wrong should still leave the learner knowing the
            // right answer and why, not just that they missed.
            correction: widget.question.isCorrectChoice(selected)
                ? null
                : 'The answer was "${widget.question.correctChoice.text}" — '
                      '${widget.question.correctChoice.explanation}',
          ),
        ] else ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Choose one. You get a single attempt at each question.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.index,
    required this.isSelected,
    required this.isRevealed,
    required this.onTap,
  });

  final QuizChoice choice;
  final int index;
  final bool isSelected;
  final bool isRevealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PnlColors pnl = theme.pnl;

    final bool markRight = isRevealed && choice.isCorrect;
    final bool markWrong = isRevealed && isSelected && !choice.isCorrect;

    final Color border = markRight
        ? pnl.correct
        : markWrong
        ? pnl.incorrect
        : (isSelected ? theme.colorScheme.primary : theme.colorScheme.outline);
    final Color fill = markRight
        ? pnl.correct.withValues(alpha: 0.12)
        : markWrong
        ? pnl.incorrect.withValues(alpha: 0.12)
        : Colors.transparent;

    // The verdict is carried by an icon and by the wording of the semantic
    // label as well as by colour (CLAUDE.md accessibility rule).
    final IconData? verdict = markRight
        ? Icons.check_circle
        : markWrong
        ? Icons.cancel
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: !isRevealed,
        selected: isSelected,
        excludeSemantics: true,
        label: isRevealed
            ? '${choice.text}. '
                  '${choice.isCorrect ? 'Correct answer' : 'Not correct'}'
            : choice.text,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isRevealed ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: border,
                  width: isSelected || markRight ? 1.8 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 24,
                    width: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      String.fromCharCode(65 + index),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      choice.text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                  if (verdict != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(verdict, size: 20, color: border),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Short answer: compute the number and type it in.
///
/// The field is here but the submit button is NOT — it lives in the screen's
/// pinned footer. On iOS the numeric keypad has no return key, so a submit
/// control that scrolls with the content ends up behind the keyboard with no
/// way to reach it, leaving a typed answer that cannot be sent.
class _NumericView extends StatefulWidget {
  const _NumericView({
    required this.question,
    required this.verdict,
    required this.controller,
    required this.onSubmit,
  });

  final NumericQuestion question;
  final bool? verdict;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  State<_NumericView> createState() => _NumericViewState();
}

class _NumericViewState extends State<_NumericView> {
  bool _hintShown = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumericQuestion question = widget.question;
    final bool answered = widget.verdict != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.controller,
          enabled: !answered,
          // Lands the learner in the field without a hunt, and raises the
          // keyboard while the question is still on screen above it.
          autofocus: !answered,
          autocorrect: false,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-, ]')),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onSubmit(),
          // Keeps room above the field when it is scrolled clear of the
          // keyboard, so the question stays readable while typing.
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            labelText: 'Your answer',
            hintText: '0',
            prefixText: question.unitPrefix.isEmpty
                ? null
                : question.unitPrefix,
            suffixText: question.unitSuffix.isEmpty
                ? null
                : question.unitSuffix,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (!answered) ...<Widget>[
          if (question.hint != null && !_hintShown)
            TextButton.icon(
              onPressed: () => setState(() => _hintShown = true),
              icon: const Icon(Icons.lightbulb_outline, size: 16),
              label: const Text('Show a hint'),
            ),
          if (_hintShown && question.hint != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question.hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ] else
          _Verdict(
            correct: widget.verdict!,
            explanation: question.explanation,
            correction: widget.verdict!
                ? null
                : 'The answer was ${question.formattedAnswer}.',
          ),
      ],
    );
  }
}

/// The right/wrong panel. Plain language, and the reasoning either way.
class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.correct,
    required this.explanation,
    this.correction,
  });

  final bool correct;
  final String explanation;

  /// What the answer should have been. Only set when the learner was wrong.
  final String? correction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = correct ? theme.pnl.correct : theme.pnl.incorrect;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: tone,
                ),
                const SizedBox(width: 8),
                Text(
                  correct ? 'Correct' : 'Not quite',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              explanation,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            if (correction != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                correction!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The point the question was really making — shown whether or not the learner
/// got it right, because a lucky guess deserves the reasoning too.
class _TeachingNote extends StatelessWidget {
  const _TeachingNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.push_pin_outlined,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
