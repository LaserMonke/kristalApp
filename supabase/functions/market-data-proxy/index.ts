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

// An allow-list so a caller cannot turn this into a free proxy for the whole
// API. Extend deliberately.
const ALLOWED = new Set<string>([
  "AAPL",
  "MSFT",
  "SPY",
  "TSLA",
  "NVDA",
  "AMZN",
  "GOOGL",
]);

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

  let symbols: string[];
  try {
    const body = await req.json();
    symbols = Array.isArray(body?.symbols) ? body.symbols : [];
  } catch (_) {
    return json({ error: "Expected a JSON body with a symbols array." }, 400);
  }

  // Normalise, filter to the allow-list, cap the count.
  const wanted = [...new Set(symbols.map((s) => String(s).toUpperCase()))]
    .filter((s) => ALLOWED.has(s))
    .slice(0, 10);

  if (wanted.length === 0) {
    return json({ error: "No allowed symbols requested.", quotes: [] }, 200);
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
