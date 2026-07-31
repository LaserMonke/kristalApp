// `price-heavy` — offloads very large Monte Carlo runs from the phone.
//
// DEPLOY.md 1d. Deploy with:
//     supabase functions deploy price-heavy
//
// WHAT THIS ENDPOINT IS FOR. Phase 8's simulations run on a Dart isolate on
// the device, which is fast enough for anything a learner will normally ask
// for. This exists for the runs that are not: a few million paths across a
// few hundred steps, where a phone would spend half a minute and a chunk of
// battery. `AdvancedPricer` in the client decides when to come here, and
// falls back to the device if this is unreachable — so this endpoint is an
// optimisation, never a dependency.
//
// WHAT IT RECEIVES AND RETURNS. In: the contract's numbers and the simulation
// settings. Out: a price, a standard error and a path count. Nothing else.
// No identifier is sent, nothing is written to the database, and no result is
// logged with a request body, so a learner exploring a hypothetical option
// tells the server nothing about themselves (CLAUDE.md rule 6 — collect the
// minimum).
//
// The closed-form comparison and the honesty notes are computed on the CLIENT
// (`lib/pricing/pricing_job.dart`) rather than here. That is deliberate: a
// stale deployment of this function then cannot serve an out-of-date caveat
// or omit one, and it keeps the amount of pricing mathematics that exists
// twice as small as possible. See the header of `engine.ts`.
//
// AUTHENTICATION. Callers must present a valid Supabase session. Without it
// the project's compute is free to anyone holding the publishable key, which
// ships in every copy of the app.

import { createClient } from "jsr:@supabase/supabase-js@2";

import { simulate } from "./engine.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return json({ error: "Use POST." }, 405);
  }

  // ── Authentication ──────────────────────────────────────────────────────
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Sign in to use the pricing server." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("price-heavy is missing SUPABASE_URL or SUPABASE_ANON_KEY");
    return json({ error: "The pricing server is misconfigured." }, 500);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return json({ error: "Sign in to use the pricing server." }, 401);
  }

  // ── Run ─────────────────────────────────────────────────────────────────
  let job: unknown;
  try {
    job = await request.json();
  } catch {
    return json({ error: "The request body was not valid JSON." }, 400);
  }

  const startedAt = performance.now();
  try {
    const estimate = simulate(job);

    // Deliberately logged WITHOUT the request body: how long a job took is
    // useful for capacity planning, what contract a learner was exploring is
    // nobody's business.
    console.log(
      `price-heavy ok in ${Math.round(performance.now() - startedAt)}ms`,
    );

    return json({
      price: estimate.price,
      standard_error: estimate.standardError,
      paths: estimate.paths,
    }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error.";
    // A rejected job is the caller's mistake, so the reason is returned; it
    // describes the request, never the server's internals.
    console.error(`price-heavy rejected a job: ${message}`);
    return json({ error: message }, 400);
  }
});
