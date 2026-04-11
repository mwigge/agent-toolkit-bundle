/**
 * types_example.ts — Advanced TypeScript type patterns.
 *
 * Demonstrates:
 *   - Branded types
 *   - Discriminated unions
 *   - Conditional types with `infer`
 *   - Template literal types
 *   - `satisfies` operator
 *   - `const` assertions
 */

// ---------------------------------------------------------------------------
// 1. Branded Types — prevent accidental type mixing
// ---------------------------------------------------------------------------

type Brand<T, B extends string> = T & { readonly __brand: B };

type ExperimentId = Brand<string, "ExperimentId">;
type UserId = Brand<string, "UserId">;
type Milliseconds = Brand<number, "Milliseconds">;

function createExperimentId(raw: string): ExperimentId {
  if (!raw.match(/^[0-9a-f-]{36}$/i)) {
    throw new Error(`Invalid ExperimentId: ${raw}`);
  }
  return raw as ExperimentId;
}

function createMilliseconds(n: number): Milliseconds {
  if (n < 0) throw new RangeError("Duration cannot be negative");
  return n as Milliseconds;
}

// This would be a type error — cannot mix UserId and ExperimentId:
// const id: ExperimentId = "user-123" as UserId; // ✗

// ---------------------------------------------------------------------------
// 2. Discriminated Unions — exhaustive pattern matching
// ---------------------------------------------------------------------------

type ExperimentStatus =
  | { readonly kind: "pending" }
  | { readonly kind: "running"; readonly startedAt: Date }
  | { readonly kind: "completed"; readonly success: boolean; readonly durationMs: Milliseconds }
  | { readonly kind: "failed"; readonly error: string; readonly durationMs: Milliseconds }
  | { readonly kind: "aborted" };

function describeStatus(status: ExperimentStatus): string {
  switch (status.kind) {
    case "pending":
      return "Waiting to start";
    case "running":
      return `Running since ${status.startedAt.toISOString()}`;
    case "completed":
      return status.success
        ? `Passed in ${status.durationMs}ms`
        : `Failed in ${status.durationMs}ms`;
    case "failed":
      return `Error: ${status.error}`;
    case "aborted":
      return "Aborted by operator";
    default: {
      // Exhaustiveness check — TS will error if a case is missing
      const _exhaustive: never = status;
      return _exhaustive;
    }
  }
}

// ---------------------------------------------------------------------------
// 3. Conditional Types + `infer`
// ---------------------------------------------------------------------------

type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;
type UnwrapArray<T> = T extends Array<infer U> ? U : T;

// Extract the return type of any function
type ReturnOf<T extends (...args: never[]) => unknown> =
  T extends (...args: never[]) => infer R ? R : never;

// Flatten nested arrays one level
type Flatten<T> = T extends Array<infer Item>
  ? Item extends Array<infer Inner>
    ? Inner
    : Item
  : T;

// Deep readonly
type DeepReadonly<T> = T extends object
  ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
  : T;

type ReadonlyExperiment = DeepReadonly<{
  id: string;
  config: { timeout: number; targets: string[] };
}>;

// ---------------------------------------------------------------------------
// 4. Template Literal Types
// ---------------------------------------------------------------------------

type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
type ApiVersion = "v1" | "v2";
type ResourceName = "experiments" | "reports" | "probes";

type ApiEndpoint = `/${ApiVersion}/${ResourceName}`;
// → "/v1/experiments" | "/v1/reports" | ... | "/v2/probes"

type EventName<T extends string> = `${T}:created` | `${T}:updated` | `${T}:deleted`;
type ExperimentEvent = EventName<"experiment">;
// → "experiment:created" | "experiment:updated" | "experiment:deleted"

type MetricKey = `resilience_${string}_${string}_${"total" | "seconds" | "bytes"}`;

function emitMetric(key: MetricKey, value: number): void {
  console.log(`metric: ${key}=${value}`);
}

// ---------------------------------------------------------------------------
// 5. `satisfies` operator — validate shape without widening
// ---------------------------------------------------------------------------

type Config = {
  readonly timeoutMs: number;
  readonly retries: number;
  readonly endpoint: string;
};

// `satisfies` checks the type but preserves the literal type of values
const defaultConfig = {
  timeoutMs: 5000,
  retries: 3,
  endpoint: "https://api.chaos.internal",
} satisfies Config;

// defaultConfig.timeoutMs is still `number`, not widened to `Config["timeoutMs"]`

// ---------------------------------------------------------------------------
// 6. `const` Assertions
// ---------------------------------------------------------------------------

const EXPERIMENT_STATES = ["pending", "running", "completed", "failed", "aborted"] as const;
type ExperimentState = (typeof EXPERIMENT_STATES)[number];

const SEVERITY_LEVELS = {
  low: 1,
  medium: 2,
  high: 3,
  critical: 4,
} as const;
type Severity = keyof typeof SEVERITY_LEVELS;
type SeverityValue = (typeof SEVERITY_LEVELS)[Severity]; // 1 | 2 | 3 | 4

function compareSeverity(a: Severity, b: Severity): number {
  return SEVERITY_LEVELS[a] - SEVERITY_LEVELS[b];
}

// ---------------------------------------------------------------------------
// 7. Utility type composition
// ---------------------------------------------------------------------------

type CreateExperimentRequest = Pick<
  { id: string; name: string; blastRadius: number; config: object; createdAt: Date },
  "name" | "blastRadius" | "config"
>;

type UpdateExperimentRequest = Partial<CreateExperimentRequest> & {
  readonly id: ExperimentId;
};

type ApiResponse<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { code: string; message: string } };

function isSuccess<T>(response: ApiResponse<T>): response is { ok: true; data: T } {
  return response.ok;
}

// ---------------------------------------------------------------------------
// Usage
// ---------------------------------------------------------------------------

const id = createExperimentId("550e8400-e29b-41d4-a716-446655440000");
const duration = createMilliseconds(1234);

const status: ExperimentStatus = {
  kind: "completed",
  success: true,
  durationMs: duration,
};

console.log(describeStatus(status));
emitMetric("resilience_api_latency_seconds", 0.123);

const states: ExperimentState[] = [...EXPERIMENT_STATES];
console.log(states);
