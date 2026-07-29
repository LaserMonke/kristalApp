import 'package:flutter/material.dart';

/// Badge glyphs for the level ladder (see lib/engagement/levels.dart).
///
/// Same rationale as the lesson icon map: icon fonts are tree-shaken at build
/// time, so glyphs must be named at compile time in one fixed map. An unknown
/// name falls back to a neutral badge rather than crashing.
const Map<String, IconData> _badgeIcons = <String, IconData>{
  'seedling': Icons.spa_outlined,
  'eye': Icons.visibility_outlined,
  'book': Icons.menu_book_outlined,
  'chart': Icons.query_stats,
  'strategy': Icons.account_tree_outlined,
  'shield': Icons.shield_outlined,
  'medal': Icons.workspace_premium_outlined,
};

const IconData _fallback = Icons.military_tech_outlined;

IconData levelBadgeIcon(String name) => _badgeIcons[name] ?? _fallback;

/// For the test that pins level definitions to glyphs that actually exist.
Iterable<String> get knownBadgeIconNames => _badgeIcons.keys;
