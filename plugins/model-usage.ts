import type { Plugin } from "@opencode-ai/plugin"
import type { Event } from "@opencode-ai/sdk"
import { appendFileSync, mkdirSync, readFileSync, realpathSync } from "fs"
import { join, dirname } from "path"
import { execFile } from "child_process"
import { homedir } from "os"
import { fileURLToPath } from "url"

// model-usage.ts — tiered model usage instrumentation
// SPDX-License-Identifier: Apache-2.0
//
// Listens on the OpenCode `event` hook for `message.updated` events.
// On every assistant message completion records: tier, model, provider,
// token counts (input/output/reasoning/cache), and cost in USD.
// On `session.idle` / `session.closed` writes a per-session summary to
// model-summary.ndjson and fires a fire-and-forget write to MemPalace
// for cross-session sprint/block analysis.
//
// Output files (relative to project cwd):
//   .claude/logs/model-usage.ndjson        — one entry per assistant message
//   .claude/logs/model-summary.ndjson      — one entry per session (on idle/close)
//   .claude/logs/model-usage-errors.ndjson — MemPalace write failures
//
// NOTE: No console.* — OpenCode plugins share stderr with the TUI.

// ── Token shape ───────────────────────────────────────────────────────────────

interface AssistantMessageTokens {
  input: number
  output: number
  reasoning: number
  cache: { read: number; write: number }
}

// ── Tier mapping ──────────────────────────────────────────────────────────────

type Tier = "utility" | "primary" | "sign-off" | "unknown"

interface TierEntry {
  tier: Tier
  /** Approximate cost per 1M output tokens in USD. 0 = local. */
  costPer1MOut: number
}

// policy/guard-patterns.json's model_tier_map is the single source of truth
// (shared with hooks/model-usage-summary.sh and tools/model-report.py). Fall
// back to this previous hardcoded map if the file is missing or unreadable.
const FALLBACK_TIER_MAP: Record<string, TierEntry> = {
  "devstral":              { tier: "primary",  costPer1MOut: 0 },
  "llama3.3":              { tier: "primary",  costPer1MOut: 0 },
  "gemma4":                { tier: "primary",  costPer1MOut: 0 },
  "qwen2.5-coder":         { tier: "utility",  costPer1MOut: 0 },
  "claude-opus-4":         { tier: "sign-off", costPer1MOut: 75 },
  "claude-opus-3":         { tier: "sign-off", costPer1MOut: 75 },
  "claude-sonnet-4":       { tier: "sign-off", costPer1MOut: 15 },
  "claude-sonnet-3":       { tier: "sign-off", costPer1MOut: 15 },
  "claude-haiku-4":        { tier: "sign-off", costPer1MOut: 1.25 },
  "claude-haiku-3":        { tier: "sign-off", costPer1MOut: 1.25 },
  "gpt-4o":                { tier: "sign-off", costPer1MOut: 15 },
  "o3":                    { tier: "sign-off", costPer1MOut: 60 },
  "gemini-2.5-pro":        { tier: "sign-off", costPer1MOut: 10 },
}

function loadTierMap(): Record<string, TierEntry> {
  try {
    const scriptPath = realpathSync(fileURLToPath(import.meta.url))
    const policyPath = join(dirname(scriptPath), "..", "policy", "guard-patterns.json")
    const raw = JSON.parse(readFileSync(policyPath, "utf8")) as {
      model_tier_map?: Record<string, { tier: Tier; cost_per_1m_out: number }>
    }
    const map = raw.model_tier_map
    if (!map) return FALLBACK_TIER_MAP

    const result: Record<string, TierEntry> = {}
    for (const [key, entry] of Object.entries(map)) {
      if (key.startsWith("$")) continue
      result[key] = { tier: entry.tier, costPer1MOut: entry.cost_per_1m_out }
    }
    return result
  } catch {
    return FALLBACK_TIER_MAP
  }
}

const TIER_MAP: Record<string, TierEntry> = loadTierMap()

function resolveTier(modelID: string): TierEntry {
  // Prefix-match: "claude-opus-4" matches "claude-opus-4-6", "claude-opus-4-5", etc.
  // More specific prefixes must be listed before general ones in TIER_MAP.
  for (const [key, entry] of Object.entries(TIER_MAP)) {
    if (modelID.startsWith(key)) return entry
  }
  return { tier: "unknown", costPer1MOut: 0 }
}

// ── Storage helpers ───────────────────────────────────────────────────────────

function logDir(cwd: string): string {
  const dir = join(cwd, ".claude", "logs")
  mkdirSync(dir, { recursive: true })
  return dir
}

// ── In-memory session state ───────────────────────────────────────────────────

type TierBucket = {
  calls: number
  tokens_in: number
  tokens_out: number
  tokens_reasoning: number
  tokens_cache_read: number
  cost_usd: number
}

interface SessionAccumulator {
  sessionID: string
  startTs: string
  by_tier: Record<string, TierBucket>
}

const sessions = new Map<string, SessionAccumulator>()
const costWarningFired = new Set<string>()
const SESSION_MAX_AGE_MS = 24 * 60 * 60 * 1_000 // 24 hours

function readCostCeiling(cwd: string): number {
  try {
    const settingsPath = join(cwd, ".claude", "settings.local.json")
    const settings = JSON.parse(readFileSync(settingsPath, "utf8"))
    const val = settings?.costCeilingUsd
    return typeof val === "number" && val > 0 ? val : 5.0
  } catch {
    return 5.0
  }
}

function getOrCreate(sessionID: string): SessionAccumulator {
  const existing = sessions.get(sessionID)
  if (existing) return existing
  const acc: SessionAccumulator = { sessionID, startTs: new Date().toISOString(), by_tier: {} }
  sessions.set(sessionID, acc)
  return acc
}

function accumulate(acc: SessionAccumulator, tier: string, tokens: {
  input: number; output: number; reasoning: number; cache_read: number
}, cost: number): void {
  if (!acc.by_tier[tier]) {
    acc.by_tier[tier] = { calls: 0, tokens_in: 0, tokens_out: 0, tokens_reasoning: 0, tokens_cache_read: 0, cost_usd: 0 }
  }
  const b = acc.by_tier[tier]
  b.calls++
  b.tokens_in         += tokens.input
  b.tokens_out        += tokens.output
  b.tokens_reasoning  += tokens.reasoning
  b.tokens_cache_read += tokens.cache_read
  b.cost_usd          += cost
}

// ── MemPalace helper ──────────────────────────────────────────────────────────
// FIX-5: Use env override → pyenv shim (not version-pinned path)

const PYENV_PYTHON = process.env["MEMPALACE_PYTHON"]
  ?? join(homedir(), ".pyenv", "shims", "python3")

function writeToMemPalace(cwd: string, acc: SessionAccumulator): void {
  try {
    const totalTok  = Object.values(acc.by_tier).reduce((s, b) => s + b.tokens_in + b.tokens_out, 0)
    const totalCost = Object.values(acc.by_tier).reduce((s, b) => s + b.cost_usd, 0)
    // FIX-6: Sanitise tier keys — prevent pipe/equals chars corrupting MemPalace entry format
    const tierLines = Object.entries(acc.by_tier)
      .map(([t, b]) => {
        const safeTier = t.replace(/[|=\n\r]/g, "_")
        return `${safeTier}:calls=${b.calls},tok_in=${b.tokens_in},tok_out=${b.tokens_out},cost=${b.cost_usd.toFixed(4)}`
      })
      .join("|")
    const entry = `SESSION_USAGE:${acc.startTs.slice(0, 10)}|${tierLines}|total_tok=${totalTok}|total_cost_usd=${totalCost.toFixed(4)}`
    // FIX-3: Log execFile failures to model-usage-errors.ndjson
    execFile(PYENV_PYTHON, [
      "-m", "mempalace", "add-drawer",
      "--wing", "wing_ai_dev", "--room", "model-usage",
      "--content", entry, "--added-by", "model-usage-plugin",
    ], { timeout: 8_000 }, (err) => {
      if (err) {
        try {
          appendFileSync(
            join(logDir(cwd), "model-usage-errors.ndjson"),
            JSON.stringify({ ts: new Date().toISOString(), event: "mempalace.write.failed", error: err.message }) + "\n",
          )
        } catch { /* truly last-resort */ }
      }
    })
  } catch { /* mempalace unavailable — ignore */ }
}

// ── Session flush (shared by idle, closed, ended, and TTL eviction) ───────────

function flushSession(cwd: string, sessionID: string, acc: SessionAccumulator): void {
  const totalTok  = Object.values(acc.by_tier).reduce((s, b) => s + b.tokens_in + b.tokens_out, 0)
  const totalCost = Object.values(acc.by_tier).reduce((s, b) => s + b.cost_usd, 0)
  const summary = {
    ts: new Date().toISOString(),
    event: "session-summary",
    session: sessionID,
    start_ts: acc.startTs,
    by_tier: acc.by_tier,
    totals: { tokens: totalTok, cost_usd: totalCost },
  }
  try {
    appendFileSync(join(logDir(cwd), "model-summary.ndjson"), JSON.stringify(summary) + "\n")
  } catch { /* ignore */ }
  writeToMemPalace(cwd, acc)
}

// FIX-2: TTL-based eviction — evict sessions older than 24h on every event
function evictStaleSessions(cwd: string): void {
  const now = Date.now()
  for (const [id, acc] of sessions) {
    if (now - new Date(acc.startTs).getTime() > SESSION_MAX_AGE_MS) {
      flushSession(cwd, id, acc)
      sessions.delete(id)
    }
  }
}

// ── Plugin ────────────────────────────────────────────────────────────────────

export const ModelUsagePlugin: Plugin = async () => {
  return {
    event: async ({ event }: { event: Event }) => {
      const cwd = process.cwd()

      // Evict stale sessions on every event (cheap — O(n) over open sessions)
      evictStaleSessions(cwd)

      // ── Per-message: assistant message completed ──────────────────────────
      if (event.type === "message.updated") {
        // FIX-1: Guard against null/undefined/wrong-shape before any property access
        const raw = (event.properties as Record<string, unknown>)?.["info"]
        if (!raw || typeof raw !== "object") return
        const msg = raw as Record<string, unknown>
        if (msg["role"] !== "assistant") return

        const modelID    = typeof msg["modelID"]    === "string" ? msg["modelID"]    : "unknown"
        const providerID = typeof msg["providerID"] === "string" ? msg["providerID"] : "unknown"
        // FIX-S3: Sanitise sessionID before writing to log
        const rawSession = typeof msg["sessionID"]  === "string" ? msg["sessionID"]  : "unknown"
        const sessionID  = rawSession.replace(/[\n\r]/g, "_")
        const rawCost    = typeof msg["cost"]       === "number" ? msg["cost"]       : 0
        const rawTok: AssistantMessageTokens = (msg["tokens"] && typeof msg["tokens"] === "object")
          ? msg["tokens"] as AssistantMessageTokens
          : { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } }

        const { tier, costPer1MOut } = resolveTier(modelID)
        // FIX-4: Include reasoning tokens in fallback cost estimate
        const estimatedCost = ((rawTok.output + rawTok.reasoning) / 1_000_000) * costPer1MOut
        const cost_usd = rawCost > 0 ? rawCost : estimatedCost

        const usageEntry = {
          ts: new Date().toISOString(),
          event: "model-usage",
          session: sessionID,
          tier,
          model: modelID,
          provider: providerID,
          tokens: {
            input:      rawTok.input,
            output:     rawTok.output,
            reasoning:  rawTok.reasoning,
            cache_read:  rawTok.cache.read,
            cache_write: rawTok.cache.write,
            total: rawTok.input + rawTok.output + rawTok.reasoning,
          },
          cost_usd,
        }

        try {
          appendFileSync(join(logDir(cwd), "model-usage.ndjson"), JSON.stringify(usageEntry) + "\n")
        } catch { /* ignore */ }

        const acc = getOrCreate(sessionID)
        accumulate(acc, tier, {
          input: rawTok.input, output: rawTok.output,
          reasoning: rawTok.reasoning, cache_read: rawTok.cache.read,
        }, cost_usd)

        // Cost ceiling advisory warning
        const totalCost = Object.values(acc.by_tier).reduce((s, b) => s + b.cost_usd, 0)
        const ceiling = readCostCeiling(cwd)
        if (ceiling > 0 && totalCost > ceiling && !costWarningFired.has(sessionID)) {
          costWarningFired.add(sessionID)
          try {
            appendFileSync(
              join(logDir(cwd), "model-usage.ndjson"),
              JSON.stringify({
                ts: new Date().toISOString(),
                event: "cost-warning",
                session: sessionID,
                total_cost_usd: totalCost,
                ceiling_usd: ceiling,
                message: `Session cost $${totalCost.toFixed(2)} exceeds ceiling $${ceiling.toFixed(2)}`,
              }) + "\n",
            )
          } catch { /* ignore */ }
        }
      }

      // ── Session idle / closed / ended → flush summary ─────────────────────
      // FIX-2: Handle all session-end events, not just session.idle
      if (
        event.type === "session.idle" ||
        event.type === "session.closed" ||
        event.type === "session.ended"
      ) {
        // FIX-1 (C4): Safe optional accessor — don't crash on missing sessionID
        const sessionID = (event.properties as Partial<{ sessionID: string }>).sessionID
        if (!sessionID) return
        const acc = sessions.get(sessionID)
        if (!acc) return
        flushSession(cwd, sessionID, acc)
        sessions.delete(sessionID)
      }

      // ── Compaction marker ─────────────────────────────────────────────────
      if (event.type === "session.compacted") {
        // FIX-1 (C4): Safe optional accessor
        const sessionID = (event.properties as Partial<{ sessionID: string }>).sessionID
        if (!sessionID) return
        try {
          appendFileSync(
            join(logDir(cwd), "model-usage.ndjson"),
            JSON.stringify({ ts: new Date().toISOString(), event: "compaction", session: sessionID }) + "\n",
          )
        } catch { /* ignore */ }
      }
    },
  }
}
