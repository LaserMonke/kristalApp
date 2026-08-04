import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/disclaimer_text.dart';
import '../../../data/models/market.dart';
import '../../../games/stockle/stockle_engine.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/stockle_providers.dart';

/// Fetches the finished puzzle's quote once. Autodisposed so leaving the
/// screen does not keep it alive, and keyed on the symbol.
final quoteForProvider = FutureProvider.autoDispose
    .family<Quote?, String>((Ref ref, String symbol) async {
      try {
        final List<Quote> quotes = await ref
            .read(marketRepoProvider)
            .quotes(<String>[symbol]);
        return quotes.isEmpty ? null : quotes.first;
      } catch (_) {
        // The overview is the reward, not the game. A dead network should
        // degrade it, never blank the result the player just earned.
        return null;
      }
    });

/// Shown once the day's game ends: the verdict, then what the ticker actually
/// is — which is the part that teaches anything.
class StockleResult extends ConsumerWidget {
  const StockleResult({super.key, required this.game});

  final StockleState game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final StockleStats stats = ref.watch(stockleStatsProvider);
    final int points = stocklePoints(game);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Icon(
                  game.isWon ? Icons.check_circle_outline : Icons.schedule,
                  size: 32,
                  color: game.isWon
                      ? AppColors.bluishGreen
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  game.isWon
                      ? 'Solved in ${game.guessesUsed} '
                            '${game.guessesUsed == 1 ? "guess" : "guesses"}'
                      : 'Today’s ticker was ${game.answer.symbol}',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (game.isWon && points > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '+$points points',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.bluishGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (!game.isWon) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'No points today, and nothing taken away. '
                    'A new ticker arrives at midnight UTC.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),
                _StatsRow(stats: stats),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CompanyOverview(ticker: game.answer),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final StockleStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _Stat(label: 'Played', value: '${stats.played}'),
        _Stat(
          label: 'Solved',
          value: stats.winPercent == null ? '—' : '${stats.winPercent}%',
        ),
        _Stat(label: 'Streak', value: '${stats.streak}'),
        _Stat(label: 'Points', value: '${stats.points}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The payoff: who the ticker actually belongs to, and where it is trading.
class _CompanyOverview extends ConsumerWidget {
  const _CompanyOverview({required this.ticker});

  final StockleTicker ticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<Quote?> quote = ref.watch(quoteForProvider(ticker.symbol));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticker.symbol,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ticker.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        ticker.sector,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            quote.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (Object _, StackTrace _) => const _NoPrice(),
              data: (Quote? q) => q == null ? const _NoPrice() : _Price(q),
            ),
            const SizedBox(height: 14),
            const DisclaimerBanner(text: Disclaimers.noAdviceShort),
          ],
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price(this.quote);

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool up = quote.change >= 0;

    // Colourblind-safe: an arrow and an explicit sign carry the direction, not
    // the colour on its own.
    final Color tone = up ? AppColors.blue : AppColors.vermillion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              quote.price.toStringAsFixed(2),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: tone,
            ),
            const SizedBox(width: 2),
            Text(
              '${up ? "+" : ""}${quote.change.toStringAsFixed(2)} '
              '(${up ? "+" : ""}${quote.percentChange.toStringAsFixed(2)}%)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          quote.synthetic
              // Not real data. Saying "delayed" here would be a lie.
              ? 'Simulated price — no live market data is available, so this '
                    'is a stand-in, not a real quote.'
              : quote.delayed
              ? 'Delayed price, not real time.'
              : 'Price as reported by our data provider.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NoPrice extends StatelessWidget {
  const _NoPrice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      'No price available right now.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
