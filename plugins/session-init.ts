// session-init.ts — OpenCode one-shot session bootstrap.
// SPDX-License-Identifier: Apache-2.0
//
// OpenCode has no SessionStart event. We simulate it by running once
// on the first tool call of a process lifetime (module-level flag =
// per-session). Mirrors Claude Code's setup-init.sh hook: ensure the
// .claude/ working directories exist, log a SessionStart event, and
// drop a short reminder into the session-init log.
//
// NOTE: No console.* — OpenCode plugins share stderr with the TUI.
//       All output goes to .claude/logs/session-init.log only.
//
// Install:
//   cp plugins/session-init.ts ~/.config/opencode/plugin/session-init.ts

import type { Plugin } from "@opencode-ai/plugin"
import {
  existsSync,
  mkdirSync,
  appendFileSync,
  writeFileSync,
} from "fs"
import { join } from "path"

let sessionInitialised = false

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
      JSON.stringify({
        ts: new Date().toISOString(),
        event: "SessionStart",
        via: "session-init-plugin",
      }) + "\n",
    )
  } catch {
    // Ignore log failures.
  }
}

function logReminder(cwd: string): void {
  const logFile = join(cwd, ".claude", "logs", "session-init.log")
  const reminder =
    "SESSION INITIALISED. Read AGENTS.md before your first action. " +
    "Apply conventional commits. No AI attribution. No hardcoded secrets."
  try {
    appendFileSync(logFile, `${new Date().toISOString()} INIT\n${reminder}\n\n`)
  } catch {
    // Ignore log failures.
  }
}

// ── Plugin ────────────────────────────────────────────────────────────────────

export const SessionInitPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (_input, _output) => {
      if (sessionInitialised) return
      sessionInitialised = true

      const cwd = process.cwd()

      // 1. Ensure required dirs.
      ensureDirs(cwd)

      // 2. Log session start event.
      logSessionStart(cwd)

      // 3. Drop a short reminder into the session-init log (file only, not terminal).
      logReminder(cwd)
    },
  }
}
