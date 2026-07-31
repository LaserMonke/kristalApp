// Cross-language agreement test for the price-heavy engine.
//
// `vectors.json` is generated FROM THE DART ENGINE (see the note in
// supabase/functions/price-heavy/README.md). Both implementations use the same
// named generator seeded the same way, so identical inputs must produce the
// same price — not a statistically compatible one, the same one. Two genuinely
// independent implementations of a Monte Carlo pricer would differ in the
// second decimal place; these agree to about the twelfth.
//
// The tolerance is not zero only because `Math.exp` and `Math.log` may differ
// by an ulp between the Dart VM's libm and V8's, which accumulates to a
// relative difference far below anything that could matter.
//
// Run with either:
//     deno test --allow-read supabase/functions/price-heavy/engine.test.ts
//     node --test supabase/functions/price-heavy/engine.test.ts

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

import { inverseNormalCdf, simulate } from "./engine.ts";

const here = dirname(fileURLToPath(import.meta.url));

interface Vector {
  // deno-lint-ignore no-explicit-any
  job: any;
  expected: { price: number; standard_error: number; paths: number };
}

const vectors: Vector[] = JSON.parse(
  readFileSync(join(here, "vectors.json"), "utf8"),
);

/** Relative agreement, with an absolute floor for prices near zero. */
function assertClose(actual: number, expected: number, what: string): void {
  const tolerance = 1e-9 * Math.max(1, Math.abs(expected));
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${what}: got ${actual}, expected ${expected} ` +
      `(differs by ${Math.abs(actual - expected)})`,
  );
}

test("vectors.json is present and covers every job kind", () => {
  assert.ok(vectors.length >= 10, "expected at least ten vectors");
  const kinds = new Set(vectors.map((v) => v.job.kind));
  for (const kind of ["european", "barrier", "asian", "basket", "heston"]) {
    assert.ok(kinds.has(kind), `no vector covers "${kind}"`);
  }
});

for (const [index, vector] of vectors.entries()) {
  const name = `${vector.job.kind} vector ${index} matches the Dart engine`;
  test(name, () => {
    const result = simulate(vector.job);
    assertClose(result.price, vector.expected.price, "price");
    assertClose(
      result.standardError,
      vector.expected.standard_error,
      "standard error",
    );
    assert.equal(result.paths, vector.expected.paths, "path count");
  });
}

test("the inverse normal CDF matches known quantiles", () => {
  assertClose(inverseNormalCdf(0.975), 1.9599639845400545, "97.5th");
  assertClose(inverseNormalCdf(0.5), 0, "median");
  assert.ok(Math.abs(inverseNormalCdf(0.5)) < 1e-9);
});

test("malformed jobs are refused rather than guessed at", () => {
  assert.throws(() => simulate({ kind: "quantum" }), /Unknown job kind/);
  assert.throws(
    () => simulate({ kind: "european", type: "straddle" }),
    /Expected a whole number|Unknown type/,
  );
  assert.throws(
    () =>
      simulate({
        kind: "european",
        type: "call",
        inputs: {
          spot: 100,
          strike: 100,
          rate: 0,
          volatility: 0.2,
          time_to_expiry: 1,
        },
        settings: { paths: 10, steps: 1, seed: 1.5, antithetic: true },
      }),
    /whole number/,
  );
});

test("an absurd workload is refused", () => {
  assert.throws(
    () =>
      simulate({
        kind: "european",
        type: "call",
        inputs: {
          spot: 100,
          strike: 100,
          rate: 0,
          volatility: 0.2,
          time_to_expiry: 1,
        },
        settings: {
          paths: 40000000,
          steps: 20000,
          seed: 1,
          antithetic: true,
        },
      }),
    /larger than this endpoint/,
  );
});
