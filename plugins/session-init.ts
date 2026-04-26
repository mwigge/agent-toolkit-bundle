import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, mkdirSync, readFileSync, appendFileSync, writeFileSync, statSync, renameSync, createReadStream, createWriteStream } from "fs"
import { createGzip } from "zlib"
import { pipeline } from "stream"
import { execFile } from "child_process"
import { homedir } from "os"
import { join } from "path"

// OpenCode has no SessionStart event. We simulate it by running once on the
// first tool call of a process lifetime (module-level flag = per-session).
// Mirrors Claude Code's setup-init.sh + mempalace-wake-up.sh combined.
// NOTE: No console.warn — OpenCode plugins share stderr with the TUI.
//       All output goes to .claude/logs/session-init.log only.

let sessionInitialised = false

const HOME = homedir()
const PYENV_PYTHON = join(HOME, ".pyenv", "versions", "3.12.13", "bin", "python3")
const AI_LOCAL = join(HOME, "dev", "src", "ai_local")
const DOCS_LOCAL = join(HOME, "dev", "src", "docs_local")
const MINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000

// ── Wing keyword routing ──────────────────────────────────────────────────────

const WING_KEYWORDS: Record<string, string[]> = {
  wing_cls_architecture: ["mcp", "agent", "sso", "auth", "multitenancy", "org-role", "idp", "wl-sso", "apigee", "compliance"],
  wing_cls_platform: ["early-adopter", "onboarding", "feedback", "admin-role", "tester-first", "demo", "learning", "gamification", "slack", "slo", "dora"],
  wing_cls_resilience: ["resilience", "maturity", "score", "complexity", "ontology", "scenario", "experiment", "library", "steadystate", "recommend", "incident"],
  wing_cls_infra: ["postgres", "pgbouncer", "observability", "pre-production", "hardening", "compute", "metric", "typed", "session-metric", "quality-lake", "run-probe", "run-experiment", "guardrail", "extension", "analytics", "cloud", "kubernetes", "artifactory", "alerting"],
}

function detectWing(changeName: string): string {
  const lower = changeName.toLowerCase()
  for (const [wing, keywords] of Object.entries(WING_KEYWORDS)) {
    if (keywords.some((kw) => lower.includes(kw))) return wing
  }
  return "wing_ai_dev"
}

function detectPrimaryWing(): string {
  const detected = new Set<string>()

  // From memory.md branch names
  const memoryFile = join(AI_LOCAL, "memory.md")
  if (existsSync(memoryFile)) {
    const content = readFileSync(memoryFile, "utf8")
    for (const match of content.matchAll(/feat\/CLS-\d+\/([a-z0-9_-]+)/g)) {
      detected.add(detectWing(match[1]))
    }
  }

  // From recently modified openspec/changes/ dirs
  const changesDir = join(DOCS_LOCAL, "openspec", "changes")
  if (existsSync(changesDir)) {
    try {
      const { readdirSync, statSync } = require("fs") as typeof import("fs")
      const entries = readdirSync(changesDir, { withFileTypes: true })
      for (const entry of entries) {
        if (!entry.isDirectory() || entry.name === "archive") continue
        const stat = statSync(join(changesDir, entry.name))
        if (Date.now() - stat.mtimeMs < MINE_WINDOW_MS) {
          detected.add(detectWing(entry.name))
        }
      }
    } catch { /* ignore */ }
  }

  // Priority ordering
  for (const preferred of ["wing_cls_architecture", "wing_cls_platform", "wing_cls_resilience", "wing_cls_infra"]) {
    if (detected.has(preferred)) return preferred
  }
  return "wing_ai_dev"
}

function ensureDirs(cwd: string): void {
  for (const sub of [".claude/logs", ".claude/backups", ".claude/cache"]) {
    mkdirSync(join(cwd, sub), { recursive: true })
  }
  const auditLog = join(cwd, ".claude", "audit.log")
  if (!existsSync(auditLog)) writeFileSync(auditLog, "")
}

function logSessionStart(cwd: string): void {
  const logFile = join(cwd, ".claude", "logs", "events.ndjson")
  try {
    appendFileSync(
      logFile,
      JSON.stringify({ ts: new Date().toISOString(), event: "SessionStart", via: "session-init-plugin" }) + "\n",
    )
  } catch { /* ignore */ }
}

function wakeUpPalace(wing: string): Promise<string> {
  return new Promise((resolve) => {
    if (!existsSync(PYENV_PYTHON)) { resolve(""); return }
    execFile(
      PYENV_PYTHON,
      ["-m", "mempalace", "wake-up", "--wing", wing],
      { timeout: 10000 },
      (err, stdout) => resolve(err ? "" : stdout.trim()),
    )
  })
}

// ── Log rotation ─────────────────────────────────────────────────────────────

const MAX_LOG_SIZE = 50 * 1024 * 1024 // 50 MB

function rotateLogsIfNeeded(cwd: string): void {
  const logsDir = join(cwd, ".claude", "logs")
  for (const logfile of ["events.ndjson", "model-usage.ndjson"]) {
    const lpath = join(logsDir, logfile)
    try {
      if (!existsSync(lpath)) continue
      const size = statSync(lpath).size
      if (size <= MAX_LOG_SIZE) continue

      for (let i = 4; i >= 1; i--) {
        const src = join(logsDir, `${logfile}.${i}.gz`)
        const dst = join(logsDir, `${logfile}.${i + 1}.gz`)
        if (existsSync(src)) renameSync(src, dst)
      }

      const gzPath = join(logsDir, `${logfile}.1.gz`)
      pipeline(
        createReadStream(lpath),
        createGzip(),
        createWriteStream(gzPath),
        () => { /* fire and forget */ },
      )
      writeFileSync(lpath, "")
    } catch {
      // rotation failures are never blockers
    }
  }
}

// ── Plugin ────────────────────────────────────────────────────────────────────

export const SessionInitPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (_input, _output) => {
      if (sessionInitialised) return
      sessionInitialised = true

      const cwd = process.cwd()

      // 1. Ensure required dirs
      ensureDirs(cwd)

      // 1b. Log rotation (50 MB threshold, 5 rotations)
      rotateLogsIfNeeded(cwd)

      // 2. Log session start event
      logSessionStart(cwd)

      // 3. MemPalace wake-up (async — don't block the tool call)
      const wing = detectPrimaryWing()
      const logFile = join(cwd, ".claude", "logs", "session-init.log")
      wakeUpPalace(wing).then((wakeText) => {
        const prefix = wakeText
          ? `MEMPALACE WAKE-UP [wing: ${wing}]\n${wakeText}\nUse mempalace_search() or mempalace_list_rooms() for deeper recall.`
          : `MEMPALACE: palace not initialised or empty. Run /mine all to populate.`
        try {
          appendFileSync(logFile, `${new Date().toISOString()} WAKE-UP [${wing}]\n${prefix}\n\n`)
        } catch { /* ignore */ }
      }).catch(() => { /* ignore */ })

      // 4. Log AGENTS.md reminder to file only (not terminal)
      const memoryPath = join(AI_LOCAL, "memory.md")
      let reminder = "SESSION INITIALISED. Read AGENTS.md before your first action. Apply conventional commits. No AI attribution. No hardcoded secrets."
      if (existsSync(memoryPath)) {
        reminder += ` Also read ${memoryPath} for session state from previous work.`
      }
      try {
        appendFileSync(logFile, `${new Date().toISOString()} INIT\n${reminder}\n\n`)
      } catch { /* ignore */ }
    },
  }
}
