import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../data/models/market.dart';
import '../../providers/market_providers.dart';
import '../../providers/repository_providers.dart';

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
    // This screen is the only place with live prices, so it is where the
    // trading week starts and where it settles. Points land at most once a
    // week; the rest of the app just reads the total.
    ref.listen<AsyncValue<Portfolio>>(portfolioControllerProvider, (
      AsyncValue<Portfolio>? _,
      AsyncValue<Portfolio> next,
    ) {
      final Portfolio? p = next.value;
      if (p != null) _reconcile(context, ref, p);
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

    // Also settle on the first build, not only when the portfolio changes —
    // otherwise a learner who opens the tab and trades nothing never starts
    // (or closes) a week.
    final Portfolio? loaded = portfolio.value;
    if (loaded != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _reconcile(context, ref, loaded);
      });
    }

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

        const _SymbolSearch(),
        const SizedBox(height: 18),

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
                  onRemove: () =>
                      ref.read(watchlistProvider.notifier).remove(q.symbol),
                ),
              if (list.isEmpty)
                const _Note(
                  'Nothing on your watchlist. Search above to add a symbol.',
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

  /// Starts the trading week, or settles it if a week has passed, telling the
  /// learner plainly what they earned. A losing week settles too — it just
  /// earns nothing, and says so rather than staying silent.
  Future<void> _reconcile(
    BuildContext context,
    WidgetRef ref,
    Portfolio portfolio,
  ) async {
    final Map<String, double> prices = ref.read(pricesProvider);
    // No prices yet means no honest way to value the week.
    if (prices.isEmpty) return;

    final double equity = portfolio.equity(prices, DateTime.now());
    final int? earned = await ref
        .read(marketSettlementProvider.notifier)
        .reconcile(equity, DateTime.now());
    if (earned == null || !context.mounted) return;

    await ref.read(hapticsProvider).impact();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          earned > 0
              ? 'Your practice week settled: $earned points from simulated '
                    'gains. A new week starts now.'
              : 'Your practice week settled flat or down, so no points this '
                    'time. Nothing was taken away. A new week starts now.',
        ),
        duration: const Duration(seconds: 6),
      ),
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
      await ref.read(hapticsProvider).warn();
      await ref.read(portfolioControllerProvider.notifier).reset();
      // A fresh account must not settle against a week it never traded.
      await ref.read(marketSettlementProvider.notifier).clear();
    }
  }
}

/// Search any ticker and trade it.
///
/// The watchlist is a starting point, not a boundary: whatever the learner
/// finds here gets added to it and priced like anything else. Lookups are
/// debounced because each one costs a call against the paid data plan.
class _SymbolSearch extends ConsumerStatefulWidget {
  const _SymbolSearch();

  @override
  ConsumerState<_SymbolSearch> createState() => _SymbolSearchState();
}

class _SymbolSearchState extends ConsumerState<_SymbolSearch> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _opening = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    FocusScope.of(context).unfocus();
  }

  /// Adds the symbol to the watchlist, then opens its ticket. The quote is
  /// fetched directly rather than waiting for the next poll, so the sheet has
  /// a price to trade at straight away.
  Future<void> _open(String symbol) async {
    if (_opening) return;
    setState(() => _opening = true);
    FocusScope.of(context).unfocus();

    final String? failed = await ref
        .read(watchlistProvider.notifier)
        .add(symbol);
    if (!mounted) return;
    if (failed != null) {
      setState(() => _opening = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failed)));
      return;
    }

    final List<Quote> found = await ref
        .read(marketRepoProvider)
        .quotes(<String>[symbol]);
    if (!mounted) return;
    setState(() => _opening = false);

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No price came back for $symbol. It is on your watchlist — try '
            'again in a moment.',
          ),
        ),
      );
      return;
    }

    _clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => _TradeSheet(quote: found.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<SymbolMatch>> results = _query.isEmpty
        ? const AsyncValue<List<SymbolMatch>>.data(<SymbolMatch>[])
        : ref.watch(symbolSearchProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.search,
          onSubmitted: (String v) {
            if (v.trim().isNotEmpty) _open(v.trim().toUpperCase());
          },
          decoration: InputDecoration(
            hintText: 'Search by name or ticker — Apple, Coca-Cola, NVDA…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty && _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear search',
                    onPressed: _clear,
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (_query.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
            error: (Object e, StackTrace _) =>
                const _Note('Symbol search is unavailable right now.'),
            data: (List<SymbolMatch> matches) => matches.isEmpty
                ? const _Note('No symbols match that.')
                : Column(
                    children: <Widget>[
                      for (final SymbolMatch m in matches)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              m.symbol,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: m.description.isEmpty
                                ? null
                                : Text(
                                    m.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: _opening
                                ? null
                                : const Icon(Icons.add_chart, size: 20),
                            onTap: _opening ? null : () => _open(m.symbol),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
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

class _Summary extends ConsumerWidget {
  const _Summary({required this.portfolio, required this.prices});

  final Portfolio portfolio;
  final Map<String, double> prices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final double equity = portfolio.equity(prices, now);
    final double pnl = portfolio.totalReturn(prices, now);
    final Color pnlColor = pnl >= 0 ? theme.pnl.gain : theme.pnl.loss;
    final double margin = portfolio.marginHeld(prices, now);

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
                // Only worth the space once something is written — otherwise
                // collateral is always zero and buying power is just cash.
                if (margin > 0)
                  _MiniStat(label: 'Collateral', value: _money(margin)),
              ],
            ),
            if (margin > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Buying power ${_money(portfolio.buyingPower(prices, now))} — '
                'collateral is held against your written options and cannot be '
                'spent until you close them.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const _WeekInProgress(),
          ],
        ),
      ),
    );
  }
}

/// The trading week: what it has made so far, what that would pay, and when it
/// settles.
///
/// Stated rather than hinted at, because points arriving out of nowhere a week
/// later would be mystifying — and because a week that is down should say so
/// plainly instead of quietly showing nothing (CLAUDE.md rule 9).
class _WeekInProgress extends ConsumerWidget {
  const _WeekInProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ({double gain, int points, Duration left, bool started}) week = ref
        .watch(weekInProgressProvider);

    if (!week.started) {
      return Text(
        'Your first practice week starts as soon as prices load. Every seven '
        'days, a week that finished up earns points — one per '
        '\$${kDollarsPerPoint.toStringAsFixed(0)} of simulated gain, up to '
        '$kMaxWeeklyPoints.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      );
    }

    final bool up = week.gain > 0;
    final Color c = up ? theme.pnl.gain : theme.colorScheme.onSurfaceVariant;
    final int days = week.left.inDays;
    final int hours = week.left.inHours % 24;
    final String when = week.left == Duration.zero
        ? 'settling now'
        : days > 0
        ? 'settles in $days ${days == 1 ? 'day' : 'days'}'
        : 'settles in $hours ${hours == 1 ? 'hour' : 'hours'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.event_repeat_outlined, size: 16, color: c),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'This week ${up ? '+' : ''}${_money(week.gain)} · $when',
                style: theme.textTheme.labelLarge?.copyWith(color: c),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          week.points > 0
              ? 'Worth ${week.points} '
                    '${week.points == 1 ? 'point' : 'points'} if the week ended '
                    'now. Only the settled figure counts, and it can still '
                    'change.'
              : 'No points from the market this week unless it finishes up. A '
                    'down week never costs you points.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
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
                    Row(
                      children: <Widget>[
                        Text(holding.label, style: theme.textTheme.titleSmall),
                        if (holding.isShort) ...<Widget>[
                          const SizedBox(width: 6),
                          _ShortBadge(unbounded: holding.hasUnboundedLoss),
                        ],
                      ],
                    ),
                    Text(
                      '${holding.isShort ? 'Wrote' : 'Long'} ${holding.size} '
                      'contract${holding.size == 1 ? '' : 's'} · '
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

/// Marks a written position in the list. Not colour alone — the word "SHORT"
/// carries it, so it still reads for a colourblind learner (CLAUDE.md
/// accessibility).
class _ShortBadge extends StatelessWidget {
  const _ShortBadge({required this.unbounded});

  final bool unbounded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.pnl.loss.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.pnl.loss.withValues(alpha: 0.5)),
      ),
      child: Text(
        unbounded ? 'SHORT · NO CAP' : 'SHORT',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.pnl.loss,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    required this.quote,
    required this.onTap,
    required this.onRemove,
  });

  final Quote quote;
  final VoidCallback onTap;
  final VoidCallback onRemove;

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
        // Long-press to stop following. Positions are unaffected — anything
        // held stays priced whether or not it is on the list.
        onLongPress: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheet) => SafeArea(
            child: ListTile(
              leading: const Icon(Icons.playlist_remove),
              title: Text('Remove ${quote.symbol} from watchlist'),
              subtitle: const Text('Any position you hold keeps its price.'),
              onTap: () {
                Navigator.pop(sheet);
                onRemove();
              },
            ),
          ),
        ),
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

  // Options. Buying is the default and stays the default: the most a long
  // option can lose is its premium. Writing is available but never the
  // pre-selected choice, and the sheet states the downside in full before the
  // button can be pressed (CLAUDE.md rule 2).
  bool _writing = false;
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
    final double consideration = premium * _contracts * kContractMultiplier;
    final double collateral = _writing
        ? shortMarginPerContract(
                isCall: _isCall,
                spot: _spot,
                strike: _strikes[_strikeIndex],
                premium: premium,
              ) *
              _contracts
        : 0;

    return <Widget>[
      SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: false, label: Text('Buy')),
          ButtonSegment<bool>(value: true, label: Text('Write')),
        ],
        selected: <bool>{_writing},
        showSelectedIcon: false,
        onSelectionChanged: (Set<bool> s) => setState(() {
          _writing = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 16),
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
      Text(
        _writing
            ? 'Premium received: ${_money(consideration)}'
            : 'Cost: ${_money(consideration)}',
        style: theme.textTheme.bodyMedium,
      ),
      if (_writing) ...<Widget>[
        const SizedBox(height: 2),
        Text(
          'Collateral held: ${_money(collateral)}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: 10),
      if (_writing)
        _WriteRiskNote(isCall: _isCall, strike: _strikes[_strikeIndex],
            premium: premium, contracts: _contracts)
      else
        Text(
          'The most a bought option can lose is the premium — it can expire '
          'worthless and often does. Priced with one flat volatility, so treat '
          'it as illustrative.',
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
      final String verb = _writing ? 'Write' : 'Buy';
      return '$verb $_contracts contract${_contracts == 1 ? '' : 's'}';
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
      error = await c.tradeOption(
        contract: spec,
        size: _contracts,
        selling: _writing,
        markPerShare: premium,
        prices: ref.read(pricesProvider),
      );
    } else {
      error = _buying
          ? await c.buy(widget.quote.symbol, _shares, _spot)
          : await c.sell(widget.quote.symbol, _shares, _spot);
    }

    if (!mounted) return;
    if (error == null) {
      // Writing an option is the one trade here that opens an obligation, so
      // it gets the firmer, doubled confirmation.
      await (_options && _writing
          ? ref.read(hapticsProvider).warn()
          : ref.read(hapticsProvider).tick());
      if (!mounted) return;
      Navigator.pop(context);
    } else {
      setState(() {
        _working = false;
        _error = error;
      });
    }
  }
}

/// States, in cash, what writing this particular contract can cost.
///
/// Deliberately concrete rather than a generic warning: "unlimited" is easy to
/// nod past, "$4,200 if it falls to zero" is not. Required by CLAUDE.md rule 2
/// — a written option's downside has to be told plainly, every time.
class _WriteRiskNote extends StatelessWidget {
  const _WriteRiskNote({
    required this.isCall,
    required this.strike,
    required this.premium,
    required this.contracts,
  });

  final bool isCall;
  final double strike;
  final double premium;
  final int contracts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double kept = premium * contracts * kContractMultiplier;
    final double worstPut =
        (strike - premium) * contracts * kContractMultiplier;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.pnl.loss.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.pnl.loss.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 18, color: theme.pnl.loss),
              const SizedBox(width: 6),
              Text(
                'Writing carries the obligation',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.pnl.loss,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isCall
                ? 'The most you can make is the ${_money(kept)} premium. The '
                      'loss has no ceiling — you are obliged to deliver at '
                      '${_money(strike)} however high the price goes, so the '
                      'more it rises the more it costs to buy back.'
                : 'The most you can make is the ${_money(kept)} premium. The '
                      'worst case is ${_money(worstPut)}, if the price falls to '
                      'zero and you must still buy at ${_money(strike)}.',
            style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Collateral is held against the position while it is open, and this '
            'sandbox recomputes it from one flat volatility. A real broker '
            'would demand more, and could close you out.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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
  late int _contracts = widget.holding.size;
  String? _error;
  bool _working = false;

  /// Closing a long means selling; closing a written position means buying it
  /// back, and paying whatever it now costs.
  bool get _short => widget.holding.isShort;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double consideration =
        widget.mark * _contracts * kContractMultiplier;

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
            _short
                ? 'Buy back what you wrote, at the model mark of '
                      '${_money(widget.mark)} / share. Practice only.'
                : 'Sell at the model mark of ${_money(widget.mark)} / share. '
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
            onUp: _contracts < widget.holding.size
                ? () => setState(() => _contracts++)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            _short
                ? 'Cost to close: ${_money(consideration)}'
                : 'Proceeds: ${_money(consideration)}',
            style: theme.textTheme.bodyMedium,
          ),
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
            child: Text(
              _short ? 'Buy back $_contracts' : 'Sell $_contracts',
            ),
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
    // Closing runs the opposite way to how the position was opened.
    final String? error = await ref
        .read(portfolioControllerProvider.notifier)
        .tradeOption(
          contract: widget.holding,
          size: _contracts,
          selling: !_short,
          markPerShare: widget.mark,
          prices: ref.read(pricesProvider),
        );

    if (!mounted) return;
    if (error == null) {
      await ref.read(hapticsProvider).tick();
      if (!mounted) return;
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
