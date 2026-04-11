// observe.ts — OpenCode audit trail + transcript backup.
// SPDX-License-Identifier: Apache-2.0
//
// Mirrors the observe.sh + transcript-backup.sh pair of Claude Code hooks.
// Writes structured NDJSON to .claude/logs/events.ndjson on every tool call,
// and snapshots session-compaction payloads to .claude/backups/transcript-*.jsonl.
// Never throws — audit failures are silently ignored.
//
// NOTE: No console.* — OpenCode plugins share stderr with the TUI.
//       All output goes to .claude/logs/events.ndjson only.
//
// Install:
//   cp plugins/observe.ts ~/.config/opencode/plugin/observe.ts

import type { Plugin } from "@opencode-ai/plugin"
import {
  appendFileSync,
  mkdirSync,
  writeFileSync,
  readdirSync,
  unlinkSync,
} from "fs"
import { join } from "path"

const MAX_BACKUPS = 10

function logDir(cwd: string): string {
  const dir = join(cwd, ".claude", "logs")
  mkdirSync(dir, { recursive: true })
  return dir
}

function backupDir(cwd: string): string {
  const dir = join(cwd, ".claude", "backups")
  mkdirSync(dir, { recursive: true })
  return dir
}

function riskScore(tool: string, summary: string): number {
  if (tool === "bash") {
    if (
      /rm\s+-rf|drop\s+table|truncate|curl|wget|ssh\s|scp\s|rsync|git\s+push|git\s+reset|pip\s+install|npm\s+install/i.test(
        summary,
      )
    )
      return 3
    if (/\.env|migration|alter\s+table|create\s+table|chmod|chown/i.test(summary))
      return 2
    return 1
  }
  if (tool === "edit" || tool === "write") {
    if (/\.env|settings\.local|pdm\.lock|package-lock/i.test(summary)) return 2
    return 1
  }
  if (tool === "webfetch") return 1
  return 0
}

function summarise(tool: string, args: Record<string, unknown>): string {
  const str = (key: string): string =>
    typeof args[key] === "string" ? (args[key] as string) : ""
  switch (tool) {
    case "bash":
      return str("command").slice(0, 200)
    case "edit":
    case "write":
      return str("filePath")
    case "read":
    case "glob":
    case "grep":
      return str("filePath") || str("pattern")
    case "webfetch":
      return str("url")
    default:
      return JSON.stringify(args).slice(0, 200)
  }
}

function pruneBackups(dir: string): void {
  try {
    const files = readdirSync(dir)
      .filter((f) => f.startsWith("transcript-") && f.endsWith(".jsonl"))
      .map((f) => join(dir, f))
      .sort()
    if (files.length > MAX_BACKUPS) {
      for (const f of files.slice(0, files.length - MAX_BACKUPS)) {
        try {
          unlinkSync(f)
        } catch {
          // Ignore unlink failures.
        }
      }
    }
  } catch {
    // Ignore readdir failures.
  }
}

export const ObservePlugin: Plugin = async () => {
  return {
    // tool.execute.before: args live on output.args (mutable).
    "tool.execute.before": async (input, output) => {
      const tool = input.tool
      const args = (output.args ?? {}) as Record<string, unknown>
      const cwd = process.cwd()
      const summary = summarise(tool, args)
      const risk = riskScore(tool, summary)
      const entry = JSON.stringify({
        ts: new Date().toISOString(),
        event: "PreToolUse",
        tool,
        input_summary: summary,
        outcome: "ok",
        risk,
      })
      try {
        appendFileSync(join(logDir(cwd), "events.ndjson"), entry + "\n")
        if (risk >= 3) {
          appendFileSync(
            join(cwd, ".claude", "audit.log"),
            `${new Date().toISOString()} HIGH-RISK tool=${tool} ${summary.slice(0, 150)}\n`,
          )
        }
      } catch {
        // Ignore audit failures.
      }
    },

    // tool.execute.after: args live on input.args (read-only).
    "tool.execute.after": async (input, _output) => {
      const tool = input.tool
      const args = (input.args ?? {}) as Record<string, unknown>
      const cwd = process.cwd()
      const summary = summarise(tool, args)
      const risk = riskScore(tool, summary)
      const entry = JSON.stringify({
        ts: new Date().toISOString(),
        event: "PostToolUse",
        tool,
        input_summary: summary,
        outcome: "ok",
        risk,
      })
      try {
        appendFileSync(join(logDir(cwd), "events.ndjson"), entry + "\n")
      } catch {
        // Ignore audit failures.
      }
    },

    "experimental.session.compacting": async (_input, _output) => {
      const cwd = process.cwd()
      const ts = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15)
      const outFile = join(backupDir(cwd), `transcript-${ts}.jsonl`)
      try {
        const payload = JSON.stringify(_input ?? {})
        writeFileSync(outFile, payload + "\n")
        pruneBackups(backupDir(cwd))
        appendFileSync(
          join(logDir(cwd), "events.ndjson"),
          JSON.stringify({
            ts: new Date().toISOString(),
            event: "PreCompact",
            backup: outFile,
          }) + "\n",
        )
      } catch {
        // Ignore backup failures.
      }
    },
  }
}
