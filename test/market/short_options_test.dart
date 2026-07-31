import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/market.dart';

/// Writing options is the one place in the practice market where a learner can
/// lose more than they put in, so the arithmetic behind it gets pinned down
/// here: the sign convention, what a short marks at, and what collateral it
/// ties up.
void main() {
  final DateTime now = DateTime(2026, 1, 1);
  final DateTime expiry = DateTime(2026, 4, 1);

  OptionHolding written({int contracts = -1, double premium = 5}) =>
      OptionHolding(
        symbol: 'AAPL',
        isCall: true,
        strike: 100,
        expiry: expiry,
        contracts: contracts,
        premiumPaid: premium,
      );

  group('signed contracts', () {
    test('a negative count reads as short and reports its size unsigned', () {
      final OptionHolding h = written(contracts: -3);
      expect(h.isShort, isTrue);
      expect(h.size, 3);
      expect(written(contracts: 3).isShort, isFalse);
    });

    test('a written position is a liability, so it marks negative', () {
      // Wrote 1 contract; it is now worth $7/share to buy back.
      expect(written().marketValue(7), -700);
      expect(written(contracts: 2).marketValue(7), 1400);
    });

    test('a writer profits when the option cheapens', () {
      // Took in $5/share, now worth $2 — $300 of the credit is earned.
      expect(written(premium: 5).unrealised(2), 300);
      // And loses when it richens.
      expect(written(premium: 5).unrealised(9), -400);
    });

    test('the credit taken in shows as a negative basis', () {
      expect(written(premium: 5).costBasis(), -500);
    });
  });

  group('worst case', () {
    test('a written call has none to state', () {
      expect(written().hasUnboundedLoss, isTrue);
      expect(written().worstCaseLoss(), isNull);
    });

    test('a written put is worst at a spot of zero', () {
      final OptionHolding put = OptionHolding(
        symbol: 'AAPL',
        isCall: false,
        strike: 100,
        expiry: expiry,
        contracts: -1,
        premiumPaid: 4,
      );
      expect(put.hasUnboundedLoss, isFalse);
      // Obliged to buy at 100 something worth 0, having kept 4.
      expect(put.worstCaseLoss(), 9600);
    });

    test('a bought option cannot lose more than its premium', () {
      expect(written(contracts: 2, premium: 5).worstCaseLoss(), 1000);
    });
  });

  group('collateral', () {
    test('an at-the-money call takes 20% of spot plus the premium', () {
      final double m = shortMarginPerContract(
        isCall: true,
        spot: 100,
        strike: 100,
        premium: 5,
      );
      // 0.20 * 100 - 0 + 5 = 25 per share.
      expect(m, 2500);
    });

    test('being far out of the money reduces it to the floor', () {
      final double m = shortMarginPerContract(
        isCall: true,
        spot: 100,
        strike: 200,
        premium: 1,
      );
      // Standard: 20 - 100 + 1 is negative, so the 10%-of-spot floor holds.
      expect(m, (0.10 * 100 + 1) * kContractMultiplier);
    });

    test('a put floors on the strike, not the spot', () {
      final double m = shortMarginPerContract(
        isCall: false,
        spot: 200,
        strike: 100,
        premium: 1,
      );
      expect(m, (0.10 * 100 + 1) * kContractMultiplier);
    });

    test('it is never negative', () {
      expect(
        shortMarginPerContract(
          isCall: true,
          spot: 0.01,
          strike: 500,
          premium: 0,
        ),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('portfolio', () {
    test('collateral is held only against written positions', () {
      final Portfolio p = Portfolio(
        cash: 100000,
        holdings: const <Holding>[],
        options: <OptionHolding>[written(), written(contracts: 2)],
        startingCash: 100000,
      );
      final Map<String, double> prices = <String, double>{'AAPL': 100};

      final double held = p.marginHeld(prices, now);
      expect(held, greaterThan(0));
      // The long two contracts contribute nothing to the requirement.
      final Portfolio shortOnly = p.copyWith(
        options: <OptionHolding>[written()],
      );
      expect(shortOnly.marginHeld(prices, now), held);
    });

    test('buying power is cash less collateral', () {
      final Portfolio p = Portfolio(
        cash: 50000,
        holdings: const <Holding>[],
        options: <OptionHolding>[written()],
        startingCash: 50000,
      );
      final Map<String, double> prices = <String, double>{'AAPL': 100};
      expect(
        p.buyingPower(prices, now),
        50000 - p.marginHeld(prices, now),
      );
    });

    test('equity counts a written position against you', () {
      final Map<String, double> prices = <String, double>{'AAPL': 100};
      final Portfolio flat = Portfolio(
        cash: 100000,
        holdings: const <Holding>[],
        options: const <OptionHolding>[],
        startingCash: 100000,
      );
      final Portfolio short = flat.copyWith(
        options: <OptionHolding>[written()],
      );
      // Same cash, but now carrying an obligation, so equity is lower.
      expect(short.equity(prices, now), lessThan(flat.equity(prices, now)));
    });
  });
}
