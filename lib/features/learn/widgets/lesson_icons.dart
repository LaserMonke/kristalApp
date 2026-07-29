import 'package:flutter/material.dart';

/// The icons a lesson author may name in JSON.
///
/// A fixed set rather than free-form icon codepoints: icon fonts are tree-
/// shaken at build time, so an icon referenced only by a runtime string would
/// be stripped from the release binary and render as a blank box. Unknown or
/// missing names fall back to [_fallback] instead of throwing — a typo in
/// content should never crash a lesson.
///
/// Icons are decorative. Per CLAUDE.md nothing is ever communicated by an icon
/// alone; every card that carries one also states the same thing in words.
const Map<String, IconData> _lessonIcons = <String, IconData>{
  'contract': Icons.description_outlined,
  'handshake': Icons.handshake_outlined,
  'call': Icons.trending_up,
  'put': Icons.trending_down,
  'clock': Icons.schedule_outlined,
  'calendar': Icons.event_outlined,
  'scale': Icons.balance_outlined,
  'shield': Icons.shield_outlined,
  'umbrella': Icons.umbrella_outlined,
  'chart': Icons.show_chart,
  'compass': Icons.explore_outlined,
  'coins': Icons.savings_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'question': Icons.help_outline,
  'lightbulb': Icons.lightbulb_outline,
  'warning': Icons.report_problem_outlined,
  'buyer': Icons.person_outline,
  'seller': Icons.storefront_outlined,
  'split': Icons.call_split,
  'target': Icons.adjust,
  'lock': Icons.lock_outline,
  'flag': Icons.flag_outlined,
  'school': Icons.school_outlined,
  'formula': Icons.calculate_outlined,
  'insights': Icons.insights_outlined,
  'waves': Icons.waves_outlined,
  'strategy': Icons.alt_route_outlined,
};

const IconData _fallback = Icons.circle_outlined;

/// Resolves a JSON icon name, or null when the author named none.
IconData? lessonIcon(String? name) {
  if (name == null) return null;
  return _lessonIcons[name] ?? _fallback;
}

/// Every name the content may use — exposed so a test can assert the JSON
/// never references an icon that does not exist.
Iterable<String> get knownLessonIconNames => _lessonIcons.keys;
