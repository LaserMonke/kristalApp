import 'package:flutter/material.dart';

/// Semantic colours for OptionsSchool.
///
/// Gain/loss colours are drawn from the Okabe–Ito colourblind-safe palette
/// (blue vs. vermillion) instead of the conventional red/green pair, which is
/// indistinguishable to ~8% of men with deuteranopia/protanopia. Per CLAUDE.md
/// colour is never the ONLY signal: P/L is always accompanied by a sign
/// (+/-) and, in charts, by line style or a labelled axis.
abstract final class AppColors {
  // Okabe–Ito base hues.
  static const Color blue = Color(0xFF0072B2); // gain
  static const Color skyBlue = Color(0xFF56B4E9); // gain, on dark
  static const Color vermillion = Color(0xFFD55E00); // loss
  static const Color orange = Color(0xFFE69F00); // loss, on dark / warning
  static const Color bluishGreen = Color(0xFF009E73); // confirm / correct
  static const Color reddishPurple = Color(0xFFCC79A7); // accent
  static const Color yellow = Color(0xFFF0E442); // highlight

  /// Terminal-style neutrals (dark).
  static const Color darkBackground = Color(0xFF0B0E13);
  static const Color darkSurface = Color(0xFF141920);
  static const Color darkSurfaceHigh = Color(0xFF1D242E);
  static const Color darkOutline = Color(0xFF2C3641);

  /// Terminal-style neutrals (light).
  static const Color lightBackground = Color(0xFFF6F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFEDEFF3);
  static const Color lightOutline = Color(0xFFD3D8E0);
}

/// Gain/loss colours resolved for the active brightness.
///
/// Exposed via [ThemeExtension] so widgets and the payoff `CustomPainter`
/// read the same values and light/dark stay in sync.
@immutable
class PnlColors extends ThemeExtension<PnlColors> {
  const PnlColors({
    required this.gain,
    required this.loss,
    required this.neutral,
    required this.correct,
    required this.incorrect,
  });

  /// Profit / positive change.
  final Color gain;

  /// Loss / negative change.
  final Color loss;

  /// Break-even, zero line, unfilled regions.
  final Color neutral;

  /// Q&A correct-answer feedback.
  final Color correct;

  /// Q&A incorrect-answer feedback.
  final Color incorrect;

  static const PnlColors light = PnlColors(
    gain: AppColors.blue,
    loss: AppColors.vermillion,
    neutral: Color(0xFF6B7280),
    correct: AppColors.bluishGreen,
    incorrect: AppColors.vermillion,
  );

  static const PnlColors dark = PnlColors(
    gain: AppColors.skyBlue,
    loss: AppColors.orange,
    neutral: Color(0xFF8A93A0),
    correct: AppColors.bluishGreen,
    incorrect: AppColors.orange,
  );

  @override
  PnlColors copyWith({
    Color? gain,
    Color? loss,
    Color? neutral,
    Color? correct,
    Color? incorrect,
  }) {
    return PnlColors(
      gain: gain ?? this.gain,
      loss: loss ?? this.loss,
      neutral: neutral ?? this.neutral,
      correct: correct ?? this.correct,
      incorrect: incorrect ?? this.incorrect,
    );
  }

  @override
  PnlColors lerp(ThemeExtension<PnlColors>? other, double t) {
    if (other is! PnlColors) return this;
    return PnlColors(
      gain: Color.lerp(gain, other.gain, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      correct: Color.lerp(correct, other.correct, t)!,
      incorrect: Color.lerp(incorrect, other.incorrect, t)!,
    );
  }
}

/// `Theme.of(context).pnl` — shorthand for the P/L colour set.
extension PnlColorsX on ThemeData {
  PnlColors get pnl => extension<PnlColors>() ?? PnlColors.light;
}
