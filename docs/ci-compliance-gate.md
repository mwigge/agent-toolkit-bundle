# CI Compliance Gate — Recommendation

**Version**: 1.0 | **Updated**: 2026-04-17 | **Status**: Advisory (not implemented — for the pipeline team)

---

## Why

The ai_local hooks (security-guard, pii-guard, quality-gate) enforce rules at the tool-call level inside Claude Code and OpenCode. But a developer who uses raw `git commit` bypasses every hook. A CI compliance gate catches anything the hooks missed and provides a second line of defence.

This document recommends a CI job to add to the shared pipeline (`gitlab-pipelines`). Implementation ownership belongs to the pipeline team.

---

## Recommended CI job: `compliance-gate`

Run on every MR pipeline, after lint and before merge.

### 1. Secret scan (detect-secrets)

```yaml
compliance-secret-scan:
  stage: compliance
  image: python:3.12-slim
  script:
    - pip install detect-secrets
    - detect-secrets scan --all-files --baseline .secrets.baseline
    - detect-secrets audit --report .secrets.baseline
  allow_failure: false
```

Catches high-entropy strings, JWTs, AWS keys, and other patterns the hook-level regex misses. Baseline file (`.secrets.baseline`) tracks known-safe entries.

### 2. PII pattern scan

```yaml
compliance-pii-scan:
  stage: compliance
  script:
    - python3 scripts/ci-pii-scan.py --patterns ai_local/.claude/pii-patterns.json --paths src/
  allow_failure: false
```

Reuses the same `pii-patterns.json` the pii-guard hook uses. Scans changed files for PANs, IBANs, emails, national IDs. Blocks the pipeline on match.

### 3. Dependency audit

```yaml
compliance-dep-audit:
  stage: compliance
  script:
    - pip-audit --requirement requirements.txt --fix --dry-run  # Python
    - npm audit --audit-level=high                                # TypeScript
    - cargo audit                                                 # Rust
  allow_failure: false  # block on HIGH/CRITICAL CVEs
```

### 4. SBOM generation

```yaml
compliance-sbom:
  stage: compliance
  script:
    - cyclonedx-py environment -o sbom.json --format json  # Python
    - cyclonedx-npm --output-file sbom.json                 # TypeScript
  artifacts:
    paths: [sbom.json]
    expire_in: 90 days
```

Produces a CycloneDX SBOM for every build. Required by PCI-DSS 4.0 Req. 6.3.2 (software inventory) and useful for DORA Art. 5 (ICT asset management).

---

## Gap this addresses

- **PCI-DSS Req. 10.5**: the CI gate provides a pipeline-level audit trail that complements the local `events.ndjson`. Pipeline logs are retained by GitLab CI (90 days default, extendable).
- **DORA Art. 6**: dependency scanning and SBOM generation contribute to the ICT risk management framework.
- **Hook bypass**: any commit made outside Claude Code / OpenCode (raw git) is still scanned by the CI gate.

---

## References

- `ai_local/.claude/pii-patterns.json` — PII detection patterns (shared with the hook)
- `ai_local/skills/compliance/refs/pci-dss.md` — PCI-DSS mapping (Req. 10.5 gap)
- `ai_local/skills/compliance/refs/dora.md` — DORA mapping (Art. 5-6)
- [detect-secrets](https://github.com/Yelp/detect-secrets) — entropy + pattern secret scanner
- [CycloneDX](https://cyclonedx.org/) — SBOM standard
