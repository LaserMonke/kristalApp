import 'package:flutter/material.dart';

import '../../../core/widgets/disclaimer_text.dart';
import '../../../games/stockle/stockle_engine.dart';

/// The full playable set, on demand.
///
/// Stockle only accepts tickers that are in the list, the same way Wordle only
/// accepts dictionary words. Hiding that list turns a reasoning puzzle into a
/// memory test of index membership, which is not the thing being taught — so
/// the list is one tap away, with the company behind each symbol next to it.
///
/// Tickers already guessed today are marked, so a player can see at a glance
/// what is still available without re-reading their own board.
class StockleTickerListSheet extends StatefulWidget {
  const StockleTickerListSheet({
    super.key,
    required this.dictionary,
    this.guessed = const <String>{},
  });

  final StockleDictionary dictionary;

  /// Symbols already played today.
  final Set<String> guessed;

  @override
  State<StockleTickerListSheet> createState() => _StockleTickerListSheetState();
}

class _StockleTickerListSheetState extends State<StockleTickerListSheet> {
  String _query = '';

  /// Alphabetical by symbol — the order someone scanning for a four-letter
  /// combination expects, rather than the index-weight order of the asset.
  late final List<StockleTicker> _sorted = List<StockleTicker>.of(
    widget.dictionary.tickers,
  )..sort((StockleTicker a, StockleTicker b) => a.symbol.compareTo(b.symbol));

  List<StockleTicker> get _visible {
    final String q = _query.trim().toUpperCase();
    if (q.isEmpty) return _sorted;
    return _sorted
        .where(
          (StockleTicker t) =>
              t.symbol.contains(q) || t.name.toUpperCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<StockleTicker> visible = _visible;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Ticker list', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Every guess must be one of these '
                    '${widget.dictionary.length} NASDAQ-100 tickers, as of '
                    '${widget.dictionary.asOf}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search ticker or company',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No ticker in the list matches “${_query.trim()}”.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final StockleTicker ticker = visible[index];
                        final bool played = widget.guessed.contains(
                          ticker.symbol,
                        );
                        return _TickerRow(ticker: ticker, played: played);
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: const DisclaimerBanner(
                icon: Icons.info_outline,
                text:
                    'A game list, not a reference index. Membership changes, '
                    'so it can fall behind, and nothing here is a suggestion '
                    'to buy or sell anything.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TickerRow extends StatelessWidget {
  const _TickerRow({required this.ticker, required this.played});

  final StockleTicker ticker;

  /// Already guessed today — dimmed so it reads as spent, not as wrong.
  final bool played;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faded = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: played
          ? '${ticker.symbol}, ${ticker.name}, ${ticker.sector}. '
                'Already guessed today.'
          : '${ticker.symbol}, ${ticker.name}, ${ticker.sector}.',
      excludeSemantics: true,
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 56,
          child: Text(
            ticker.symbol,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: played ? faded : theme.colorScheme.primary,
            ),
          ),
        ),
        title: Text(
          ticker.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: played ? faded : null,
          ),
        ),
        subtitle: Text(
          ticker.sector,
          style: theme.textTheme.bodySmall?.copyWith(color: faded),
        ),
        trailing: played ? Icon(Icons.check, size: 18, color: faded) : null,
      ),
    );
  }
}
