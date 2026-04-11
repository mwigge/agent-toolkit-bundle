#!/usr/bin/env python3
"""
pir_scaffold.py — Generate a pre-populated Post-Incident Review (PIR) markdown file.

Usage:
    python pir_scaffold.py --title "Payment service outage" --sev SEV1 --date 2026-04-05

Output:
    pir-2026-04-05-payment-service-outage.md

Exit codes:
    0  Success
    1  Error
"""

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

def slugify(text: str) -> str:
    """Convert a title to a URL-safe slug."""
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")

def validate_sev(value: str) -> str:
    upper = value.upper()
    if upper not in {"SEV1", "SEV2", "SEV3", "SEV4"}:
        raise argparse.ArgumentTypeError(f"Invalid severity: {value}. Must be SEV1, SEV2, SEV3, or SEV4.")
    return upper

def validate_date(value: str) -> str:
    try:
        datetime.strptime(value, "%Y-%m-%d")
        return value
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid date: {value}. Expected format: YYYY-MM-DD")

def pir_deadline(sev: str, incident_date: str) -> str:
    dt = datetime.strptime(incident_date, "%Y-%m-%d")
    if sev == "SEV1":
        from datetime import timedelta
        deadline = dt + timedelta(days=2)
        return f"{deadline.strftime('%Y-%m-%d')} (48h SLA for {sev})"
    elif sev == "SEV2":
        from datetime import timedelta
        deadline = dt + timedelta(days=7)
        return f"{deadline.strftime('%Y-%m-%d')} (1-week SLA for {sev})"
    else:
        return "No mandatory deadline — schedule at team discretion"

def render_pir(title: str, sev: str, date: str) -> str:
    slug = slugify(title)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    deadline = pir_deadline(sev, date)

    sev_descriptions = {
        "SEV1": "Total service outage or data loss / security breach risk",
        "SEV2": "Major feature broken, >20% of users affected, or SLO breach",
        "SEV3": "Degraded performance, workaround exists, <20% of users affected",
        "SEV4": "Minor issue, cosmetic, no user impact",
    }

    return f"""# Post-Incident Review: {title}

> **Generated**: {generated_at}
> **PIR due**: {deadline}

---

## Incident Summary

| Field | Value |
|-------|-------|
| **Title** | {title} |
| **Severity** | {sev} — {sev_descriptions[sev]} |
| **Date of incident** | {date} |
| **Date detected** | {date} TBD:HH:MM UTC |
| **Date resolved** | TBD |
| **Duration** | TBD |
| **Incident Commander** | [Name, @handle] |
| **Scribe** | [Name, @handle] |
| **Status** | Draft — pending review |

---

## Impact Assessment

| Dimension | Description |
|-----------|-------------|
| **Users affected** | [Number or percentage] |
| **Services affected** | [List of service names] |
| **Data affected** | [None / Describe scope] |
| **Error budget consumed** | [X% of monthly budget] |
| **Estimated business impact** | [Revenue / support cost / SLA credit] |

---

## Timeline

All times UTC. Be precise — use log timestamps, not memory.

| Time (UTC) | Event |
|-----------|-------|
| {date} HH:MM | First symptom observed (describe the observable symptom, not the cause) |
| {date} HH:MM | Alert fired: [alert name and threshold] |
| {date} HH:MM | Incident declared by [name] |
| {date} HH:MM | Incident Commander assigned: [name] |
| {date} HH:MM | Initial diagnosis: [what was suspected] |
| {date} HH:MM | Mitigation attempted: [action taken] |
| {date} HH:MM | [Mitigation succeeded / failed] — [observable result] |
| {date} HH:MM | Root cause confirmed: [one sentence] |
| {date} HH:MM | Service restored to normal operation |
| {date} HH:MM | Incident resolved and declared closed |

---

## Root Cause Analysis — 5 Whys

**Presenting symptom**: [Describe what users / monitoring observed]

| Why # | Question | Answer |
|-------|----------|--------|
| Why 1 | Why did users experience [symptom]? | [Answer] |
| Why 2 | Why did [answer 1] happen? | [Answer] |
| Why 3 | Why did [answer 2] happen? | [Answer] |
| Why 4 | Why did [answer 3] happen? | [Answer] |
| Why 5 | Why did [answer 4] happen? | [Root cause] |

**Root cause summary**: [One to two sentences describing the systemic root cause]

---

## Contributing Factors

Factors that made the incident worse or harder to detect/resolve. These are not root causes but should be addressed.

- [ ] [Factor 1, e.g. "Alert threshold was set too high — did not fire until 10% error rate"]
- [ ] [Factor 2, e.g. "Runbook for this service was outdated — missing rollback steps"]
- [ ] [Factor 3, e.g. "On-call engineer had insufficient context on this service"]
- [ ] [Add more as needed]

---

## What Went Well

> This section is not optional. Identify genuine strengths to reinforce good practices.

- [e.g. "Detection-to-acknowledgement time was under 3 minutes"]
- [e.g. "Rollback procedure worked correctly on first attempt"]
- [e.g. "Clear communication kept stakeholders informed throughout"]

---

## Action Items

All action items must have an owner and a due date. No ownerless action items.

| # | Action | Owner | Due date | Status |
|---|--------|-------|----------|--------|
| 1 | [Specific, verifiable action — not "improve monitoring"] | [@owner] | [YYYY-MM-DD] | Open |
| 2 | [e.g. "Add circuit breaker to payment-client with 5s timeout"] | [@owner] | [YYYY-MM-DD] | Open |
| 3 | [e.g. "Update runbook: add rollback procedure for DB migration failures"] | [@owner] | [YYYY-MM-DD] | Open |
| 4 | [e.g. "Add alert: error budget burn rate >6x for 6h window"] | [@owner] | [YYYY-MM-DD] | Open |

---

## Lessons Learned

> For sharing in engineering all-hands or newsletter. Write for an audience who was not involved.

[2–4 paragraphs summarising what happened, what caused it, and what the team is doing to prevent recurrence. Use plain language. Avoid blame language. Link to the action items above.]

---

## Appendix

### Alert that fired

```
[Paste alert query and threshold here]
```

### Relevant log excerpts

```
[Paste key log lines here with timestamps]
```

### Links

- Incident Slack channel: [link]
- Dashboard at time of incident: [link]
- Deployment that preceded incident: [link]
- Related Jira tickets: [<PROJ>-XXX]
"""

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a pre-populated Post-Incident Review markdown file"
    )
    parser.add_argument("--title", required=True, help="Incident title (e.g. 'Payment service outage')")
    parser.add_argument("--sev", required=True, type=validate_sev, help="Severity: SEV1, SEV2, SEV3, or SEV4")
    parser.add_argument("--date", required=True, type=validate_date, help="Incident date in YYYY-MM-DD format")
    parser.add_argument("--output-dir", default=".", help="Directory to write the PIR file (default: current dir)")

    args = parser.parse_args()

    slug = slugify(args.title)
    filename = f"pir-{args.date}-{slug}.md"
    output_path = Path(args.output_dir) / filename

    if output_path.exists():
        print(f"ERROR: file already exists: {output_path}", file=sys.stderr)
        sys.exit(1)

    content = render_pir(args.title, args.sev, args.date)

    output_path.write_text(content, encoding="utf-8")
    print(f"Created: {output_path}")
    print(f"PIR due: {pir_deadline(args.sev, args.date)}")

if __name__ == "__main__":
    main()
