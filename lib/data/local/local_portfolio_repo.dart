import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/market.dart';
import '../repositories/portfolio_repo.dart';

/// The practice portfolio, stored on the device as JSON. A fresh install
/// starts with [Portfolio.fresh] — the default simulated cash, no positions.
class LocalPortfolioRepo implements PortfolioRepo {
  const LocalPortfolioRepo(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'practice_portfolio_v1';

  @override
  Future<Portfolio> load() async {
    final String? raw = _prefs.getString(_key);
    if (raw == null) return const Portfolio.fresh();
    try {
      return Portfolio.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A corrupt blob should not brick the tab; start clean.
      return const Portfolio.fresh();
    }
  }

  @override
  Future<void> save(Portfolio portfolio) async {
    await _prefs.setString(_key, jsonEncode(portfolio.toJson()));
  }
}
