// format-on-save.ts — OpenCode tool.execute.after auto-formatter.
// SPDX-License-Identifier: Apache-2.0
//
// Runs language-appropriate formatters after edit/write tool calls.
// Mirrors the format-on-save.sh hook. Never throws — format failures
// are advisory and must not block the tool pipeline.
//
// Install:
//   cp plugins/format-on-save.ts ~/.config/opencode/plugin/format-on-save.ts
//
// OpenCode auto-loads any plugin in that directory on startup.

import type { Plugin } from "@opencode-ai/plugin"
import { execFileSync } from "child_process"
import { existsSync } from "fs"

// Fixed argv only — never interpolate model-chosen paths into a shell
// string. Prevents command injection via prompt-injected filePath.
function tryFormat(bin: string, args: string[]): void {
  try {
    execFileSync(bin, args, { stdio: "pipe", timeout: 30000 })
  } catch {
    // Format failures are never blockers — degrade silently.
  }
}

function hasCmd(cmd: string): boolean {
  try {
    execFileSync("command", ["-v", cmd], { stdio: "pipe", shell: "/bin/sh" })
    return true
  } catch {
    return false
  }
}

export const FormatOnSavePlugin: Plugin = async () => {
  return {
    "tool.execute.after": async (input, _output) => {
      const tool = input.tool
      if (tool !== "edit" && tool !== "write") return

      // tool.execute.after: args live on input.args (read-only).
      const args = (input.args ?? {}) as Record<string, unknown>
      const filePath = typeof args.filePath === "string" ? args.filePath : ""
      if (!filePath || !existsSync(filePath)) return

      const ext = filePath.split(".").pop() ?? ""

      switch (ext) {
        case "py":
          if (hasCmd("ruff")) {
            tryFormat("ruff", ["check", "--fix", "--quiet", filePath])
            tryFormat("ruff", ["format", "--quiet", filePath])
          }
          if (hasCmd("black")) {
            tryFormat("black", ["--quiet", filePath])
          }
          break

        case "ts":
        case "tsx":
        case "js":
        case "jsx":
        case "mjs":
        case "cjs":
          if (hasCmd("prettier")) {
            tryFormat("prettier", ["--write", "--log-level", "silent", filePath])
          }
          break

        case "json":
        case "yaml":
        case "yml":
          if (hasCmd("prettier")) {
            tryFormat("prettier", ["--write", "--log-level", "silent", filePath])
          }
          break

        case "sql":
          if (hasCmd("sqlfluff")) {
            tryFormat("sqlfluff", ["fix", "--dialect", "postgres", "--quiet", filePath])
          }
          break
      }

      // Always exit cleanly — format-on-save never blocks.
    },
  }
}
