/**
 * result_type.ts — Result<T, E> implementation using discriminated unions.
 *
 * No fp-ts dependency. Provides:
 *   - Result<T, E> type
 *   - ok() and err() constructors
 *   - map, flatMap, mapError, fold helpers
 *   - fromThrowable — wrap sync throwing functions
 *   - fromPromise — wrap async throwing functions
 *   - collect — combine multiple Results
 */

// ---------------------------------------------------------------------------
// 1. Core Types
// ---------------------------------------------------------------------------

export type Ok<T> = { readonly ok: true; readonly value: T };
export type Err<E> = { readonly ok: false; readonly error: E };
export type Result<T, E> = Ok<T> | Err<E>;


// ---------------------------------------------------------------------------
// 2. Constructors
// ---------------------------------------------------------------------------

export function ok<T>(value: T): Ok<T> {
  return { ok: true, value };
}

export function err<E>(error: E): Err<E> {
  return { ok: false, error };
}


// ---------------------------------------------------------------------------
// 3. Type Guards
// ---------------------------------------------------------------------------

export function isOk<T, E>(result: Result<T, E>): result is Ok<T> {
  return result.ok;
}

export function isErr<T, E>(result: Result<T, E>): result is Err<E> {
  return !result.ok;
}


// ---------------------------------------------------------------------------
// 4. Transformations
// ---------------------------------------------------------------------------

export function map<T, U, E>(
  result: Result<T, E>,
  fn: (value: T) => U,
): Result<U, E> {
  return result.ok ? ok(fn(result.value)) : result;
}

export function mapError<T, E, F>(
  result: Result<T, E>,
  fn: (error: E) => F,
): Result<T, F> {
  return result.ok ? result : err(fn(result.error));
}

export function flatMap<T, U, E>(
  result: Result<T, E>,
  fn: (value: T) => Result<U, E>,
): Result<U, E> {
  return result.ok ? fn(result.value) : result;
}

export function fold<T, E, R>(
  result: Result<T, E>,
  onOk: (value: T) => R,
  onErr: (error: E) => R,
): R {
  return result.ok ? onOk(result.value) : onErr(result.error);
}

export function getOrElse<T, E>(result: Result<T, E>, fallback: T): T {
  return result.ok ? result.value : fallback;
}

export function getOrThrow<T, E>(result: Result<T, E>): T {
  if (result.ok) return result.value;
  const error = result.error;
  if (error instanceof Error) throw error;
  throw new Error(String(error));
}


// ---------------------------------------------------------------------------
// 5. Constructors from throwing code
// ---------------------------------------------------------------------------

export function fromThrowable<T, E = Error>(
  fn: () => T,
  mapErr?: (e: unknown) => E,
): Result<T, E> {
  try {
    return ok(fn());
  } catch (e) {
    return err(mapErr ? mapErr(e) : (e as E));
  }
}

export async function fromPromise<T, E = Error>(
  promise: Promise<T>,
  mapErr?: (e: unknown) => E,
): Promise<Result<T, E>> {
  try {
    return ok(await promise);
  } catch (e) {
    return err(mapErr ? mapErr(e) : (e as E));
  }
}


// ---------------------------------------------------------------------------
// 6. Combining Results
// ---------------------------------------------------------------------------

export function collect<T, E>(results: Result<T, E>[]): Result<T[], E> {
  const values: T[] = [];
  for (const result of results) {
    if (!result.ok) return result;
    values.push(result.value);
  }
  return ok(values);
}

// Collect all errors, not just the first
export function collectAll<T, E>(results: Result<T, E>[]): Result<T[], E[]> {
  const values: T[] = [];
  const errors: E[] = [];

  for (const result of results) {
    if (result.ok) {
      values.push(result.value);
    } else {
      errors.push(result.error);
    }
  }

  return errors.length > 0 ? err(errors) : ok(values);
}


// ---------------------------------------------------------------------------
// 7. Domain Error types — use with Result
// ---------------------------------------------------------------------------

export type DomainError =
  | { readonly code: "NOT_FOUND"; readonly id: string }
  | { readonly code: "VALIDATION_ERROR"; readonly field: string; readonly message: string }
  | { readonly code: "CONFLICT"; readonly message: string }
  | { readonly code: "INTERNAL_ERROR"; readonly cause: unknown };


// ---------------------------------------------------------------------------
// 8. Example usage
// ---------------------------------------------------------------------------

function parseExperimentId(raw: string): Result<string, DomainError> {
  if (!raw.match(/^[0-9a-f-]{36}$/i)) {
    return err({
      code: "VALIDATION_ERROR",
      field: "id",
      message: `"${raw}" is not a valid UUID`,
    });
  }
  return ok(raw);
}

async function fetchExperiment(
  id: string,
): Promise<Result<{ id: string; name: string }, DomainError>> {
  return fromPromise(
    fetch(`https://api.chaos.internal/experiments/${id}`).then((r) => {
      if (r.status === 404) throw Object.assign(new Error("not found"), { status: 404 });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json() as Promise<{ id: string; name: string }>;
    }),
    (e) => ({
      code: "INTERNAL_ERROR" as const,
      cause: e,
    }),
  );
}

// Pipeline example
async function getExperimentName(rawId: string): Promise<Result<string, DomainError>> {
  const idResult = parseExperimentId(rawId);
  if (!idResult.ok) return idResult;

  const fetchResult = await fetchExperiment(idResult.value);
  return map(fetchResult, (exp) => exp.name);
}

// Usage
const example = parseExperimentId("550e8400-e29b-41d4-a716-446655440000");
const name = fold(
  example,
  (id) => `Valid ID: ${id}`,
  (e) => `Error [${e.code}]`,
);
console.log(name);

export type { DomainError as AppError };
