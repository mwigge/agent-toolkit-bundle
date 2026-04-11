// mempalace_query.ts — OpenCode custom tool: full-text search the palace.
// SPDX-License-Identifier: Apache-2.0
//
// Thin wrapper around the MCP mempalace_search tool. Does not interpret
// results — the backend owns ranking and relevance. Returns the raw JSON
// response (trimmed to an output budget) so the LLM can read and reason
// over it.

import { tool } from "@opencode-ai/plugin"
import { execFileSync } from "child_process"
import { existsSync, readFileSync } from "fs"
import { homedir } from "os"
import { join } from "path"

const MAX_OUTPUT_BYTES = 256 * 1024
const CALL_TIMEOUT_MS = 15_000
const DEFAULT_LIMIT = 10

interface PalaceTransport {
  mcpUrl: string
  mcpToken: string
  cli: string
}

function loadTransport(): PalaceTransport {
  const configPath =
    process.env.MEMPALACE_CONFIG ??
    join(homedir(), ".agents", "mempalace", "config", "mempalace.conf")

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
        if (key === "MCP_URL") mcpUrlFromFile = value
        else if (key === "MCP_TOKEN") mcpTokenFromFile = value
      }
    } catch {
      // Degrade silently on config read failure.
    }
  }

  return {
    mcpUrl: process.env.MEMPALACE_MCP_URL ?? mcpUrlFromFile,
    mcpToken: process.env.MEMPALACE_MCP_TOKEN ?? mcpTokenFromFile,
    cli: process.env.MEMPALACE_CLI ?? "mempalace",
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

function callViaCli(cli: string, payload: string): string {
  const out = execFileSync(cli, ["call", "mempalace_search"], {
    input: payload,
    timeout: CALL_TIMEOUT_MS,
    stdio: ["pipe", "pipe", "pipe"],
    maxBuffer: MAX_OUTPUT_BYTES,
  })
  return out.toString("utf8")
}

function callViaHttp(
  url: string,
  token: string,
  toolName: string,
  args: Record<string, unknown>,
): string {
  const body = JSON.stringify({ tool: toolName, arguments: args })
  const curlArgs = [
    "-sS",
    "--max-time",
    String(Math.ceil(CALL_TIMEOUT_MS / 1000)),
    "-H",
    "Content-Type: application/json",
  ]
  if (token) curlArgs.push("-H", `Authorization: Bearer ${token}`)
  curlArgs.push("-X", "POST", "--data", body, `${url}/tools/call`)
  const out = execFileSync("curl", curlArgs, {
    timeout: CALL_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: MAX_OUTPUT_BYTES,
  })
  return out.toString("utf8")
}

export default tool({
  description:
    "Search the MemPalace (persistent cross-session memory) via the BYO MCP " +
    "server. Returns the raw JSON response from mempalace_search, including " +
    "matching drawer contents and metadata. Use when the user asks about " +
    "prior decisions, notes, or diary entries.",
  args: {
    query: tool.schema
      .string()
      .describe(
        "Free-text search query. Passed verbatim to the MCP mempalace_search tool.",
      ),
    limit: tool.schema
      .number()
      .optional()
      .describe("Maximum number of results to return. Defaults to 10, capped at 100."),
  },
  async execute(args, _context) {
    const trimmed = args.query.trim()
    if (!trimmed) {
      throw new Error("query must not be empty")
    }

    const limit = Math.max(1, Math.min(args.limit ?? DEFAULT_LIMIT, 100))
    const transport = loadTransport()

    const payload = { query: trimmed, limit }
    const payloadJson = JSON.stringify(payload)

    try {
      if (hasBinary(transport.cli)) {
        return callViaCli(transport.cli, payloadJson).trim()
      }
      if (!transport.mcpUrl) {
        throw new Error(
          "MemPalace is unconfigured: set MEMPALACE_MCP_URL or install a " +
            "'mempalace' CLI wrapper on PATH.",
        )
      }
      if (!hasBinary("curl")) {
        throw new Error("curl is required for HTTP transport and was not found")
      }
      return callViaHttp(
        transport.mcpUrl,
        transport.mcpToken,
        "mempalace_search",
        payload,
      ).trim()
    } catch (err) {
      const e = err as { message?: string }
      throw new Error(`mempalace_search failed: ${e.message ?? "unknown error"}`)
    }
  },
})
