import '../models/market.dart';

/// Persists the fake-money practice portfolio. Local for now (this is a
/// per-device learning sandbox); a Supabase-synced implementation could slot
/// in behind the same interface later, exactly like progress did.
abstract interface class PortfolioRepo {
  Future<Portfolio> load();
  Future<void> save(Portfolio portfolio);
}
