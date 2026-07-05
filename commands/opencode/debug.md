# /debug — Systematic Root-Cause Debugging

Find and fix the *root cause* of the reported problem. The symptom (error message, failing test, or description) is the command argument. Do not patch symptoms; do not guess-and-rerun.

## Skill in Effect

- **`/systematic-debugging`** — the full method and the 3-failed-attempts stop gate. Load it and follow the loop.

Reach for the specialised instruments as each step needs them: `/find-bugs`, `/investigate`, `/diagnose` (CI/pipeline/build failures), `/triage-frontend-issues` (browser/UI). Consider handing the investigation to `@debugger` for a focused, write-restricted run.

## Steps

### 1. Reproduce

Establish a reliable, minimal repro. Capture the exact command, input, environment, and the precise failing output. If it does not reproduce, make reproduction the first task (reduce the input, pin versions, loop until an intermittent failure surfaces).

### 2. Gather evidence

Read the real error, the full stack trace, the logs, and the failing values. Open the code path the trace names. Separate what you **observe** from what you **infer**. Do not theorise before reading.

### 3. Form ONE hypothesis

State a single, specific, falsifiable cause and write it down. One at a time.

### 4. Design a minimal test

The smallest probe that can **confirm or refute** that one hypothesis — a targeted log line, a breakpoint, a unit test asserting the suspected value, a one-line experiment. It must be able to prove you wrong.

### 5. Confirm or refute

- **Refuted** -> discard the hypothesis (do not patch around it) and return to step 2 with the new evidence.
- **Confirmed** -> you have the root cause.

### 6. Stop gate

If you have made **~3 failed attempts**, STOP. List every assumption, verify the most load-bearing one **directly** (prove it — do not assume it), question the architecture not just the line, and widen the search (`git bisect`, diff against last-known-good, check whether the repro itself is wrong).

### 7. Fix the cause and verify

Change the underlying cause, not the symptom. Then:
- Re-run the original repro from step 1 — the failure must be gone.
- Add a regression test that **fails without the fix and passes with it**.
- Confirm surrounding tests stay green.

## Report

```
## Debug — <symptom>
Repro: <exact command / input / env>
Root cause: <confirmed cause + the evidence that confirmed it>
Hypotheses tested: <each, confirmed|refuted>
Stop gate hit? <no | yes — false assumption was: ...>
Fix: <what changed at the cause>
Regression test: <added test that fails without the fix>
Verify: original repro now passes; neighbouring tests green
```
