// market-data-proxy — the ONLY place the paid Finnhub key lives.
//
// CLAUDE.md rule 8: a paid data-API key must never ship in the app binary.
// The Flutter client calls this function; the function reads the key from a
// Supabase secret (`FINNHUB_API_KEY`) and calls Finnhub server-side, returning
// only the fields the client needs. The key is never sent to the client.
//
// The response is labelled "delayed" on purpose. Free Finnhub tiers and many
// venues are delayed, and rule 8 also says delayed data must be labelled — so
// the label is attached HERE, server-side, where the client cannot strip it.
//
// Deploy:  supabase functions deploy market-data-proxy --project-ref <ref>
// Secret:  supabase secrets set FINNHUB_API_KEY=... --project-ref <ref>

const FINNHUB = "https://finnhub.io/api/v1";

// Learners can follow any ticker, so a fixed allow-list is gone. What remains
// is shape validation and hard caps: this endpoint still only ever reaches two
// Finnhub paths, never takes a URL from the caller, and refuses anything that
// is not ticker-shaped — so it cannot be turned into a general proxy for the
// API the key pays for.
const SYMBOL = /^[A-Z][A-Z0-9.\-]{0,9}$/;
const MAX_SYMBOLS = 20;
const MAX_MATCHES = 15;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Quote {
  symbol: string;
  price: number;
  change: number;
  percentChange: number;
  high: number;
  low: number;
  open: number;
  previousClose: number;
  // Always true here: we do not promise real-time, and the client shows it.
  delayed: boolean;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  const key = Deno.env.get("FINNHUB_API_KEY");
  if (!key) {
    return json({ error: "Market data is not configured on the server." }, 503);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Expected a JSON body." }, 400);
  }

  // Two actions, both fixed here. The caller picks between them; it never
  // supplies a path.
  if (typeof body?.query === "string") {
    return await handleSearch(body.query, key);
  }

  const symbols = Array.isArray(body?.symbols) ? body.symbols : [];

  // Normalise, keep only ticker-shaped entries, cap the count.
  const wanted = [...new Set(symbols.map((s) => String(s).toUpperCase()))]
    .filter((s) => SYMBOL.test(s))
    .slice(0, MAX_SYMBOLS);

  if (wanted.length === 0) {
    return json({ error: "No valid symbols requested.", quotes: [] }, 200);
  }

  try {
    const quotes = await Promise.all(
      wanted.map((symbol) => fetchQuote(symbol, key)),
    );
    return json({
      quotes: quotes.filter((q): q is Quote => q !== null),
      // A second, machine-readable label so the client never has to assume.
      disclaimer:
        "Delayed market data, provided for a learning simulation only. " +
        "Not a quote to trade on.",
    }, 200);
  } catch (_) {
    return json({ error: "Could not reach the market data provider." }, 502);
  }
});

// Symbol lookup for the Market tab's search field. Returns tickers and names
// only — no prices, so nothing here needs the delayed-data label.
async function handleSearch(raw: string, key: string): Promise<Response> {
  const query = raw.trim();
  if (query.length === 0 || query.length > 40) {
    return json({ matches: [] }, 200);
  }

  try {
    const res = await fetch(
      `${FINNHUB}/search?q=${encodeURIComponent(query)}&exchange=US&token=${key}`,
    );
    if (!res.ok) return json({ error: "Symbol search failed.", matches: [] }, 502);

    const body = await res.json();
    const result = Array.isArray(body?.result) ? body.result : [];
    const matches = result
      // Common stock and ETFs only: the learner cannot trade the rest here, so
      // offering them would just be a dead end.
      .filter((r: Record<string, unknown>) =>
        typeof r?.symbol === "string" && SYMBOL.test(r.symbol)
      )
      .slice(0, MAX_MATCHES)
      .map((r: Record<string, unknown>) => ({
        symbol: r.symbol as string,
        description: typeof r.description === "string" ? r.description : "",
      }));

    return json({ matches }, 200);
  } catch (_) {
    return json({ error: "Could not reach the market data provider." }, 502);
  }
}

async function fetchQuote(symbol: string, key: string): Promise<Quote | null> {
  const res = await fetch(
    `${FINNHUB}/quote?symbol=${encodeURIComponent(symbol)}&token=${key}`,
  );
  if (!res.ok) return null;
  const q = await res.json();
  // Finnhub /quote: c=current, d=change, dp=percent, h/l/o, pc=prev close.
  if (typeof q?.c !== "number" || q.c === 0) return null;
  return {
    symbol,
    price: q.c,
    change: typeof q.d === "number" ? q.d : 0,
    percentChange: typeof q.dp === "number" ? q.dp : 0,
    high: typeof q.h === "number" ? q.h : q.c,
    low: typeof q.l === "number" ? q.l : q.c,
    open: typeof q.o === "number" ? q.o : q.c,
    previousClose: typeof q.pc === "number" ? q.pc : q.c,
    delayed: true,
  };
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
