import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, appendFileSync, mkdirSync, existsSync } from "fs"
import { homedir } from "os"
import { join } from "path"

interface PiiPattern {
  name: string
  pattern: string
  luhn?: boolean
  allowlist?: string[]
  context_required?: string
}

const PATTERNS_PATH = join(homedir(), ".claude", "pii-patterns.json")
const ALLOWLIST_PATH = join(homedir(), ".claude", "pii-guard-allowlist.txt")

function loadPatterns(): PiiPattern[] {
  try {
    return JSON.parse(readFileSync(PATTERNS_PATH, "utf8"))
  } catch {
    return []
  }
}

function loadAllowlist(): string[] {
  try {
    return readFileSync(ALLOWLIST_PATH, "utf8")
      .split("\n")
      .filter((l) => l.trim() && !l.startsWith("#"))
  } catch {
    return []
  }
}

function luhnValid(num: string): boolean {
  const digits = num.replace(/[\s-]/g, "")
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = parseInt(digits[i], 10)
    if (alt) {
      d *= 2
      if (d > 9) d -= 9
    }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}

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

function extractText(tool: string, args: Record<string, unknown>): string {
  if (!args || typeof args !== "object") return ""
  try {
    if (tool === "bash") return (args.command as string) ?? ""
    if (tool === "agent") return ((args.prompt as string) ?? "") + " " + ((args.description as string) ?? "")
  } catch { /* ignore */ }
  return ""
}

export const PiiGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool?.toLowerCase() ?? ""
      if (tool !== "bash" && tool !== "agent") return

      const args = (input?.args ?? {}) as Record<string, unknown>
      const text = extractText(tool, args)
      if (!text) return

      const patterns = loadPatterns()
      if (patterns.length === 0) return

      const allowlist = loadAllowlist()

      for (const p of patterns) {
        if (p.context_required) {
          const ctxRe = new RegExp(p.context_required, "i")
          if (!ctxRe.test(text)) continue
        }

        const re = new RegExp(p.pattern, "g")
        let match: RegExpExecArray | null
        while ((match = re.exec(text)) !== null) {
          const matchStr = match[0]

          if (p.allowlist) {
            const skip = p.allowlist.some((al) =>
              matchStr.toLowerCase().includes(al.toLowerCase()),
            )
            if (skip) continue
          }

          if (allowlist.some((al) => matchStr.includes(al))) continue

          if (p.luhn && !luhnValid(matchStr)) continue

          const redacted = matchStr.slice(0, 4) + "****"

          auditLog(
            `PII-GUARD BLOCKED pattern=${p.name} indicator=${redacted} tool=${tool} risk=3`,
          )

          throw new Error(
            `BLOCKED: PII detected (${p.name}) — redact the sensitive data and retry. The matched content was NOT logged.`,
          )
        }
      }
    },
  }
}
