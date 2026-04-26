import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "fs"
import { homedir } from "os"
import { join, dirname } from "path"

// Protected file patterns — writing to these is blocked
const PROTECTED_FILE_PATTERN =
  /\.env$|\.env\.|migrations\/.*\.(sql|py)$|pdm\.lock$|package-lock\.json$|\.claude\/settings\.json$/

// Destructive bash command patterns
const DESTRUCTIVE_CMD_PATTERN =
  /rm\s+-rf\s+\/|git\s+push\s+--force\s+.*main|drop\s+table|truncate\s+table|format\s+[cCdD]:/i

// Hardcoded secret patterns (in file content)
const SECRET_PATTERN =
  /(api_key|secret_key|password|token)\s*=\s*["'][^$\{][^"']{8,}/i

function auditLog(message: string): void {
  const logDir = join(process.cwd(), ".claude")
  const logFile = join(logDir, "audit.log")
  try {
    mkdirSync(logDir, { recursive: true })
    appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`)
  } catch {
    // never block on audit failure
  }
}

function checkFileForSecrets(filePath: string): boolean {
  try {
    const content = readFileSync(filePath, "utf8")
    return SECRET_PATTERN.test(content)
  } catch {
    return false
  }
}

export const SecurityGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool ?? ""
      const args = ((output?.args ?? input?.args ?? {}) as Record<string, string>) ?? {}

      // Audit every call
      auditLog(`TOOL=${tool} FILE=${args.filePath ?? ""} CMD=${(args.command ?? "").slice(0, 120)}`)

      // ── Bash: block destructive commands ──────────────────────────────────
      if (tool === "bash") {
        const command = args.command ?? ""
        if (DESTRUCTIVE_CMD_PATTERN.test(command)) {
          throw new Error(
            `BLOCKED (security-guard): destructive command not permitted — ${command.slice(0, 200)}`,
          )
        }
      }

      // ── Edit / Write: protect sensitive paths ──────────────────────────────
      if (tool === "edit" || tool === "write") {
        const filePath = args.filePath ?? ""

        if (PROTECTED_FILE_PATTERN.test(filePath)) {
          throw new Error(
            `BLOCKED (security-guard): '${filePath}' is a protected file — edit manually`,
          )
        }

        // Check file content for secrets after write (content available for write tool)
        if (tool === "write") {
          const content = args.content ?? ""
          if (SECRET_PATTERN.test(content)) {
            throw new Error(
              `BLOCKED (security-guard): potential hardcoded secret detected in content for '${filePath}' — use environment variables`,
            )
          }
        }

        // For edit, check the existing file
        if (tool === "edit" && existsSync(filePath)) {
          // Check newString for secrets
          const newString = args.newString ?? ""
          if (SECRET_PATTERN.test(newString)) {
            throw new Error(
              `BLOCKED (security-guard): potential hardcoded secret in edit to '${filePath}' — use environment variables`,
            )
          }
        }
      }

      // ── Bash: egress allowlisting (Phase 1 — log-only) ─────────────────
      if (tool === "bash") {
        const command: string = args.command ?? ""
        const egressMatch = command.match(
          /(?:curl|wget|ssh|scp)\s+[^|;]*?(?:https?:\/\/)?([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})/,
        )
        if (egressMatch) {
          const host = egressMatch[1]
          const allowlistPath = join(homedir(), ".claude", "egress-allowlist.txt")
          if (existsSync(allowlistPath)) {
            const lines = readFileSync(allowlistPath, "utf8")
              .split("\n")
              .map((l) => l.replace(/#.*/, "").trim())
              .filter(Boolean)
            const allowed = lines.some((entry) => {
              if (entry.startsWith("*")) {
                return host.endsWith(entry.slice(1))
              }
              return host === entry
            })
            if (!allowed) {
              auditLog(`EGRESS-WARNING host=${host} command=${command.slice(0, 80)} risk=2`)
              // Phase 1: log only — Phase 2: throw to block
            }
          }
        }
      }
    },
  }
}
