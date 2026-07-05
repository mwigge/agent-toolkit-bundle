---
name: systematic-debugging
description: Use when a bug's root cause is unknown, a fix is not holding, you have tried the same fix twice, behaviour is intermittent, or an error reproduces inconsistently. A disciplined reproduce -> gather evidence -> single hypothesis -> minimal test -> confirm/refute -> fix -> verify loop with a hard stop-and-rethink gate after ~3 failed attempts. Orchestrates the specialised bug tools (find-bugs, investigate, diagnose, triage-frontend-issues).
---

# Systematic Debugging

A root-cause method, not a symptom-patching method. The goal is to *understand why* the defect happens before changing a line of code. Guessing and re-running is not debugging.

## The Loop

Run these steps in order. Do not skip ahead to a fix.

1. **Reproduce** — establish a reliable, minimal repro. Capture the exact command, input, environment, and the precise failing output. If you cannot reproduce it, you cannot fix it — make reproduction the first task (see *Cannot Reproduce* below).
2. **Gather evidence** — read the actual error, the full stack trace, the logs, the failing values. Look at the code path the trace names. Do not theorise before you have read the evidence. State what you *observe*, separate from what you *infer*.
3. **Form ONE hypothesis** — a single, specific, falsifiable statement of the cause: "X is null because loader Y runs after consumer Z." One hypothesis at a time. Write it down.
4. **Design a minimal test** — the smallest change or probe that will *confirm or refute* that one hypothesis (a targeted log line, a breakpoint, a unit test asserting the suspected value, a one-line experiment). The test must be able to prove you *wrong*.
5. **Run it — confirm or refute** — if refuted, discard the hypothesis (do not patch around it) and return to step 2 with the new evidence. If confirmed, you have the root cause.
6. **Fix the root cause** — change the underlying cause, not the symptom. If the fix only suppresses the symptom (swallows the error, adds a retry, special-cases the one input), you have not fixed the bug.
7. **Verify** — reproduce with the original repro from step 1 and confirm the failure is gone. Add or update a regression test that fails without the fix and passes with it. Check you did not break neighbouring behaviour.

## The Stop Gate (non-negotiable)

**After ~3 failed fix attempts, STOP.** Do not try a fourth variation of the same fix. Repeated failure means a wrong assumption is upstream of everything you have tried. When you hit the gate:

- Write down every assumption you have been treating as true (the environment, the input, which code actually runs, what "should" happen).
- Pick the most load-bearing assumption and **verify it directly** — do not assume it, prove it (print the value, check the git blame, confirm the deployed version, read the actual config).
- Question the architecture, not just the line: is the bug a symptom of a design flaw (wrong ownership of state, a race, a leaky abstraction)?
- Widen the search: `git bisect` to find the introducing commit; diff against the last known-good state; check whether the repro itself is wrong.
- If still stuck, restate the problem from scratch to a rubber duck / colleague — the act of explaining usually surfaces the false assumption.

Three failures is a signal, not a nuisance. Treat it as a hard checkpoint.

## Anti-Patterns (stop if you catch yourself doing these)

- **Shotgun debugging** — changing several things at once so you cannot tell what fixed (or broke) it. Change one variable at a time.
- **Symptom patching** — `try/except: pass`, blanket retries, `if input == the_one_broken_case`, bumping a timeout. These hide the bug; they do not fix it.
- **Fixing without reproducing** — if you never reproduced it, you cannot know you fixed it.
- **Theorising over reading** — guessing the cause before reading the stack trace and the code it names.
- **Multiple live hypotheses** — testing three theories at once. One at a time.
- **Removing the regression test** — never delete or weaken a failing test to make the suite green.

## Specialised Tools This Orchestrates

This skill is the method; these skills are the instruments. Load the one that fits the current step:

- **`/find-bugs`** — targeted static bug hunting across a code path when you need candidate causes to inspect.
- **`/investigate`** — structured, evidence-first investigation of an unknown failure (deep-dive on step 2).
- **`/diagnose`** — workflow/pipeline failure diagnosis when the fault is in CI, a build, or an integration.
- **`/triage-frontend-issues`** — browser/UI-specific reproduction and evidence gathering (console, network, DOM, state).

Reach for `/property-based-testing` or `/mutation-testing` when the bug hints at an untested invariant, and `/tdd-workflow` to drive the regression test in step 7.

## Evidence-Gathering by Layer

| Symptom | First evidence to gather |
|---------|--------------------------|
| Exception / crash | Full stack trace, the exact line, the values of the variables it names |
| Wrong output, no error | Inputs vs expected vs actual at each transformation; bisect the pipeline |
| Intermittent / flaky | What differs between pass and fail — timing, order, shared state, concurrency, external I/O |
| Works locally, fails in CI/prod | Environment delta: versions, config, env vars, data, filesystem, permissions, clock |
| Performance regression | Profile before theorising; find the actual hot path; diff against last-good |
| Fix does not hold | You fixed a symptom — return to step 2; the real cause is still live |

## Reproduction First

You cannot fix what you cannot observe. If reproduction is hard:

- Reduce the input to the smallest case that still fails (delete half, retest, repeat — a binary search on the input).
- Pin the environment: exact versions, seed any RNG, freeze the clock, isolate from network.
- For intermittent bugs, run in a loop until it fails and capture full state at the moment of failure; add logging that survives the failure.
- Capture the failing case as an automated test as soon as you have it — it becomes the regression test in step 7.

## Definition of Done

- [ ] The failure was reproduced reliably before any fix was attempted
- [ ] A single confirmed root-cause hypothesis is written down (not a guess)
- [ ] The fix addresses the cause, not the symptom
- [ ] The original repro now passes
- [ ] A regression test fails without the fix and passes with it
- [ ] No neighbouring behaviour was broken (surrounding tests green)
- [ ] If the stop gate was hit: the false assumption is documented
