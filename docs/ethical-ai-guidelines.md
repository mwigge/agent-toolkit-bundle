# Ethical AI Guidelines — AI-Assisted Development

**Version**: 1.0 | **Updated**: 2026-04-17

Five principles for responsible use of AI tools in our development workflow. These are not aspirational — each one maps to an existing enforcement mechanism or team convention.

---

## 1. Human-in-the-loop

Security-critical changes require human review before commit. No agent output is auto-merged — ever. The orchestrator (build agent) never writes feature code; it decides, delegates, and signs off. Every commit is a human decision.

**Enforcement**: AGENTS.md delegation protocol — "the primary agent is an orchestrator, not an implementor."

## 2. Accountability chain

Every line of shipped code has a named human behind it:

```
model suggests → human reviews → human commits → human pushes
```

The model's suggestion is a draft. The human who commits owns the outcome. The human who pushes owns the deployment. There is no step where accountability is ambiguous.

**Enforcement**: git history requires a human author on every commit; `no-ai-attribution` hook ensures the model is never listed as a co-author.

## 3. Hallucination acknowledgement

AI-generated code may be plausible but incorrect. The model can produce code that compiles, passes a smoke test, and is still subtly wrong — wrong business logic, wrong edge case handling, wrong security assumption. The primary mitigation is **test-driven development**: every `@coder-*` agent writes a failing test before writing the implementation. If the test is wrong, the implementation is wrong — and the human catches it in review.

**Enforcement**: TDD is non-negotiable in every `@coder-*` agent definition. `quality-gate` hook runs lint + type checks + security scan at end-of-turn.

## 4. Bias awareness

Code suggestions may reflect biases present in the model's training data. This can manifest as:
- Defaulting to English-only string handling
- Generating examples with culturally narrow assumptions
- Recommending patterns that favour one tech stack over another without evidence

Security reviews (`@security` agent) should check for demographic or geographic bias in generated logic, especially in code that touches user-facing features, fraud scoring, or access control.

**Enforcement**: `@security` agent loads `/compliance` and `/security-review` simultaneously; bias is a review lens, not an automated gate.

## 5. Augmentation principle

AI tools augment engineering judgement; they do not replace it. The orchestrator reads, plans, and delegates — it does not make architecture decisions unilaterally. The `@architect` agent produces design documents for human review, not approved designs. The `@coder-*` agents produce code for human review, not shipped features.

**Enforcement**: AGENTS.md — "the primary agent is an orchestrator, not an implementor." `@architect` has `bash: deny` — it cannot execute, only design.

---

## References

- `ai_local/AGENTS.md` — delegation protocol and non-negotiable rules
- `ai_local/.claude/agents/` — agent definitions with tool permissions
- `ai_local/docs/ai-act-assessment.md` — EU AI Act risk classification
- `ai_local/docs/data-classification.md` — data handling requirements
