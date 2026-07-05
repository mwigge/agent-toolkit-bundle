# /docs — Generate or Update Documentation

Produce accurate documentation for the target. The target and optional doc type are the command argument.

## Skill in Effect

- **`/documentation`** — Diataxis framework (tutorial / how-to / reference / explanation), ADR format, RFC template, CHANGELOG conventions.

## Steps

### 1. Determine what and for whom

Identify the documentation type and its audience — they are not interchangeable:

| Type | Answers | Audience |
|------|---------|----------|
| **Tutorial** | "teach me from zero" | newcomer |
| **How-to guide** | "how do I accomplish X" | task-focused user |
| **Reference** | "what exactly does this API do" | someone mid-task |
| **Explanation** | "why is it built this way" | someone forming a mental model |
| **ADR** | "what did we decide and why" | future maintainers |

Pick the right type; do not blend a tutorial and a reference in one document.

### 2. Read the source of truth

Documentation must match reality. Read the actual code, signatures, config, and existing docs. Extract the real names, parameters, return types, defaults, errors, and env vars — never invent an API or an option. If code and existing docs disagree, the code wins; note the drift.

### 3. Match the repo's existing conventions

Study a few existing docs first (structure, heading style, code-fence language tags, tone, link style, admonitions). Follow them exactly. For code documentation, use the project's docstring/JSDoc convention consistently.

### 4. Write

- **README**: what it is, why, install, minimal usage example that actually runs, links to deeper docs.
- **Reference/API**: every public function/endpoint — signature, params (name, type, required, default), returns, raises/errors, one example.
- **Docstrings/JSDoc**: describe behaviour, params, returns, and raised errors — the *what* and *why*, not a restatement of the code.
- **ADR**: context -> decision -> consequences (and alternatives considered).
- Keep examples copy-pasteable and correct; prefer one working example over three vague ones.

### 5. Verify

- Every code example runs / type-checks as written.
- Every referenced symbol, path, flag, and env var exists in the code.
- Every internal link resolves.
- No stale references left from a previous version.

### 6. Report

```
## Docs — <target>
Type: <tutorial | how-to | reference | explanation | ADR | docstrings>
Files: <created / updated>
Verified: examples run, symbols/paths/links resolve
Drift found: <any code/doc mismatches corrected, or "none">
```

Do not add AI attribution anywhere in the generated documentation.
