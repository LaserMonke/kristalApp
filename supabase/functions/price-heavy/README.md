# `price-heavy`

Offloads very large Monte Carlo runs from the phone (DEPLOY.md 1d).

    supabase functions deploy price-heavy

It is an **optimisation, never a dependency**. `AdvancedPricer` on the client
falls back to an on-device isolate whenever this is unreachable, so the app
works fully with this function never deployed at all. That is also why nothing
here is on the critical path of a lesson.

## Why there is a second pricing engine, and how it is kept honest

`engine.ts` re-implements part of `lib/pricing/` in TypeScript. Two
implementations of the same mathematics can drift apart silently, and the
failure mode — a wrong price delivered confidently — is the worst one this app
has. Three things hold it together:

**1. It only re-implements the expensive part.** Generating paths, and nothing
else. Every closed form, every caveat and every label stays in
`lib/pricing/pricing_job.dart` and is applied on the device after the numbers
come back. So a stale deployment of this function cannot serve an out-of-date
disclaimer or drop one, and the surface that can disagree is as small as it can
be made.

**2. The two engines agree bit-for-bit, not statistically.** Both use
xoshiro128** seeded through SplitMix32 and Acklam's inverse-normal transform,
so the same job produces the *same price*, agreeing to around twelve decimal
places rather than to within sampling error. Two genuinely independent Monte
Carlo pricers would differ in the second decimal. The residual gap is only
`Math.exp`/`Math.log` differing by an ulp between the Dart VM's libm and V8's.

**3. There is a test that proves it.** `vectors.json` holds ten jobs — covering
every job kind, both antithetic settings, correlated baskets and Heston — with
the price the **Dart** engine produced for each.

    node --test supabase/functions/price-heavy/engine.test.ts
    # or, with a Deno install:
    deno test --allow-read supabase/functions/price-heavy/engine.test.ts

## After changing any pricing code

If you touch `lib/pricing/monte_carlo.dart`, `basket.dart`, `heston.dart` or
`random.dart`, the vectors are stale. Regenerate them, then re-run the test
above.

**The Dart is the source of truth.** It is the side with reference-value tests
behind it — independently computed in Python, checked against Black-Scholes
limits, put-call parity and in-out parity. If the two disagree, `engine.ts` is
what changes.

To regenerate, write a throwaway Dart test that decodes each `job` object from
`vectors.json`, calls `simulatePricingJob`, and writes the resulting price,
standard error and path count back into the `expected` field. Keep the existing
jobs so a regression shows up as a diff rather than as a new baseline.

## Privacy

The request carries a contract's numbers and nothing else — no user id, no
username, no progress. Nothing is written to the database. The success log
records a duration only, deliberately **not** the request body: how long a job
took is useful for capacity planning, which option a learner was curious about
is not ours to keep (CLAUDE.md rule 6).

## Authentication

Callers must present a valid session; `SUPABASE_ANON_KEY` alone is refused with
a 401. The publishable key ships inside every copy of the app, so without this
check the project's compute would be free to anyone who extracted it.
