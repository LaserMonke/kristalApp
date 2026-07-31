// Monte Carlo engine for the `price-heavy` Edge Function (DEPLOY.md 1d).
//
// THIS IS A SECOND IMPLEMENTATION OF CODE THAT ALREADY EXISTS IN DART, and
// that is a hazard, not a convenience. Two implementations of the same
// mathematics can drift apart silently, and the failure mode is a wrong price
// delivered confidently. Three things keep that in check:
//
//   1. SCOPE. Only the genuinely heavy part is here — generating paths. Every
//      closed form, every caveat and every label stays on the client
//      (`lib/pricing/pricing_job.dart`), so a stale deployment of this file
//      cannot serve an out-of-date disclaimer or a missing one.
//   2. BIT-FOR-BIT AGREEMENT. Both sides use the same named generator
//      (xoshiro128**) and the same inverse-normal transform, seeded the same
//      way, so identical inputs must produce the SAME PRICE — not merely a
//      statistically compatible one. `engine.test.ts` checks that against
//      `vectors.json`, which is generated from the Dart engine.
//   3. ORDER OF OPERATIONS. The arithmetic below deliberately mirrors the
//      Dart line for line, including where terms are grouped, because
//      floating-point addition is not associative and a "tidier" rearrangement
//      would break the agreement in (2).
//
// If you change anything in `lib/pricing/monte_carlo.dart`, `basket.dart`,
// `heston.dart` or `random.dart`, regenerate the vectors and re-run the test
// here. If the two disagree, the Dart is the source of truth: it is the one
// with the reference-value tests behind it.

export interface McSettings {
  paths: number;
  steps: number;
  seed: number;
  antithetic: boolean;
}

export interface McEstimate {
  price: number;
  standardError: number;
  paths: number;
}

// ── Random numbers ────────────────────────────────────────────────────────

/** xoshiro128** 1.0, matching `lib/pricing/random.dart`. */
class Xoshiro128 {
  private s0 = 0;
  private s1 = 0;
  private s2 = 0;
  private s3 = 0;

  constructor(seed: number) {
    let x = seed >>> 0;
    const splitmix32 = (): number => {
      x = (x + 0x9e3779b9) >>> 0;
      let z = x;
      z = (z ^ (z >>> 16)) >>> 0;
      z = Math.imul(z, 0x21f0aaad) >>> 0;
      z = (z ^ (z >>> 15)) >>> 0;
      z = Math.imul(z, 0x735a2d97) >>> 0;
      return (z ^ (z >>> 15)) >>> 0;
    };

    this.s0 = splitmix32();
    this.s1 = splitmix32();
    this.s2 = splitmix32();
    this.s3 = splitmix32();

    if ((this.s0 | this.s1 | this.s2 | this.s3) === 0) this.s0 = 0x9e3779b9;
  }

  private static rotl(x: number, k: number): number {
    return ((x << k) | (x >>> (32 - k))) >>> 0;
  }

  nextUint32(): number {
    const result = Math.imul(
      Xoshiro128.rotl(Math.imul(this.s1, 5) >>> 0, 7),
      9,
    ) >>> 0;
    const t = (this.s1 << 9) >>> 0;

    this.s2 = (this.s2 ^ this.s0) >>> 0;
    this.s3 = (this.s3 ^ this.s1) >>> 0;
    this.s1 = (this.s1 ^ this.s2) >>> 0;
    this.s0 = (this.s0 ^ this.s3) >>> 0;
    this.s2 = (this.s2 ^ t) >>> 0;
    this.s3 = Xoshiro128.rotl(this.s3, 11);

    return result;
  }

  /** 53 bits of randomness in [0, 1), assembled exactly as the Dart does. */
  nextDouble(): number {
    const hi = this.nextUint32() >>> 5;
    const lo = this.nextUint32() >>> 6;
    return (hi * 67108864.0 + lo) / 9007199254740992.0;
  }
}

const TINY = 1e-15;

/** Acklam's inverse normal CDF, matching `lib/pricing/random.dart`. */
export function inverseNormalCdf(p: number): number {
  const a = [
    -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
    1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00,
  ];
  const b = [
    -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
    6.680131188771972e+01, -1.328068155288572e+01,
  ];
  const c = [
    -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
    -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00,
  ];
  const d = [
    7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
    3.754408661907416e+00,
  ];

  const pLow = 0.02425;
  const pHigh = 1 - pLow;

  if (p < pLow) {
    const q = Math.sqrt(-2 * Math.log(p));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
      c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (p > pHigh) {
    const q = Math.sqrt(-2 * Math.log(1 - p));
    return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
      c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }

  const q = p - 0.5;
  const r = q * q;
  return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
    q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
}

/** Draws one path's block of shocks; antithetic pairs mirror whole paths. */
class NormalPathSampler {
  private readonly rng: Xoshiro128;
  private readonly buffer: Float64Array;
  private readonly dimension: number;
  private readonly antithetic: boolean;
  private mirrorNext = false;

  // Fields are declared and assigned explicitly rather than as TypeScript
  // parameter properties, so this file runs under Node's strip-only type
  // handling as well as under Deno — which is what lets the cross-language
  // test be run without a Deno install.
  constructor(seed: number, dimension: number, antithetic: boolean) {
    this.rng = new Xoshiro128(seed);
    this.buffer = new Float64Array(dimension);
    this.dimension = dimension;
    this.antithetic = antithetic;
  }

  nextPath(): Float64Array {
    if (this.antithetic && this.mirrorNext) {
      this.mirrorNext = false;
      for (let i = 0; i < this.dimension; i++) {
        this.buffer[i] = -this.buffer[i];
      }
      return this.buffer;
    }
    for (let i = 0; i < this.dimension; i++) {
      const raw = this.rng.nextDouble();
      const u = raw < TINY ? TINY : raw > 1 - TINY ? 1 - TINY : raw;
      this.buffer[i] = inverseNormalCdf(u);
    }
    this.mirrorNext = this.antithetic;
    return this.buffer;
  }
}

/** Running mean and variance, pairing antithetic paths before measuring. */
class McAccumulator {
  private count = 0;
  private sum = 0;
  private sumSquares = 0;
  private pending: number | null = null;
  private readonly paired: boolean;

  constructor(paired: boolean) {
    this.paired = paired;
  }

  add(payoff: number): void {
    if (!this.paired) {
      this.record(payoff);
      return;
    }
    if (this.pending === null) {
      this.pending = payoff;
      return;
    }
    this.record(0.5 * (this.pending + payoff));
    this.pending = null;
  }

  private record(value: number): void {
    this.count++;
    this.sum += value;
    this.sumSquares += value * value;
  }

  finish(discountFactor: number): McEstimate {
    if (this.count === 0) return { price: 0, standardError: 0, paths: 0 };
    const mean = this.sum / this.count;
    const variance = this.count < 2
      ? 0
      : Math.max(
        (this.sumSquares - this.count * mean * mean) / (this.count - 1),
        0,
      );
    return {
      price: discountFactor * mean,
      standardError: discountFactor * Math.sqrt(variance / this.count),
      paths: this.count,
    };
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────

function gbmStep(
  s: number,
  drift: number,
  diffusion: number,
  z: number,
): number {
  return s * Math.exp(drift + diffusion * z);
}

function vanillaPayoff(type: string, underlying: number, strike: number) {
  return type === "call"
    ? (underlying > strike ? underlying - strike : 0)
    : (strike > underlying ? strike - underlying : 0);
}

/** Abramowitz & Stegun 26.2.17, matching `lib/pricing/black_scholes.dart`. */
function normalPdf(x: number): number {
  return Math.exp(-x * x / 2) / Math.sqrt(2 * Math.PI);
}

function normalCdf(x: number): number {
  const negative = x < 0;
  const z = negative ? -x : x;
  const b1 = 0.319381530, b2 = -0.356563782, b3 = 1.781477937;
  const b4 = -1.821255978, b5 = 1.330274429, p = 0.2316419;
  const tt = 1 / (1 + p * z);
  const poly = tt * (b1 + tt * (b2 + tt * (b3 + tt * (b4 + tt * b5))));
  const cdf = 1 - normalPdf(z) * poly;
  return negative ? 1 - cdf : cdf;
}

/**
 * Black-Scholes-Merton price only (no Greeks). Needed for exactly one case:
 * a knock-IN whose barrier is already breached has become an ordinary option,
 * and there is nothing left to simulate.
 */
function bsmPrice(
  type: string,
  spot: number,
  strike: number,
  rate: number,
  volatility: number,
  timeToExpiry: number,
  dividendYield: number,
): number {
  const sqrtT = Math.sqrt(timeToExpiry);
  const d1 = (Math.log(spot / strike) +
    (rate - dividendYield + 0.5 * volatility * volatility) * timeToExpiry) /
    (volatility * sqrtT);
  const d2 = d1 - volatility * sqrtT;
  const discountR = Math.exp(-rate * timeToExpiry);
  const discountQ = Math.exp(-dividendYield * timeToExpiry);
  return type === "call"
    ? spot * discountQ * normalCdf(d1) - strike * discountR * normalCdf(d2)
    : strike * discountR * normalCdf(-d2) - spot * discountQ * normalCdf(-d1);
}

interface BsmInputs {
  spot: number;
  strike: number;
  rate: number;
  volatility: number;
  time_to_expiry: number;
  dividend_yield?: number;
}

function yieldOf(inputs: BsmInputs): number {
  return inputs.dividend_yield ?? 0;
}

// ── The five payoffs ──────────────────────────────────────────────────────

function european(
  type: string,
  inputs: BsmInputs,
  settings: McSettings,
): McEstimate {
  const t = inputs.time_to_expiry;
  const dt = t / settings.steps;
  const drift =
    (inputs.rate - yieldOf(inputs) - 0.5 * inputs.volatility * inputs.volatility) *
    dt;
  const diffusion = inputs.volatility * Math.sqrt(dt);

  const sampler = new NormalPathSampler(
    settings.seed,
    settings.steps,
    settings.antithetic,
  );
  const acc = new McAccumulator(settings.antithetic);

  for (let i = 0; i < settings.paths; i++) {
    const shocks = sampler.nextPath();
    let s = inputs.spot;
    for (let step = 0; step < settings.steps; step++) {
      s = gbmStep(s, drift, diffusion, shocks[step]);
    }
    acc.add(vanillaPayoff(type, s, inputs.strike));
  }
  return acc.finish(Math.exp(-inputs.rate * t));
}

/** Broadie-Glasserman-Kou, shifted TOWARDS the spot — see barrier.dart. */
function continuousEquivalentBarrier(
  barrier: number,
  direction: string,
  volatility: number,
  timeToExpiry: number,
  monitoringDates: number,
): number {
  const beta = 0.5826;
  const shift = Math.exp(
    beta * volatility * Math.sqrt(timeToExpiry / monitoringDates),
  );
  return direction === "down" ? barrier * shift : barrier / shift;
}

function barrier(
  optionType: string,
  direction: string,
  style: string,
  barrierLevel: number,
  continuityCorrection: boolean,
  inputs: BsmInputs,
  settings: McSettings,
): McEstimate {
  const t = inputs.time_to_expiry;
  const discount = Math.exp(-inputs.rate * t);
  const down = direction === "down";

  const alreadyTriggered = down
    ? inputs.spot <= barrierLevel
    : inputs.spot >= barrierLevel;
  if (alreadyTriggered) {
    const settled = style === "knockOut" ? 0 : bsmPrice(
      optionType,
      inputs.spot,
      inputs.strike,
      inputs.rate,
      inputs.volatility,
      t,
      yieldOf(inputs),
    );
    return { price: settled, standardError: 0, paths: settings.paths };
  }

  const level = continuityCorrection
    ? continuousEquivalentBarrier(
      barrierLevel,
      direction,
      inputs.volatility,
      t,
      settings.steps,
    )
    : barrierLevel;

  const dt = t / settings.steps;
  const drift =
    (inputs.rate - yieldOf(inputs) - 0.5 * inputs.volatility * inputs.volatility) *
    dt;
  const diffusion = inputs.volatility * Math.sqrt(dt);

  const sampler = new NormalPathSampler(
    settings.seed,
    settings.steps,
    settings.antithetic,
  );
  const acc = new McAccumulator(settings.antithetic);

  for (let i = 0; i < settings.paths; i++) {
    const shocks = sampler.nextPath();
    let s = inputs.spot;
    let touched = false;
    for (let step = 0; step < settings.steps; step++) {
      s = gbmStep(s, drift, diffusion, shocks[step]);
      if (!touched && (down ? s <= level : s >= level)) touched = true;
    }
    const alive = style === "knockOut" ? !touched : touched;
    acc.add(alive ? vanillaPayoff(optionType, s, inputs.strike) : 0);
  }
  return acc.finish(discount);
}

function asian(
  type: string,
  average: string,
  inputs: BsmInputs,
  settings: McSettings,
): McEstimate {
  const t = inputs.time_to_expiry;
  const dt = t / settings.steps;
  const drift =
    (inputs.rate - yieldOf(inputs) - 0.5 * inputs.volatility * inputs.volatility) *
    dt;
  const diffusion = inputs.volatility * Math.sqrt(dt);

  const sampler = new NormalPathSampler(
    settings.seed,
    settings.steps,
    settings.antithetic,
  );
  const acc = new McAccumulator(settings.antithetic);

  for (let i = 0; i < settings.paths; i++) {
    const shocks = sampler.nextPath();
    let s = inputs.spot;
    let total = 0;
    let logTotal = 0;
    for (let step = 0; step < settings.steps; step++) {
      s = gbmStep(s, drift, diffusion, shocks[step]);
      if (average === "arithmetic") total += s;
      else logTotal += Math.log(s);
    }
    const mean = average === "arithmetic"
      ? total / settings.steps
      : Math.exp(logTotal / settings.steps);
    acc.add(vanillaPayoff(type, mean, inputs.strike));
  }
  return acc.finish(Math.exp(-inputs.rate * t));
}

/** Lower-triangular Cholesky factor; throws on an impossible matrix. */
function cholesky(matrix: number[][]): number[][] {
  const n = matrix.length;
  const l: number[][] = Array.from({ length: n }, () => new Array(n).fill(0));
  for (let i = 0; i < n; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = 0;
      for (let k = 0; k < j; k++) sum += l[i][k] * l[j][k];
      if (i === j) {
        const diagonal = matrix[i][i] - sum;
        if (diagonal < -1e-10) {
          throw new Error(
            "These correlations are impossible: no set of assets can move " +
              "this way at once.",
          );
        }
        l[i][j] = Math.sqrt(Math.max(diagonal, 0));
      } else {
        l[i][j] = l[j][j] === 0 ? 0 : (matrix[i][j] - sum) / l[j][j];
      }
    }
  }
  return l;
}

interface BasketAssetJson {
  spot: number;
  volatility: number;
  weight: number;
  dividend_yield?: number;
}

function basket(
  assets: BasketAssetJson[],
  correlation: number[][],
  strike: number,
  type: string,
  rate: number,
  timeToExpiry: number,
  average: string,
  settings: McSettings,
): McEstimate {
  const n = assets.length;
  const t = timeToExpiry;

  let totalWeight = 0;
  for (const a of assets) totalWeight += a.weight;
  const weights = assets.map((a) => a.weight / totalWeight);

  const chol = cholesky(correlation);
  const drift = new Float64Array(n);
  const diffusion = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const a = assets[i];
    drift[i] =
      (rate - (a.dividend_yield ?? 0) - 0.5 * a.volatility * a.volatility) * t;
    diffusion[i] = a.volatility * Math.sqrt(t);
  }

  const sampler = new NormalPathSampler(settings.seed, n, settings.antithetic);
  const acc = new McAccumulator(settings.antithetic);
  const correlated = new Float64Array(n);

  for (let p = 0; p < settings.paths; p++) {
    const z = sampler.nextPath();
    for (let i = 0; i < n; i++) {
      let sum = 0;
      for (let k = 0; k <= i; k++) sum += chol[i][k] * z[k];
      correlated[i] = sum;
    }

    let level = 0;
    let logLevel = 0;
    for (let i = 0; i < n; i++) {
      const terminal = assets[i].spot *
        Math.exp(drift[i] + diffusion[i] * correlated[i]);
      if (average === "arithmetic") level += weights[i] * terminal;
      else logLevel += weights[i] * Math.log(terminal);
    }
    if (average === "geometric") level = Math.exp(logLevel);

    acc.add(
      type === "call"
        ? (level > strike ? level - strike : 0)
        : (strike > level ? strike - level : 0),
    );
  }
  return acc.finish(Math.exp(-rate * t));
}

interface HestonParamsJson {
  initial_variance: number;
  long_run_variance: number;
  mean_reversion: number;
  vol_of_vol: number;
  correlation: number;
}

function heston(
  type: string,
  params: HestonParamsJson,
  spot: number,
  strike: number,
  rate: number,
  timeToExpiry: number,
  dividendYield: number,
  payoff: string,
  settings: McSettings,
): McEstimate {
  const dt = timeToExpiry / settings.steps;
  const sqrtDt = Math.sqrt(dt);
  const kappa = params.mean_reversion;
  const theta = params.long_run_variance;
  const xi = params.vol_of_vol;
  const rho = params.correlation;
  const rhoComplement = Math.sqrt(Math.max(1 - rho * rho, 0));

  const sampler = new NormalPathSampler(
    settings.seed,
    2 * settings.steps,
    settings.antithetic,
  );
  const acc = new McAccumulator(settings.antithetic);

  for (let p = 0; p < settings.paths; p++) {
    const shocks = sampler.nextPath();
    let logSpot = Math.log(spot);
    let variance = params.initial_variance;
    let runningTotal = 0;

    for (let step = 0; step < settings.steps; step++) {
      const zVariance = shocks[2 * step];
      const zIndependent = shocks[2 * step + 1];
      const zPrice = rho * zVariance + rhoComplement * zIndependent;

      const usable = variance > 0 ? variance : 0;
      const volatility = Math.sqrt(usable);

      logSpot += (rate - dividendYield - 0.5 * usable) * dt +
        volatility * sqrtDt * zPrice;
      variance += kappa * (theta - usable) * dt +
        xi * volatility * sqrtDt * zVariance;

      if (payoff === "asianArithmetic") runningTotal += Math.exp(logSpot);
    }

    const observed = payoff === "asianArithmetic"
      ? runningTotal / settings.steps
      : Math.exp(logSpot);
    acc.add(vanillaPayoff(type, observed, strike));
  }
  return acc.finish(Math.exp(-rate * timeToExpiry));
}

// ── Dispatch ──────────────────────────────────────────────────────────────

/** How large a run this function will accept, matching AdvancedPricer. */
export const MAX_WORKLOAD = 400000000;

// deno-lint-ignore no-explicit-any
export function simulate(job: any): McEstimate {
  // Kind first, so an unrecognised request says so rather than complaining
  // about whichever field happened to be validated earliest.
  const kind = readEnum(
    job?.kind,
    ["european", "barrier", "asian", "basket", "heston"],
    "job kind",
  );

  const settings = readSettings(job?.settings);
  if (settings.paths * settings.steps > MAX_WORKLOAD) {
    throw new Error("Run is larger than this endpoint will attempt.");
  }

  switch (kind) {
    case "european":
      return european(
        readEnum(job.type, ["call", "put"], "type"),
        readInputs(job.inputs),
        settings,
      );
    case "barrier":
      return barrier(
        readEnum(job.option_type, ["call", "put"], "option_type"),
        readEnum(job.direction, ["down", "up"], "direction"),
        readEnum(job.style, ["knockOut", "knockIn"], "style"),
        readNumber(job.barrier, "barrier"),
        job.continuity_correction === true,
        readInputs(job.inputs),
        settings,
      );
    case "asian":
      return asian(
        readEnum(job.type, ["call", "put"], "type"),
        readEnum(job.average, ["arithmetic", "geometric"], "average"),
        readInputs(job.inputs),
        settings,
      );
    case "basket":
      return basket(
        readAssets(job.assets),
        readMatrix(job.correlation),
        readNumber(job.strike, "strike"),
        readEnum(job.type, ["call", "put"], "type"),
        readNumber(job.rate, "rate"),
        readNumber(job.time_to_expiry, "time_to_expiry"),
        readEnum(job.average, ["arithmetic", "geometric"], "average"),
        settings,
      );
    case "heston":
      return heston(
        readEnum(job.type, ["call", "put"], "type"),
        readHestonParams(job.params),
        readNumber(job.spot, "spot"),
        readNumber(job.strike, "strike"),
        readNumber(job.rate, "rate"),
        readNumber(job.time_to_expiry, "time_to_expiry"),
        job.dividend_yield == null ? 0 : readNumber(job.dividend_yield, "q"),
        readEnum(job.payoff, ["european", "asianArithmetic"], "payoff"),
        settings,
      );
    default:
      // Unreachable: readEnum above has already rejected anything else.
      throw new Error(`Unknown job kind "${kind}".`);
  }
}

// ── Validation ────────────────────────────────────────────────────────────
//
// Strict on purpose, and mirroring the Dart. A defaulted field would turn a
// malformed request into a plausible-looking price: wrong, and confident.

function readNumber(raw: unknown, what: string): number {
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    throw new Error(`Expected a finite number for "${what}".`);
  }
  return raw;
}

function readInt(raw: unknown, what: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    throw new Error(`Expected a whole number for "${what}".`);
  }
  return raw;
}

function readEnum(raw: unknown, allowed: string[], what: string): string {
  if (typeof raw !== "string" || !allowed.includes(raw)) {
    throw new Error(`Unknown ${what} "${raw}".`);
  }
  return raw;
}

// deno-lint-ignore no-explicit-any
function readSettings(raw: any): McSettings {
  const paths = readInt(raw?.paths, "paths");
  const steps = readInt(raw?.steps, "steps");
  if (paths < 2) throw new Error("Need at least two paths.");
  if (steps < 1) throw new Error("Need at least one step.");
  return {
    paths,
    steps,
    seed: readInt(raw?.seed, "seed"),
    antithetic: raw?.antithetic !== false,
  };
}

// deno-lint-ignore no-explicit-any
function readInputs(raw: any): BsmInputs {
  const inputs: BsmInputs = {
    spot: readNumber(raw?.spot, "spot"),
    strike: readNumber(raw?.strike, "strike"),
    rate: readNumber(raw?.rate, "rate"),
    volatility: readNumber(raw?.volatility, "volatility"),
    time_to_expiry: readNumber(raw?.time_to_expiry, "time_to_expiry"),
    dividend_yield: raw?.dividend_yield == null
      ? 0
      : readNumber(raw.dividend_yield, "dividend_yield"),
  };
  if (inputs.spot <= 0 || inputs.strike <= 0) {
    throw new Error("Spot and strike must be positive.");
  }
  if (inputs.volatility <= 0) throw new Error("Volatility must be positive.");
  if (inputs.time_to_expiry <= 0) throw new Error("Time must be positive.");
  return inputs;
}

// deno-lint-ignore no-explicit-any
function readAssets(raw: any): BasketAssetJson[] {
  if (!Array.isArray(raw) || raw.length < 1) {
    throw new Error("A basket needs at least one asset.");
  }
  return raw.map((a) => ({
    spot: readNumber(a?.spot, "asset spot"),
    volatility: readNumber(a?.volatility, "asset volatility"),
    weight: readNumber(a?.weight, "asset weight"),
    dividend_yield: a?.dividend_yield == null
      ? 0
      : readNumber(a.dividend_yield, "asset dividend_yield"),
  }));
}

// deno-lint-ignore no-explicit-any
function readMatrix(raw: any): number[][] {
  if (!Array.isArray(raw)) throw new Error("Expected a correlation matrix.");
  return raw.map((row) => {
    if (!Array.isArray(row)) throw new Error("Expected a correlation row.");
    return row.map((cell) => readNumber(cell, "correlation cell"));
  });
}

// deno-lint-ignore no-explicit-any
function readHestonParams(raw: any): HestonParamsJson {
  return {
    initial_variance: readNumber(raw?.initial_variance, "initial_variance"),
    long_run_variance: readNumber(raw?.long_run_variance, "long_run_variance"),
    mean_reversion: readNumber(raw?.mean_reversion, "mean_reversion"),
    vol_of_vol: readNumber(raw?.vol_of_vol, "vol_of_vol"),
    correlation: readNumber(raw?.correlation, "correlation"),
  };
}
