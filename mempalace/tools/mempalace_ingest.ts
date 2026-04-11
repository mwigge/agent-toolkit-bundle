// mempalace_ingest.ts — OpenCode custom tool: trigger a MemPalace ingestion.
// SPDX-License-Identifier: Apache-2.0
//
// LLM-callable wrapper around the mempalace-ingest.sh shell hook. Use this
// when the user asks to "re-ingest", "re-scan the palace", or wants to push
// a specific directory into memory without waiting for the session-level
// tool.execute.after hook to trigger incrementally.
//
// Either walks a single path (the `path` arg) or runs the full scan against
// every directory configured in mempalace.conf. Never parses file contents.
// Classification is the MCP backend's job.

import { tool } from "@opencode-ai/plugin"
import { execFileSync } from "child_process"
import { existsSync, statSync } from "fs"
import { homedir } from "os"
import { isAbsolute, join, resolve } from "path"

const MAX_OUTPUT_BYTES = 256 * 1024
const CALL_TIMEOUT_MS = 60_000

function resolveHook(cwd: string): string {
  const candidates = [
    join(homedir(), ".agents", "mempalace", "hooks", "mempalace-ingest.sh"),
    join(homedir(), ".claude", "hooks", "mempalace-ingest.sh"),
    join(cwd, "mempalace", "hooks", "mempalace-ingest.sh"),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  throw new Error(
    "mempalace-ingest.sh not found in ~/.agents/mempalace/hooks, " +
      "~/.claude/hooks, or the current project's mempalace/hooks/ — is the bundle installed?",
  )
}

export default tool({
  description:
    "Trigger a MemPalace ingestion against the BYO MCP server. " +
    "With no argument, re-scans every configured path. With a path argument, " +
    "limits the scan to that directory. Returns a summary of what the " +
    "underlying hook wrote to stderr.",
  args: {
    path: tool.schema
      .string()
      .optional()
      .describe(
        "Optional absolute or project-relative directory to scan. If omitted, " +
          "all paths from mempalace.conf are walked. Must not contain '..'.",
      ),
  },
  async execute(args, context) {
    const cwd = context.directory ?? process.cwd()

    if (args.path !== undefined) {
      if (args.path.includes("..")) {
        throw new Error(`invalid path: ${args.path} (no .. segments allowed)`)
      }
      const abs = isAbsolute(args.path) ? args.path : resolve(cwd, args.path)
      if (!existsSync(abs)) {
        throw new Error(`path not found: ${abs}`)
      }
      if (!statSync(abs).isDirectory()) {
        throw new Error(`path is not a directory: ${abs}`)
      }
      // The shell hook only understands "scan" (full) or stdin (per-file).
      // For a single-path scan, export EXTRA_PATHS and run a full scan; the
      // hook unions SCAN_PATHS + EXTRA_PATHS.
      const hook = resolveHook(cwd)
      try {
        const out = execFileSync("bash", [hook, "scan"], {
          cwd,
          env: { ...process.env, EXTRA_PATHS: abs },
          timeout: CALL_TIMEOUT_MS,
          stdio: ["ignore", "pipe", "pipe"],
          maxBuffer: MAX_OUTPUT_BYTES,
        })
        return out.toString("utf8").trim() || `scan complete for ${abs}`
      } catch (err) {
        const e = err as { stderr?: Buffer; message?: string }
        return (
          "scan failed: " +
          (e.stderr?.toString("utf8") ?? e.message ?? "unknown error")
        )
      }
    }

    const hook = resolveHook(cwd)
    try {
      const out = execFileSync("bash", [hook, "scan"], {
        cwd,
        timeout: CALL_TIMEOUT_MS,
        stdio: ["ignore", "pipe", "pipe"],
        maxBuffer: MAX_OUTPUT_BYTES,
      })
      return out.toString("utf8").trim() || "scan complete (no new records)"
    } catch (err) {
      const e = err as { stderr?: Buffer; message?: string }
      return (
        "scan failed: " + (e.stderr?.toString("utf8") ?? e.message ?? "unknown error")
      )
    }
  },
})
