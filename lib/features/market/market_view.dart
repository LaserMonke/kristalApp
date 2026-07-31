import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../data/models/market.dart';
import '../../providers/market_providers.dart';

/// The Phase 9 fake-money practice market (shares).
///
/// Every price here is either DELAYED real data (through the market-data-proxy
/// Edge Function) or the offline SYNTHETIC walk — the banner says which, and no
/// number is ever presented as a live, tradable quote (CLAUDE.md rules 4 & 8).
/// Fills are idealised: last price, no spread, no fees — stated plainly.
///
/// The whole tab is gated on [marketUnlockedProvider]. That is hard-wired open
/// while the paywall is a separate step (DEPLOY.md "Phase 9b"); when it lands,
/// only that provider changes.
class MarketView extends ConsumerWidget {
  const MarketView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This screen drives the live feed, so it is where the persisted
    // leaderboard bonus gets refreshed — keeping the board off the feed.
    ref.listen<int>(liveMarketBonusProvider, (int? _, int next) {
      ref.read(marketBonusPointsProvider.notifier).update(next);
    });

    if (!ref.watch(marketUnlockedProvider)) {
      return const _LockedPlaceholder();
    }

    final AsyncValue<List<Quote>> quotes = ref.watch(quotesProvider);
    final bool synthetic = ref.watch(feedIsSyntheticProvider);
    final Map<String, double> prices = ref.watch(pricesProvider);
    final AsyncValue<Portfolio> portfolio = ref.watch(
      portfolioControllerProvider,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        const DisclaimerBanner(),
        const SizedBox(height: 10),
        _FeedLabel(synthetic: synthetic),
        const SizedBox(height: 18),

        portfolio.when(
          loading: () => const _CardLoading(),
          error: (Object e, StackTrace _) =>
              const _Note('The practice portfolio could not be loaded.'),
          data: (Portfolio p) => _Summary(portfolio: p, prices: prices),
        ),
        const SizedBox(height: 20),

        portfolio.maybeWhen(
          data: (Portfolio p) => _Positions(portfolio: p, prices: prices),
          orElse: () => const SizedBox.shrink(),
        ),

        _SectionLabel('Watchlist'),
        const SizedBox(height: 8),
        quotes.when(
          loading: () => const _CardLoading(),
          error: (Object e, StackTrace _) =>
              const _Note('Prices are unavailable right now.'),
          data: (List<Quote> list) => Column(
            children: <Widget>[
              for (final Quote q in list)
                _QuoteRow(
                  quote: q,
                  onTap: () => _openTradeSheet(context, q),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: portfolio.maybeWhen(
            data: (Portfolio _) => TextButton.icon(
              onPressed: () => _confirmReset(context, ref),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset practice account'),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  void _openTradeSheet(BuildContext context, Quote quote) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => _TradeSheet(quote: quote),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reset practice account?'),
        content: const Text(
          'This clears your positions and returns the simulated cash to its '
          'starting amount. It affects nothing real.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(portfolioControllerProvider.notifier).reset();
    }
  }
}

/// Says whether the prices are delayed-real or offline-synthetic — required,
/// and it changes with the feed.
class _FeedLabel extends StatelessWidget {
  const _FeedLabel({required this.synthetic});

  final bool synthetic;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String text = synthetic
        ? 'Simulated prices (offline) — the server feed is unavailable, so '
              'these are made-up numbers for practice, not market data.'
        : 'Delayed market data — not live, and for learning only. Trades fill '
              'at the last price with no spread or fees.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          synthetic ? Icons.auto_graph : Icons.schedule,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.portfolio, required this.prices});

  final Portfolio portfolio;
  final Map<String, double> prices;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final double equity = portfolio.equity(prices, now);
    final double pnl = portfolio.totalReturn(prices, now);
    final Color pnlColor = pnl >= 0 ? theme.pnl.gain : theme.pnl.loss;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'PRACTICE ACCOUNT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _money(equity),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Icon(
                  pnl >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: pnlColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_money(pnl.abs())} total',
                  style: theme.textTheme.bodyMedium?.copyWith(color: pnlColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _MiniStat(label: 'Cash', value: _money(portfolio.cash)),
                _MiniStat(
                  label: 'Positions',
                  value: _money(equity - portfolio.cash),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _Positions extends StatelessWidget {
  const _Positions({required this.portfolio, required this.prices});

  final Portfolio portfolio;
  final Map<String, double> prices;

  @override
  Widget build(BuildContext context) {
    if (portfolio.holdings.isEmpty && portfolio.options.isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel('Your positions'),
        const SizedBox(height: 8),
        for (final Holding h in portfolio.holdings)
          Builder(
            builder: (BuildContext context) {
              final double price = prices[h.symbol] ?? h.avgCost;
              final double pnl = h.unrealised(price);
              final Color c = pnl >= 0 ? theme.pnl.gain : theme.pnl.loss;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(h.symbol, style: theme.textTheme.titleSmall),
                            Text(
                              '${h.shares} @ ${_money(h.avgCost)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            _money(h.marketValue(price)),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '${pnl >= 0 ? '+' : '-'}${_money(pnl.abs())}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: c,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        for (final OptionHolding o in portfolio.options)
          _OptionPositionCard(holding: o, spot: prices[o.symbol]),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// One option position, marked to the BSM model, with a tap-to-close action.
class _OptionPositionCard extends ConsumerWidget {
  const _OptionPositionCard({required this.holding, required this.spot});

  final OptionHolding holding;
  final double? spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double? mark = spot == null
        ? null
        : optionMarkPrice(holding, spot!, DateTime.now());
    final double value = mark == null
        ? holding.costBasis()
        : holding.marketValue(mark);
    final double pnl = mark == null ? 0 : holding.unrealised(mark);
    final Color c = pnl >= 0 ? theme.pnl.gain : theme.pnl.loss;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: mark == null
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (BuildContext _) =>
                    _SellOptionSheet(holding: holding, mark: mark),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(holding.label, style: theme.textTheme.titleSmall),
                    Text(
                      '${holding.contracts} contract'
                      '${holding.contracts == 1 ? '' : 's'} · '
                      'exp ${_shortDate(holding.expiry)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(_money(value), style: theme.textTheme.titleSmall),
                  Text(
                    '${pnl >= 0 ? '+' : '-'}${_money(pnl.abs())}',
                    style: theme.textTheme.labelSmall?.copyWith(color: c),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.onTap});

  final Quote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool up = quote.change >= 0;
    final Color c = up ? theme.pnl.gain : theme.pnl.loss;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(quote.symbol, style: theme.textTheme.titleSmall),
              ),
              Text(_money(quote.price), style: theme.textTheme.titleSmall),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Icon(
                      up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 18,
                      color: c,
                    ),
                    Text(
                      '${quote.percentChange.abs().toStringAsFixed(2)}%',
                      style: theme.textTheme.labelMedium?.copyWith(color: c),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buy/sell one symbol at its last price.
class _TradeSheet extends ConsumerStatefulWidget {
  const _TradeSheet({required this.quote});

  final Quote quote;

  @override
  ConsumerState<_TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<_TradeSheet> {
  bool _options = false;

  // Shares
  bool _buying = true;
  int _shares = 1;

  // Options — LONG only. The most a long option can lose is its premium, which
  // is the honest default here; no short/naked positions with open-ended loss
  // (CLAUDE.md rule 2). Closing existing positions happens from the holding.
  bool _isCall = true;
  int _strikeIndex = 2;
  int _expiryDays = 30;
  int _contracts = 1;

  String? _error;
  bool _working = false;

  double get _spot => widget.quote.price;

  List<double> get _strikes => <double>[
    for (final double f in <double>[0.9, 0.95, 1.0, 1.05, 1.1])
      (_spot * f).roundToDouble(),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${widget.quote.symbol}  ·  ${_money(_spot)}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Idealised fills — last price, one flat volatility, no spread or '
              'fees. Practice only.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Shares')),
                ButtonSegment<bool>(value: true, label: Text('Options')),
              ],
              selected: <bool>{_options},
              showSelectedIcon: false,
              onSelectionChanged: (Set<bool> s) => setState(() {
                _options = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_options) ..._optionControls(theme) else ..._shareControls(theme),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.pnl.loss,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _working ? null : _submit,
              child: Text(_buttonLabel()),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _shareControls(ThemeData theme) {
    return <Widget>[
      SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: true, label: Text('Buy')),
          ButtonSegment<bool>(value: false, label: Text('Sell')),
        ],
        selected: <bool>{_buying},
        showSelectedIcon: false,
        onSelectionChanged: (Set<bool> s) => setState(() {
          _buying = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 16),
      _Stepper(
        label: 'Shares',
        value: _shares,
        onDown: _shares > 1 ? () => setState(() => _shares--) : null,
        onUp: () => setState(() => _shares++),
      ),
      const SizedBox(height: 8),
      Text(
        '${_buying ? 'Cost' : 'Proceeds'}: ${_money(_shares * _spot)}',
        style: theme.textTheme.bodyMedium,
      ),
    ];
  }

  List<Widget> _optionControls(ThemeData theme) {
    final double premium = optionMarkPrice(_spec(), _spot, DateTime.now());
    final double cost = premium * _contracts * kContractMultiplier;

    return <Widget>[
      SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: true, label: Text('Call')),
          ButtonSegment<bool>(value: false, label: Text('Put')),
        ],
        selected: <bool>{_isCall},
        showSelectedIcon: false,
        onSelectionChanged: (Set<bool> s) => setState(() {
          _isCall = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 12),
      Text('Strike', style: theme.textTheme.labelMedium),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: <Widget>[
          for (int i = 0; i < _strikes.length; i++)
            ChoiceChip(
              label: Text(_money(_strikes[i])),
              selected: _strikeIndex == i,
              onSelected: (_) => setState(() {
                _strikeIndex = i;
                _error = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text('Expiry', style: theme.textTheme.labelMedium),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: const <ButtonSegment<int>>[
          ButtonSegment<int>(value: 30, label: Text('30d')),
          ButtonSegment<int>(value: 60, label: Text('60d')),
          ButtonSegment<int>(value: 90, label: Text('90d')),
        ],
        selected: <int>{_expiryDays},
        showSelectedIcon: false,
        onSelectionChanged: (Set<int> s) => setState(() {
          _expiryDays = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 12),
      _Stepper(
        label: 'Contracts',
        value: _contracts,
        onDown: _contracts > 1 ? () => setState(() => _contracts--) : null,
        onUp: () => setState(() => _contracts++),
      ),
      const SizedBox(height: 10),
      Text(
        'Model premium ${_money(premium)} / share · $kContractMultiplier '
        'shares per contract.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Text('Cost: ${_money(cost)}', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 6),
      Text(
        'Long options only — the most you can lose is the premium. Priced with '
        'one flat volatility, so treat it as illustrative.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    ];
  }

  OptionHolding _spec() => OptionHolding(
    symbol: widget.quote.symbol,
    isCall: _isCall,
    strike: _strikes[_strikeIndex],
    expiry: DateTime.now().add(Duration(days: _expiryDays)),
    contracts: _contracts,
    premiumPaid: 0,
  );

  String _buttonLabel() {
    if (_options) {
      return 'Buy $_contracts contract${_contracts == 1 ? '' : 's'}';
    }
    return _buying ? 'Buy $_shares' : 'Sell $_shares';
  }

  Future<void> _submit() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final PortfolioController c = ref.read(
      portfolioControllerProvider.notifier,
    );

    String? error;
    if (_options) {
      final OptionHolding spec = _spec();
      final double premium = optionMarkPrice(spec, _spot, DateTime.now());
      error = await c.buyOption(
        OptionHolding(
          symbol: spec.symbol,
          isCall: spec.isCall,
          strike: spec.strike,
          expiry: spec.expiry,
          contracts: spec.contracts,
          premiumPaid: premium,
        ),
      );
    } else {
      error = _buying
          ? await c.buy(widget.quote.symbol, _shares, _spot)
          : await c.sell(widget.quote.symbol, _shares, _spot);
    }

    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _working = false;
        _error = error;
      });
    }
  }
}

/// Close some or all of an option position at its current model mark.
class _SellOptionSheet extends ConsumerStatefulWidget {
  const _SellOptionSheet({required this.holding, required this.mark});

  final OptionHolding holding;
  final double mark;

  @override
  ConsumerState<_SellOptionSheet> createState() => _SellOptionSheetState();
}

class _SellOptionSheetState extends ConsumerState<_SellOptionSheet> {
  late int _contracts = widget.holding.contracts;
  String? _error;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double proceeds = widget.mark * _contracts * kContractMultiplier;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Close ${widget.holding.label}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Sell at the model mark of ${_money(widget.mark)} / share. '
            'Practice only.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _Stepper(
            label: 'Contracts',
            value: _contracts,
            onDown: _contracts > 1 ? () => setState(() => _contracts--) : null,
            onUp: _contracts < widget.holding.contracts
                ? () => setState(() => _contracts++)
                : null,
          ),
          const SizedBox(height: 8),
          Text('Proceeds: ${_money(proceeds)}', style: theme.textTheme.bodyMedium),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.pnl.loss),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _working ? null : _submit,
            child: Text('Sell $_contracts'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final String? error = await ref
        .read(portfolioControllerProvider.notifier)
        .sellOption(widget.holding.key, _contracts, widget.mark);

    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _working = false;
        _error = error;
      });
    }
  }
}

/// A labelled −/value/+ stepper, shared by the trade sheets.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
  });

  final String label;
  final int value;
  final VoidCallback? onDown;
  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: theme.textTheme.titleMedium),
        Row(
          children: <Widget>[
            IconButton.outlined(
              onPressed: onDown,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton.outlined(
              onPressed: onUp,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

String _shortDate(DateTime d) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

class _LockedPlaceholder extends StatelessWidget {
  const _LockedPlaceholder();

  @override
  Widget build(BuildContext context) {
    // Only shown once the paywall step (DEPLOY.md "Phase 9b") flips the
    // entitlement provider off for non-subscribers. Until then, unreachable.
    return const _Note('The practice market is a paid feature.');
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

String _money(double value) {
  final String sign = value < 0 ? '-' : '';
  final String digits = value.abs().toStringAsFixed(2);
  final int dot = digits.indexOf('.');
  final String whole = digits.substring(0, dot);
  final String frac = digits.substring(dot);
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '$sign\$$grouped$frac';
}
