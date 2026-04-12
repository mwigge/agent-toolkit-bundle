---
description: Report tiered model usage — tokens, cost, and tier efficiency across sessions
---

Run the model usage report for this project. Show token counts and cost by tier (utility / primary / sign-off) across all recorded sessions. Optionally scope to a sprint or block.

Usage:
  /model-report              — all sessions in this project
  /model-report today        — sessions started today
  /model-report week         — sessions started in the last 7 days
  /model-report sprint       — same as week (one sprint = one week)
  /model-report block        — sessions started in the last 30 days

Steps:
1. Run the aggregation script:
   ```
   python3 ~/.config/opencode/scripts/model-report.py --cwd "$PWD" $ARGUMENTS
   ```
2. Parse the JSON output and present a formatted table:

   | Tier      | Calls | Tokens In | Tokens Out | Reasoning | Cost (USD) | % of Total Tokens |
   |-----------|-------|-----------|------------|-----------|------------|-------------------|
   | utility   |       |           |            |           | $0.00      |                   |
   | primary   |       |           |            |           | $0.00      |                   |
   | sign-off  |       |           |            |           |            |                   |
   | **TOTAL** |       |           |            |           |            | 100%              |

3. Print routing health check:
   - If sign-off tokens < 10% of total: ✅ routing is working correctly
   - If sign-off tokens 10–25%: ⚠️  consider whether cloud calls are justified
   - If sign-off tokens > 25%: 🔴 review agent routing — too much cloud spend

4. Print compaction efficiency:
   - Count compaction events (utility tier)
   - Estimate cloud cost avoided: (utility compaction tokens) × $15 / 1M

5. If MemPalace is available, search for historical model-usage entries to show trend:
   Use mempalace_search with query "SESSION_USAGE" and wing "wing_ai_dev"
   Show week-over-week trend if enough data points exist.
