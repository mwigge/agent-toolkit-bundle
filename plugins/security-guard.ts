// security-guard.ts — OpenCode tool.execute.before security gate.
// SPDX-License-Identifier: Apache-2.0
//
// Blocks edits to protected files, destructive bash commands, and
// hardcoded secrets in edit/write payloads. Every tool call is also
// recorded to .claude/audit.log. Mirrors the security-guard.sh hook.
//
// Install:
//   cp plugins/security-guard.ts ~/.config/opencode/plugin/security-guard.ts

import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, mkdirSync } from "fs"
import { join } from "path"

// Protected file patterns — writing to these is blocked.
const PROTECTED_FILE_PATTERN =
  /\.env$|\.env\.|migrations\/.*\.(sql|py)$|pdm\.lock$|package-lock\.json$|\.claude\/settings\.json$/

// Destructive bash command patterns.
const DESTRUCTIVE_CMD_PATTERN =
  /rm\s+-rf\s+\/|git\s+push\s+--force\s+.*main|drop\s+table|truncate\s+table|format\s+[cCdD]:/i

// Hardcoded secret patterns (in file content).
const SECRET_PATTERN =
  /(api_key|secret_key|password|token)\s*=\s*["'][^$\{][^"']{8,}/i

function auditLog(message: string): void {
  const logDir = join(process.cwd(), ".claude")
  const logFile = join(logDir, "audit.log")
  try {
    mkdirSync(logDir, { recursive: true })
    appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`)
  } catch {
    // Never block on audit failure.
  }
}

export const SecurityGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool
      const args = (output.args ?? {}) as Record<string, unknown>

      const filePath = typeof args.filePath === "string" ? args.filePath : ""
      const command = typeof args.command === "string" ? args.command : ""

      // Audit every call.
      auditLog(
        `TOOL=${tool} FILE=${filePath} CMD=${command.slice(0, 120)}`,
      )

      // ── Bash: block destructive commands ──────────────────────────────────
      if (tool === "bash") {
        if (DESTRUCTIVE_CMD_PATTERN.test(command)) {
          throw new Error(
            `BLOCKED (security-guard): destructive command not permitted — ${command.slice(0, 200)}`,
          )
        }
      }

      // ── Edit / Write: protect sensitive paths ──────────────────────────────
      if (tool === "edit" || tool === "write") {
        if (PROTECTED_FILE_PATTERN.test(filePath)) {
          throw new Error(
            `BLOCKED (security-guard): '${filePath}' is a protected file — edit manually`,
          )
        }

        // Check file content for secrets after write (content available for write tool).
        if (tool === "write") {
          const content = typeof args.content === "string" ? args.content : ""
          if (SECRET_PATTERN.test(content)) {
            throw new Error(
              `BLOCKED (security-guard): potential hardcoded secret detected in content for '${filePath}' — use environment variables`,
            )
          }
        }

        // For edit, check the newString payload.
        if (tool === "edit" && existsSync(filePath)) {
          const newString =
            typeof args.newString === "string" ? args.newString : ""
          if (SECRET_PATTERN.test(newString)) {
            throw new Error(
              `BLOCKED (security-guard): potential hardcoded secret in edit to '${filePath}' — use environment variables`,
            )
          }
        }
      }
    },
  }
}
