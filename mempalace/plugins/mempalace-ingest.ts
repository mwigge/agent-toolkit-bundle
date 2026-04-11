// mempalace-ingest.ts — OpenCode equivalent of mempalace-ingest.sh +
// mempalace-wake-up.sh.
// SPDX-License-Identifier: Apache-2.0
//
// Two hooks:
//
//   session.created        — one-shot connectivity probe against the BYO
//                            MCP server (mempalace_status).
//   tool.execute.after     — on edit/write tool calls, ingest the affected
//                            file if it lives inside a configured scan path.
//
// Pure directory-boundary check. The plugin never inspects file contents for
// keywords, never classifies, never picks a wing or a room. It forwards raw
// bytes to the MCP server and the backend decides what to do with them.
//
// Never throws. If MCP is unreachable, log once to .claude/logs/events.ndjson
// and no-op for the rest of the session.

import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, mkdirSync, readFileSync, statSync } from "fs"
import { createHash } from "crypto"
import { execFileSync } from "child_process"
import { homedir } from "os"
import { dirname, isAbsolute, join, relative, resolve } from "path"

// ── config loading ────────────────────────────────────────────────────────────

interface PalaceConfig {
  scanPaths: string[]
  extraPaths: string[]
  ingestGlobs: string[]
  mcpUrl: string
  mcpToken: string
  cli: string
}

const DEFAULT_SCAN_PATHS = ["docs_local", "docs_local/openspec"]
const DEFAULT_INGEST_GLOBS = [".md", ".yaml", ".yml"]
const MAX_FILE_BYTES = 1_048_576
const CALL_TIMEOUT_MS = 10_000

function parseCsv(value: string): string[] {
  return value
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
}

function loadConfig(): PalaceConfig {
  const configPath =
    process.env.MEMPALACE_CONFIG ??
    join(homedir(), ".agents", "mempalace", "config", "mempalace.conf")

  let scanPaths = DEFAULT_SCAN_PATHS
  let extraPaths: string[] = []
  let ingestGlobs = DEFAULT_INGEST_GLOBS
  let mcpUrlFromFile = ""
  let mcpTokenFromFile = ""

  if (existsSync(configPath)) {
    try {
      const content = readFileSync(configPath, "utf8")
      for (const rawLine of content.split(/\r?\n/)) {
        const line = rawLine.trim()
        if (!line || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 0) continue
        const key = line.slice(0, eq).trim()
        let value = line.slice(eq + 1).trim()
        value = value.replace(/^["']|["']$/g, "")
        switch (key) {
          case "SCAN_PATHS":
            scanPaths = parseCsv(value)
            break
          case "EXTRA_PATHS":
            extraPaths = parseCsv(value)
            break
          case "INGEST_GLOBS":
            ingestGlobs = parseCsv(value).map((g) =>
              g.startsWith("*.") ? g.slice(1) : g.startsWith(".") ? g : `.${g}`,
            )
            break
          case "MCP_URL":
            mcpUrlFromFile = value
            break
          case "MCP_TOKEN":
            mcpTokenFromFile = value
            break
          default:
            break
        }
      }
    } catch {
      // Degrade silently on config read failure.
    }
  }

  return {
    scanPaths,
    extraPaths,
    ingestGlobs,
    mcpUrl: process.env.MEMPALACE_MCP_URL ?? mcpUrlFromFile,
    mcpToken: process.env.MEMPALACE_MCP_TOKEN ?? mcpTokenFromFile,
    cli: process.env.MEMPALACE_CLI ?? "mempalace",
  }
}

// ── logging ───────────────────────────────────────────────────────────────────

function logDir(cwd: string): string {
  const dir = join(cwd, ".claude", "logs")
  mkdirSync(dir, { recursive: true })
  return dir
}

function logEvent(cwd: string, event: Record<string, unknown>): void {
  try {
    appendFileSync(
      join(logDir(cwd), "events.ndjson"),
      JSON.stringify({ ts: new Date().toISOString(), ...event }) + "\n",
    )
  } catch {
    // Ignore logging failures — this hook is advisory.
  }
}

// ── MCP transport ─────────────────────────────────────────────────────────────

interface CallResult {
  ok: boolean
  body: string
}

function callViaCli(
  cli: string,
  tool: string,
  args: Record<string, unknown>,
): CallResult {
  try {
    const body = execFileSync(cli, ["call", tool], {
      input: JSON.stringify(args),
      timeout: CALL_TIMEOUT_MS,
      stdio: ["pipe", "pipe", "pipe"],
      maxBuffer: 4 * 1024 * 1024,
    }).toString("utf8")
    return { ok: true, body }
  } catch {
    return { ok: false, body: "" }
  }
}

function callViaHttp(
  url: string,
  token: string,
  tool: string,
  args: Record<string, unknown>,
): CallResult {
  const payload = JSON.stringify({ tool, arguments: args })
  const curlArgs = [
    "-sS",
    "--max-time",
    String(Math.ceil(CALL_TIMEOUT_MS / 1000)),
    "-H",
    "Content-Type: application/json",
  ]
  if (token) {
    curlArgs.push("-H", `Authorization: Bearer ${token}`)
  }
  curlArgs.push("-X", "POST", "--data", payload, `${url}/tools/call`)
  try {
    const body = execFileSync("curl", curlArgs, {
      timeout: CALL_TIMEOUT_MS,
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 4 * 1024 * 1024,
    }).toString("utf8")
    return { ok: true, body }
  } catch {
    return { ok: false, body: "" }
  }
}

function hasBinary(bin: string): boolean {
  try {
    execFileSync("sh", ["-c", `command -v ${bin}`], {
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 2_000,
    })
    return true
  } catch {
    return false
  }
}

function callTool(
  cfg: PalaceConfig,
  tool: string,
  args: Record<string, unknown>,
): CallResult {
  if (hasBinary(cfg.cli)) return callViaCli(cfg.cli, tool, args)
  if (hasBinary("curl") && cfg.mcpUrl) {
    return callViaHttp(cfg.mcpUrl, cfg.mcpToken, tool, args)
  }
  return { ok: false, body: "" }
}

// ── ingestion ─────────────────────────────────────────────────────────────────

function isInsideScanRoot(cfg: PalaceConfig, cwd: string, filePath: string): boolean {
  const absFile = resolve(filePath)
  const roots: string[] = []
  for (const p of [...cfg.scanPaths, ...cfg.extraPaths]) {
    roots.push(isAbsolute(p) ? p : resolve(cwd, p))
  }
  for (const root of roots) {
    const rel = relative(root, absFile)
    if (rel && !rel.startsWith("..") && !isAbsolute(rel)) return true
  }
  return false
}

function hasIngestExtension(cfg: PalaceConfig, filePath: string): boolean {
  const lower = filePath.toLowerCase()
  return cfg.ingestGlobs.some((ext) => lower.endsWith(ext.toLowerCase()))
}

function ingestOne(cfg: PalaceConfig, cwd: string, absPath: string): void {
  try {
    const st = statSync(absPath)
    if (!st.isFile()) return
    if (st.size > MAX_FILE_BYTES) {
      logEvent(cwd, {
        event: "mempalace.skip",
        reason: "oversize",
        path: absPath,
        size: st.size,
      })
      return
    }
  } catch {
    return
  }

  let content: string
  try {
    content = readFileSync(absPath, "utf8")
  } catch {
    return
  }

  const hash = createHash("sha256").update(content).digest("hex")
  const rel = relative(cwd, absPath) || absPath

  const dup = callTool(cfg, "mempalace_check_duplicate", {
    content_hash: hash,
    source_path: rel,
  })
  if (dup.ok && /"duplicate"\s*:\s*true/.test(dup.body)) {
    return
  }

  const add = callTool(cfg, "mempalace_add_drawer", {
    source_path: rel,
    content_hash: hash,
    content,
  })
  logEvent(cwd, {
    event: "mempalace.ingest",
    path: rel,
    ok: add.ok,
  })
}

// ── plugin wiring ─────────────────────────────────────────────────────────────

let sessionProbed = false
let palaceUp = false

export const MemPalaceIngestPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (_input, _output) => {
      if (sessionProbed) return
      sessionProbed = true

      const cfg = loadConfig()
      const cwd = process.cwd()
      if (!cfg.mcpUrl && !hasBinary(cfg.cli)) {
        logEvent(cwd, { event: "mempalace.wake", ok: false, reason: "unconfigured" })
        return
      }

      const status = callTool(cfg, "mempalace_status", {})
      palaceUp = status.ok && status.body.length > 0
      logEvent(cwd, { event: "mempalace.wake", ok: palaceUp })
    },

    "tool.execute.after": async (input, _output) => {
      if (!palaceUp) return
      const tool = input.tool
      if (tool !== "edit" && tool !== "write") return
      const args = (input.args ?? {}) as Record<string, unknown>
      const filePath = typeof args.filePath === "string" ? args.filePath : ""
      if (!filePath) return

      const cfg = loadConfig()
      const cwd = process.cwd()
      const abs = isAbsolute(filePath) ? filePath : resolve(cwd, filePath)
      if (!isInsideScanRoot(cfg, cwd, abs)) return
      if (!hasIngestExtension(cfg, abs)) return

      // Make sure the target directory is real. Defensive — edit tool may
      // have created a new nested path.
      if (!existsSync(dirname(abs))) return

      ingestOne(cfg, cwd, abs)
    },
  }
}
