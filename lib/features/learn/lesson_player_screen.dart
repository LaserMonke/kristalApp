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

  void _previous() {
    _controller?.previousPage(
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
          onGoDeeper: _deeper.isEmpty ? null : () => _showDeeper(context),
          deeperCount: _deeper.length,
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
              child: _ChainToDeck(
                onNext: _next,
                onPrevious: _previous,
                child: LessonCardView(card: lesson.cards[index]),
              ),
            ),
          ),
        ),
        _PlayerFooter(
          lesson: lesson,
          isLast: isLast,
          // The swipe hint is only worth its space on the very first card.
          showHint: _index == 0,
          onFinish: () => _finish(lesson),
        ),
      ],
    );
  }

  /// Cards written above this learner's level, kept out of the main deck but
  /// never taken away.
  ///
  /// A learner who ticked "high school" at sign-up is still allowed to be
  /// curious, and reading further must not cost them anything: these are not
  /// counted in progress and not required to finish.
  List<LessonCard> get _deeper {
    final Lesson? lesson = ref.read(lessonProvider(widget.lessonId)).value;
    if (lesson == null) return const <LessonCard>[];
    return lesson.deeperCards(ref.read(learningProfileProvider));
  }

  void _showDeeper(BuildContext context) {
    final List<LessonCard> cards = _deeper;
    if (cards.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (BuildContext _, ScrollController scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text(
              'Going deeper',
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Written for a more advanced level than the one you picked. '
              'Reading it changes nothing about your progress — it is here '
              'because you asked.',
              style: Theme.of(sheet).textTheme.bodySmall?.copyWith(
                color: Theme.of(sheet).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            for (final LessonCard card in cards) ...<Widget>[
              LessonCardView(card: card),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hands a drag that runs off the end of a long card back to the deck.
///
/// A card that overflows scrolls internally, and Flutter gives that inner
/// scrollable the whole vertical drag: the gesture arena picks the innermost
/// scrollable that will take it, and nested scrollables on the same axis do not
/// chain. So on a long card, swiping up scrolled the text and then simply
/// stopped at the bottom — the deck never saw the gesture, and reaching the
/// next card meant lifting off and starting a fresh swipe.
///
/// Overscroll is the signal that the finger is still going after the text has
/// run out. Accumulate it, and past a short threshold turn it into a page
/// change, so one continuous upward drag reads to the end of a card and then
/// carries on into the next one.
class _ChainToDeck extends StatefulWidget {
  const _ChainToDeck({
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  @override
  State<_ChainToDeck> createState() => _ChainToDeckState();
}

class _ChainToDeckState extends State<_ChainToDeck> {
  /// Drag accumulated past an edge. Positive is past the bottom of the card.
  double _beyond = 0;

  /// One page change per gesture. Without this a long pull would run through
  /// several cards at once.
  bool _turned = false;

  /// Far enough that a firm scroll to the bottom does not turn the page by
  /// itself, short enough that continuing the same drag obviously works.
  static const double _threshold = 42;

  bool _onNotification(Notification note) {
    if (note is ScrollStartNotification) {
      _beyond = 0;
      _turned = false;
    } else if (note is ScrollEndNotification) {
      _beyond = 0;
      _turned = false;
    } else if (note is OverscrollNotification && !_turned) {
      // Only a real finger counts. A fling that coasts into the end of the
      // card also reports overscroll, and turning the page on that would take
      // the card away from someone who was still reading it.
      if (note.dragDetails == null) return false;

      _beyond += note.overscroll;
      if (_beyond > _threshold) {
        _turned = true;
        widget.onNext();
      } else if (_beyond < -_threshold) {
        _turned = true;
        widget.onPrevious();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: widget.child,
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
    required this.onGoDeeper,
    required this.deeperCount,
  });

  final String title;
  final int cardCount;
  final int currentIndex;
  final VoidCallback onClose;

  /// Null when this lesson has nothing written above the learner's level.
  final VoidCallback? onGoDeeper;
  final int deeperCount;

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
              if (onGoDeeper != null)
                IconButton(
                  onPressed: onGoDeeper,
                  icon: const Icon(Icons.school_outlined),
                  tooltip:
                      'Go deeper — $deeperCount extra '
                      '${deeperCount == 1 ? 'card' : 'cards'} written for a '
                      'more advanced level',
                  visualDensity: VisualDensity.compact,
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
    required this.showHint,
    required this.onFinish,
  });

  final Lesson lesson;
  final bool isLast;

  /// Whether the "swipe up" hint should be visible. True only on the first
  /// card; once the learner moves on, it slides away.
  final bool showHint;

  final VoidCallback onFinish;

  static const Duration _duration = Duration(milliseconds: 300);
  static const Curve _curve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The finish card gets the call to action and the review note.
    if (isLast) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FilledButton(
              onPressed: onFinish,
              child: Text(
                lesson.hasQuiz
                    ? 'Start the Q&A · ${lesson.quizQuestionCount} questions'
                    : 'Finish lesson',
              ),
            ),
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
        ),
      );
    }

    // The swipe hint teaches the gesture once, on the first card. After that it
    // slides down out of view AND collapses its height (heightFactor → 0), so
    // every later card in the reel gets that strip of screen back.
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: showHint ? 1.0 : 0.0,
        duration: _duration,
        curve: _curve,
        child: AnimatedSlide(
          offset: showHint ? Offset.zero : const Offset(0, 1),
          duration: _duration,
          curve: _curve,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.swipe_up_alt_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Swipe up for the next card',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
