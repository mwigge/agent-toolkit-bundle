#!/usr/bin/env python3
"""model-report.py — aggregate model-usage.ndjson into a tiered cost/token report.

Requires Python 3.10+.

Usage:
    python3 model-report.py [--cwd PATH] [--since DAYS] [--format json|table] [scope]

Scopes: today (1d) | week (7d) | sprint (14d) | block (30d)

Reads:
    <cwd>/.claude/logs/model-usage.ndjson

Output:
    JSON or table report by tier with totals and routing health check.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ── Constants ─────────────────────────────────────────────────────────────────

SCOPE_DAYS: dict[str, int] = {
    "today": 1,
    "week": 7,
    "sprint": 14,   # 2-week sprint (FIX-8: was 7)
    "block": 30,
}

# Tier cost map — must stay in sync with TIER_MAP in model-usage.ts and model-usage-summary.sh
# Keys are prefix-matched against modelID (longest prefix wins).
# Cost is per 1M output tokens in USD. 0 = local.
TIER_COST_MAP: dict[str, tuple[str, float]] = {
    "devstral":          ("primary",  0.0),
    "llama3.3":          ("primary",  0.0),
    "gemma4":            ("primary",  0.0),
    "qwen2.5-coder":     ("utility",  0.0),
    "claude-opus-4":     ("sign-off", 75.0),
    "claude-opus-3":     ("sign-off", 75.0),
    "claude-sonnet-4":   ("sign-off", 15.0),
    "claude-sonnet-3":   ("sign-off", 15.0),
    "claude-haiku-4":    ("sign-off", 1.25),
    "claude-haiku-3":    ("sign-off", 1.25),
    "gpt-4o":            ("sign-off", 15.0),
    "o3":                ("sign-off", 60.0),
    "gemini-2.5-pro":    ("sign-off", 10.0),
}

# Default assumed cloud rate for savings estimate (used when tier is unknown)
ASSUMED_CLOUD_RATE_USD_PER_1M: float = 15.0


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Aggregate model usage by tier")
    p.add_argument("--cwd", default=".", help="Project root (default: .)")
    p.add_argument("--since", type=int, default=None,
                   help="Only entries within N days")
    p.add_argument("--format", choices=["json", "table"], default="json")
    p.add_argument("--cloud-rate", type=float, default=ASSUMED_CLOUD_RATE_USD_PER_1M,
                   help="Cloud cost per 1M tokens for savings estimate (default: 15.0)")
    p.add_argument("scope", nargs="?", default=None,
                   help="Shorthand scope: today / week / sprint / block")
    return p.parse_args()


def cutoff_dt(since_days: int | None, scope: str | None) -> datetime | None:
    days = since_days
    if scope and scope in SCOPE_DAYS:
        days = SCOPE_DAYS[scope]
    if days is None:
        return None
    return datetime.now(tz=timezone.utc) - timedelta(days=days)


# ── NDJSON reader (FIX-7: stream, not read_text) ─────────────────────────────

def read_ndjson(path: Path) -> list[dict]:
    if not path.exists():
        return []
    entries: list[dict] = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


# ── Aggregation ───────────────────────────────────────────────────────────────

def aggregate(entries: list[dict], cutoff: datetime | None, cloud_rate: float) -> dict:
    tiers: dict[str, dict] = defaultdict(lambda: {
        "calls": 0,
        "tokens_in": 0,
        "tokens_out": 0,
        "tokens_reasoning": 0,
        "tokens_cache_read": 0,
        "cost_usd": 0.0,
    })
    sessions: set[str] = set()
    compactions: int = 0

    for e in entries:
        if e.get("event") == "compaction":
            compactions += 1
            # FIX PY-O1: associate compaction with its session
            sessions.add(e.get("session", "compaction-unknown"))
            continue
        if e.get("event") != "model-usage":
            continue

        ts_str = e.get("ts", "")
        if cutoff and ts_str:
            try:
                ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                if ts < cutoff:
                    continue
            except ValueError:
                pass

        tier = e.get("tier", "unknown")
        tok  = e.get("tokens", {})
        tiers[tier]["calls"]             += 1
        tiers[tier]["tokens_in"]         += tok.get("input", 0)
        tiers[tier]["tokens_out"]        += tok.get("output", 0)
        tiers[tier]["tokens_reasoning"]  += tok.get("reasoning", 0)
        tiers[tier]["tokens_cache_read"] += tok.get("cache_read", 0)
        tiers[tier]["cost_usd"]          += e.get("cost_usd", 0.0)
        sessions.add(e.get("session", ""))

    total_tokens = sum(v["tokens_in"] + v["tokens_out"] for v in tiers.values())
    total_cost   = sum(v["cost_usd"] for v in tiers.values())

    sign_off_tokens = (
        tiers["sign-off"]["tokens_in"] + tiers["sign-off"]["tokens_out"]
        if "sign-off" in tiers else 0
    )
    # FIX PY-M2: explicit zero check, not `or 1`
    pct_cloud = (sign_off_tokens / total_tokens * 100) if total_tokens > 0 else 0.0

    if pct_cloud < 10:
        health = "ok"
        health_msg = "✅ Routing healthy — sign-off tier < 10% of tokens"
    elif pct_cloud < 25:
        health = "warn"
        health_msg = f"⚠️  Sign-off tier at {pct_cloud:.1f}% — review if cloud calls are justified"
    else:
        health = "alert"
        health_msg = f"🔴 Sign-off tier at {pct_cloud:.1f}% — routing review recommended"

    utility_tokens = (
        tiers["utility"]["tokens_in"] + tiers["utility"]["tokens_out"]
        if "utility" in tiers else 0
    )
    cloud_cost_avoided = (utility_tokens / 1_000_000) * cloud_rate

    return {
        "by_tier": dict(tiers),
        "totals": {
            "sessions": len(sessions),
            "compaction_events": compactions,
            "tokens": total_tokens,
            "cost_usd": round(total_cost, 6),
        },
        "routing_health": {
            "status": health,
            "sign_off_pct": round(pct_cloud, 2),
            "message": health_msg,
        },
        "compaction_savings": {
            "utility_tokens": utility_tokens,
            "assumed_cloud_rate_per_1m": cloud_rate,
            "estimated_cloud_cost_avoided_usd": round(cloud_cost_avoided, 4),
        },
    }


# ── Table printer ─────────────────────────────────────────────────────────────

def print_table(report: dict) -> None:
    by_tier = report["by_tier"]
    totals  = report["totals"]
    total_t = totals["tokens"]  # may be 0 — handled explicitly below

    header = (
        f"{'Tier':<12} {'Calls':>6} {'Tok In':>10} {'Tok Out':>10} "
        f"{'Reasoning':>10} {'Cost USD':>10} {'% Total':>8}"
    )
    sep = "-" * len(header)
    print(sep)
    print(header)
    print(sep)

    for tier in ("utility", "primary", "sign-off", "unknown"):
        if tier not in by_tier:
            continue
        b = by_tier[tier]
        tok_total = b["tokens_in"] + b["tokens_out"]
        pct = (tok_total / total_t * 100) if total_t > 0 else 0.0
        print(
            f"{tier:<12} {b['calls']:>6} {b['tokens_in']:>10,} {b['tokens_out']:>10,} "
            f"{b['tokens_reasoning']:>10,} {b['cost_usd']:>10.4f} {pct:>7.1f}%"
        )

    total_calls = sum(b["calls"]      for b in by_tier.values())
    total_in    = sum(b["tokens_in"]  for b in by_tier.values())
    total_out   = sum(b["tokens_out"] for b in by_tier.values())
    total_reas  = sum(b["tokens_reasoning"] for b in by_tier.values())
    print(sep)
    print(
        f"{'TOTAL':<12} {total_calls:>6} {total_in:>10,} {total_out:>10,} "
        f"{total_reas:>10,} {totals['cost_usd']:>10.4f} {'100.0%':>8}"
    )
    print(sep)
    print(f"\nSessions: {totals['sessions']}  |  Compaction events: {totals['compaction_events']}")
    print(f"\nRouting:  {report['routing_health']['message']}")
    sav = report["compaction_savings"]
    print(
        f"Savings:  Utility tier handled {sav['utility_tokens']:,} tokens → "
        f"estimated ${sav['estimated_cloud_cost_avoided_usd']:.4f} cloud cost avoided "
        f"(at ${sav['assumed_cloud_rate_per_1m']:.2f}/1M tokens)"
    )


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    args   = parse_args()
    cwd    = Path(args.cwd)
    cutoff = cutoff_dt(args.since, args.scope)

    usage_file = cwd / ".claude" / "logs" / "model-usage.ndjson"
    entries    = read_ndjson(usage_file)
    report     = aggregate(entries, cutoff, args.cloud_rate)

    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        print_table(report)


if __name__ == "__main__":
    main()
