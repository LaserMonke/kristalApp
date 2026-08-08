import 'package:flutter/material.dart';

/// "You were here last time" — a one-line explanation for a lesson deck or a
/// Q&A that did not open at the beginning.
///
/// Shown inline rather than as a snackbar on purpose: it belongs to the card or
/// question the learner landed on, so it should leave when they move on, not on
/// a timer. Opening on card five with no word about why reads as a bug.
class ResumeNote extends StatelessWidget {
  const ResumeNote({
    required this.visible,
    this.text = 'Picked up where you left off',
    super.key,
  });

  final bool visible;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The note leaves the tree rather than merely collapsing, so a screen
    // reader stops announcing it the moment it stops being true; AnimatedSize
    // gives the strip of screen back smoothly on the way out.
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.bookmark_outline,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
