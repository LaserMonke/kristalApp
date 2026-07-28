import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/lesson.dart';
import '../../data/models/lesson_progress.dart';
import '../../providers/lesson_providers.dart';
import '../../providers/progress_controller.dart';
import 'widgets/lesson_card_view.dart';

/// The card/reel player: one lesson, one vertically swipeable deck.
///
/// Full screen (no bottom tab bar) so a card gets the whole viewport, which is
/// what keeps the reel format readable on a phone.
class LessonPlayerScreen extends ConsumerStatefulWidget {
  const LessonPlayerScreen({required this.lessonId, super.key});

  final String lessonId;

  @override
  ConsumerState<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends ConsumerState<LessonPlayerScreen> {
  PageController? _controller;
  int _index = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Resumes where the learner left off, so a half-read lesson isn't restarted
  /// from card one. Read once, when the deck first becomes available.
  void _ensureController(Lesson lesson) {
    if (_controller != null) return;

    final LessonProgress? saved = ref
        .read(progressControllerProvider)
        .value?[lesson.id];
    final int resume = saved == null || saved.lessonCompleted
        ? 0
        : saved.cardsViewed.clamp(0, lesson.cards.length - 1);

    _index = resume;
    _controller = PageController(initialPage: resume);
  }

  void _onPageChanged(Lesson lesson, int index) {
    setState(() => _index = index);
    ref
        .read(progressControllerProvider.notifier)
        .recordCardViewed(lessonId: lesson.id, cardIndex: index);
  }

  void _next() {
    _controller?.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish(Lesson lesson) async {
    await ref
        .read(progressControllerProvider.notifier)
        .markLessonCompleted(
          lessonId: lesson.id,
          totalCards: lesson.cards.length,
        );
    if (!mounted) return;

    // Reading the cards is not the end of a lesson that has questions — the
    // Q&A is, and it is what opens the next lesson. Replacing the player
    // rather than stacking on top of it means leaving the Q&A returns to the
    // path, not to the last card of a deck already finished.
    if (lesson.hasQuiz) {
      context.pushReplacement(Routes.quizPath(lesson.id));
      return;
    }
    _close();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.learn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Lesson?> lesson = ref.watch(
      lessonProvider(widget.lessonId),
    );

    return Scaffold(
      body: SafeArea(
        child: lesson.when(
          loading: () => const Center(
            child: SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
          error: (Object error, StackTrace _) => _LoadFailure(onClose: _close),
          data: (Lesson? data) {
            if (data == null || data.cards.isEmpty) {
              return _LoadFailure(onClose: _close);
            }
            _ensureController(data);
            return _buildPlayer(context, data);
          },
        ),
      ),
    );
  }

  Widget _buildPlayer(BuildContext context, Lesson lesson) {
    final bool isLast = _index == lesson.cards.length - 1;

    return Column(
      children: <Widget>[
        _PlayerHeader(
          title: lesson.title,
          cardCount: lesson.cards.length,
          currentIndex: _index,
          onClose: _close,
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            scrollDirection: Axis.vertical,
            itemCount: lesson.cards.length,
            onPageChanged: (int index) => _onPageChanged(lesson, index),
            itemBuilder: (BuildContext context, int index) => _DeckCard(
              controller: _controller!,
              index: index,
              child: LessonCardView(card: lesson.cards[index]),
            ),
          ),
        ),
        _PlayerFooter(
          lesson: lesson,
          isLast: isLast,
          onNext: _next,
          onFinish: () => _finish(lesson),
        ),
      ],
    );
  }
}

/// The deck effect: as a card is swiped away it shrinks, tilts and fades, and
/// the incoming card grows into place — so a swipe reads as "the top card
/// leaves the pile", not "the page scrolled".
///
/// Driven directly by the [PageController]'s scroll position, which means the
/// motion tracks the learner's finger exactly (and reverses cleanly when a
/// swipe is abandoned) instead of playing a canned clip.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        // How far this card is from being front-of-deck, in pages.
        // 0 = on top; -1 = one swipe above (leaving); 1 = next in the pile.
        double delta = 0;
        if (controller.hasClients && controller.position.haveDimensions) {
          delta = (controller.page ?? controller.initialPage.toDouble()) - index;
        }
        final double t = delta.clamp(-1.0, 1.0).abs();

        final double scale;
        final double opacity;
        double tilt = 0;

        if (delta > 0) {
          // Leaving: shrink, tilt off-axis and fade as it slides off the top.
          scale = 1 - 0.10 * t;
          opacity = (1 - 0.9 * t).clamp(0.0, 1.0);
          tilt = -0.05 * t;
        } else {
          // Arriving from below: grow from slightly behind the deck.
          scale = 0.94 + 0.06 * (1 - t);
          opacity = (1 - 0.35 * t).clamp(0.0, 1.0);
        }

        return Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.title,
    required this.cardCount,
    required this.currentIndex,
    required this.onClose,
  });

  final String title;
  final int cardCount;
  final int currentIndex;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                tooltip: 'Leave lesson',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${currentIndex + 1}/$cardCount',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Segmented bar: shows how long the deck is, not just how far in.
          Semantics(
            label: 'Card ${currentIndex + 1} of $cardCount',
            child: Row(
              children: <Widget>[
                for (int i = 0; i < cardCount; i++)
                  Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: i == cardCount - 1 ? 0 : 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= currentIndex
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerFooter extends StatelessWidget {
  const _PlayerFooter({
    required this.lesson,
    required this.isLast,
    required this.onNext,
    required this.onFinish,
  });

  final Lesson lesson;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!isLast)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.swipe_up_alt_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Swipe up, or use the button',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: isLast ? onFinish : onNext,
            child: Text(
              !isLast
                  ? 'Next'
                  : lesson.hasQuiz
                  ? 'Start the Q&A · ${lesson.quizQuestionCount} questions'
                  : 'Finish lesson',
            ),
          ),
          if (isLast) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              lesson.reviewedBy == null
                  ? 'This lesson has not yet been reviewed by a derivatives '
                        'practitioner. Educational only — not financial advice.'
                  : 'Reviewed by ${lesson.reviewedBy}. Educational only — not '
                        'financial advice.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'That lesson could not be loaded.',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onClose, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
