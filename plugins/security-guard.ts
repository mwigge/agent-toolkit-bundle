import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, mkdirSync, readFileSync, realpathSync } from "fs"
import { homedir } from "os"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

// NOTE: the destructive-command and egress regexes below are best-effort
// tripwires, not a security boundary — they catch common cases (`rm -rf /`,
// force-push to main) but variants (`rm -fr /`, `find / -delete`, raw-IP
// URLs, `nc`/python egress) can slip through. The bash hooks'
// permission-autoapprove RED/escalation tiers and human review are the real
// boundary.

// ── Shared policy patterns ───────────────────────────────────────────────────
// policy/guard-patterns.json is the single source of truth for these regexes
// (shared with hooks/security-guard.sh and hooks/permission-autoapprove.sh).
// Fall back to the previous hardcoded values if the file is missing or
// unreadable so this plugin degrades gracefully instead of failing outright.
const FALLBACK_PROTECTED_FILE_PATTERN =
  "\\.env$|\\.env\\.|migrations/.*\\.(sql|py)$|pdm\\.lock$|package-lock\\.json$|\\.claude/settings\\.json$"
const FALLBACK_DESTRUCTIVE_CMD_PATTERN =
  "rm\\s+-rf\\s+/|git\\s+push\\s+--force\\s+.*main|drop\\s+table|truncate\\s+table|format\\s+[cCdD]:"
const FALLBACK_SECRET_PATTERN =
  "(api_key|secret_key|password|token)\\s*=\\s*[\"'][^$\\{][^\"']{8,}"

function loadPolicy(): Record<string, unknown> {
  try {
    const scriptPath = realpathSync(fileURLToPath(import.meta.url))
    const policyPath = join(dirname(scriptPath), "..", "policy", "guard-patterns.json")
    return JSON.parse(readFileSync(policyPath, "utf8")) as Record<string, unknown>
  } catch {
    return {}
  }
}

function buildPattern(arr: unknown, fallback: string, flags: string): RegExp {
  if (Array.isArray(arr) && arr.length > 0 && arr.every((p) => typeof p === "string")) {
    return new RegExp((arr as string[]).join("|"), flags)
  }
  return new RegExp(fallback, flags)
}

const POLICY = loadPolicy()

// Protected file patterns — writing to these is blocked
const PROTECTED_FILE_PATTERN = buildPattern(POLICY.protected_files, FALLBACK_PROTECTED_FILE_PATTERN, "")

// Destructive bash command patterns
const DESTRUCTIVE_CMD_PATTERN = buildPattern(POLICY.destructive_commands, FALLBACK_DESTRUCTIVE_CMD_PATTERN, "i")

// Hardcoded secret patterns (in file content)
const SECRET_PATTERN = new RegExp(
  typeof POLICY.secret_pattern === "string" ? POLICY.secret_pattern : FALLBACK_SECRET_PATTERN,
  "i",
)

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
        // Extract every hostname seen in curl/wget/ssh/scp invocations (not
        // just the first) so e.g. `curl a.com b.evil.com` is fully checked.
        const egressCmds = command.match(/(?:curl|wget|ssh|scp)\s+[^|;]*/g) ?? []
        const hosts = new Set<string>()
        for (const cmd of egressCmds) {
          for (const m of cmd.matchAll(/(?:https?:\/\/)?([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})/g)) {
            hosts.add(m[1])
          }
        }
        if (hosts.size > 0) {
          const allowlistPath = join(homedir(), ".claude", "egress-allowlist.txt")
          if (existsSync(allowlistPath)) {
            const lines = readFileSync(allowlistPath, "utf8")
              .split("\n")
              .map((l) => l.replace(/#.*/, "").trim())
              .filter(Boolean)
            for (const host of hosts) {
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
      }
    },
  }
}
