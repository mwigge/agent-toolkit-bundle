// inline-quality.ts — OpenCode tool.execute.after advisory linter.
// SPDX-License-Identifier: Apache-2.0
//
// Surfaces common quality issues by appending them to the tool's
// output string so the model sees them in the tool result. Does NOT
// throw — non-blocking by design. quality-gate.ts handles the blocking
// enforcement on the same events. Together they mirror the shell-hook
// pair: inline-quality.sh (advisory) + quality-gate.sh (blocking).
//
// NOTE: No console.* — OpenCode plugins share stderr with the TUI.
//       Feedback is injected into output.output for the model to read.
//
// Install:
//   cp plugins/inline-quality.ts ~/.config/opencode/plugin/inline-quality.ts

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync, appendFileSync, mkdirSync } from "fs"
import { join } from "path"

interface Issue {
  line: number
  message: string
}

function scanLines(filePath: string, pattern: RegExp, skip?: RegExp): Issue[] {
  const issues: Issue[] = []
  try {
    const lines = readFileSync(filePath, "utf8").split("\n")
    for (let i = 0; i < lines.length; i++) {
      if (skip && skip.test(lines[i])) continue
      if (pattern.test(lines[i])) {
        issues.push({ line: i + 1, message: lines[i].trim().slice(0, 120) })
      }
    }
  } catch {
    // Ignore unreadable files.
  }
  return issues
}

function logHint(cwd: string, hint: string): void {
  const logDir = join(cwd, ".claude", "logs")
  try {
    mkdirSync(logDir, { recursive: true })
    appendFileSync(
      join(logDir, "inline-quality.log"),
      `${new Date().toISOString()} ${hint}\n`,
    )
  } catch {
    // Ignore log failures.
  }
}

export const InlineQualityPlugin: Plugin = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      const tool = input.tool
      if (tool !== "edit" && tool !== "write") return

      // tool.execute.after: args live on input.args (read-only).
      const args = (input.args ?? {}) as Record<string, unknown>
      const filePath = typeof args.filePath === "string" ? args.filePath : ""
      if (!filePath || !existsSync(filePath)) return

      const ext = filePath.split(".").pop() ?? ""
      const isTest = filePath.includes("test") || filePath.includes("spec")
      const fileName = filePath.split("/").pop() ?? filePath
      const hints: string[] = []

      // ── Python advisory checks ──────────────────────────────────────────────
      if (ext === "py") {
        if (!isTest) {
          const prints = scanLines(filePath, /^\s*print\(/, /^\s*#/)
          if (prints.length > 0) {
            hints.push(
              `  Line ${prints[0].line}: print() in library code — replace with structured logger (logger.info / logger.debug)`,
            )
          }
        }

        const bareExcept = scanLines(filePath, /^\s*except\s*:/)
        if (bareExcept.length > 0) {
          hints.push(
            `  Line ${bareExcept[0].line}: bare except: — catch a specific exception (e.g. except ValueError:)`,
          )
        }

        const deprecatedTyping = scanLines(
          filePath,
          /from typing import.*\b(Dict|List|Tuple|Set|Optional)\b/,
        )
        if (deprecatedTyping.length > 0) {
          hints.push(
            `  Line ${deprecatedTyping[0].line}: deprecated typing.Dict/List/Optional — use dict / list / X | None (Python 3.10+)`,
          )
        }

        const secrets = scanLines(
          filePath,
          /(api_key|secret_key|password|token)\s*=\s*["'][^$\{][^"']{8,}/i,
        )
        if (secrets.length > 0) {
          hints.push(
            `  Line ${secrets[0].line}: potential hardcoded secret — use environment variable instead`,
          )
        }

        const sqlInterp = scanLines(
          filePath,
          /cursor\.execute\(f"|cursor\.execute\(.*%\s*[a-z]/,
        )
        if (sqlInterp.length > 0) {
          hints.push(
            `  Line ${sqlInterp[0].line}: non-parameterised SQL — use cursor.execute('... WHERE id = %s', (val,))`,
          )
        }
      }

      // ── TypeScript advisory checks ──────────────────────────────────────────
      if (ext === "ts" || ext === "tsx") {
        if (!isTest) {
          const consoleLogs = scanLines(
            filePath,
            /console\.(log|error|warn|info|debug)\(/,
          )
          if (consoleLogs.length > 0) {
            hints.push(
              `  Line ${consoleLogs[0].line}: console.log in src/ — use structured logger`,
            )
          }
        }

        const anyUsage = scanLines(filePath, /:\s*any\b/, /\/\/ any:/)
        if (anyUsage.length > 0) {
          hints.push(
            `  Line ${anyUsage[0].line}: use of 'any' — provide explicit type or add // any: <justification> comment`,
          )
        }
      }

      if (hints.length > 0) {
        const cwd = process.cwd()
        const msg = `\n\nINLINE QUALITY FEEDBACK for ${fileName}:\n${hints.join("\n")}\nFix these issues before moving on.`
        logHint(cwd, msg.trim())
        // Append to the tool's output so the model sees it in the tool result.
        const previous = typeof output.output === "string" ? output.output : ""
        output.output = previous + msg
      }
    },
  }
}
