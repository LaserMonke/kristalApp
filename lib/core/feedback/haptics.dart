import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feedback_settings.dart';

/// Vibration for the handful of moments that deserve one.
///
/// Deliberately a small vocabulary. A tick for a confirmed action, a firmer
/// one for a result worth noticing, a double for something that needs care —
/// writing an option, resetting an account. Anything more and the phone
/// becomes noise, which is its own kind of dark pattern.
///
/// Every call is silent when the learner has haptics off, and every call
/// swallows platform errors: a device with no vibrator, or a test with no
/// plugin, must never take the app down over feedback.
class Haptics {
  const Haptics(this._enabled);

  final bool _enabled;

  /// A confirmed action: a trade filled, a symbol added.
  Future<void> tick() => _run(HapticFeedback.selectionClick);

  /// A result worth noticing: an answer marked, a level reached.
  Future<void> impact() => _run(HapticFeedback.mediumImpact);

  /// Something consequential enough to feel twice: writing an option,
  /// clearing an account.
  Future<void> warn() async {
    await _run(HapticFeedback.heavyImpact);
    if (!_enabled) return;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _run(HapticFeedback.mediumImpact);
  }

  Future<void> _run(Future<void> Function() effect) async {
    if (!_enabled) return;
    try {
      await effect();
    } catch (_) {
      // No vibrator, or no platform channel. Feedback is never load-bearing.
    }
  }
}

final Provider<Haptics> hapticsProvider = Provider<Haptics>(
  (Ref ref) => Haptics(ref.watch(hapticsEnabledProvider)),
);
