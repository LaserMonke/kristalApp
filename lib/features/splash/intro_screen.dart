import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/feedback_settings.dart';

/// True once the opening sequence has finished (or been skipped).
///
/// The router holds on the intro until this flips, so the app never cuts the
/// animation off halfway. It lives for the life of the process, so the intro
/// plays once per launch and never again on a later redirect.
class IntroController extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() {
    if (!state) state = true;
  }
}

final NotifierProvider<IntroController, bool> introCompleteProvider =
    NotifierProvider<IntroController, bool>(IntroController.new);

/// The opening screen: the mark draws itself in over a held chime, then hands
/// over to the app.
///
/// Two rules it has to respect. It is skippable — a tap anywhere ends it —
/// because nobody should be made to sit through branding, and it must not be
/// the only way anything is communicated, so it says nothing the app does not
/// say again elsewhere.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  /// Long enough to register, short enough not to be in the way.
  static const Duration _hold = Duration(milliseconds: 1750);

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: IntroScreen._hold,
  );
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(_finish);
    _play();
  }

  Future<void> _play() async {
    if (!ref.read(introSoundEnabledProvider)) return;
    try {
      final AudioPlayer player = AudioPlayer();
      _player = player;
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(AssetSource('audio/intro_chime.wav'), volume: 0.7);
    } catch (_) {
      // No audio device, no plugin, or the file would not decode. The intro
      // is decoration; it must never block the app from opening.
    }
  }

  void _finish() {
    if (!mounted) return;
    ref.read(introCompleteProvider.notifier).complete();
  }

  void _skip() {
    _controller.stop();
    _player?.stop().catchError((_) {});
    _finish();
  }

  @override
  void dispose() {
    _controller.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The mark settles first, the wordmark follows it in.
    final Animation<double> markIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
    );
    final Animation<double> textIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
    );
    final Animation<double> ringIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.95, curve: Curves.easeInOut),
    );

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Semantics(
          label: 'Stock Options Academy is opening.',
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 148,
                    height: 148,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: ringIn.value,
                            strokeWidth: 4,
                            strokeCap: StrokeCap.round,
                            backgroundColor: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        Opacity(
                          opacity: markIn.value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.7 + 0.3 * markIn.value.clamp(0.0, 1.0),
                            child: Icon(
                              Icons.candlestick_chart_outlined,
                              size: 62,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: textIn.value.clamp(0.0, 1.0),
                    child: Padding(
                      // The wordmark is long enough to reach the screen edge on
                      // a narrow phone; pad so it wraps cleanly instead.
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Stock Options Academy',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: (textIn.value * 0.75).clamp(0.0, 1.0),
                    child: Text(
                      'Learn how options work',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
