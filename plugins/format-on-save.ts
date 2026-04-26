import type { Plugin } from "@opencode-ai/plugin"
import { execSync } from "child_process"
import { existsSync } from "fs"

function tryFormat(cmd: string): void {
  try {
    execSync(cmd, { stdio: "pipe", timeout: 30000 })
  } catch {
    // format failures are never blockers — degrade silently
  }
}

function hasCmd(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, { stdio: "pipe" })
    return true
  } catch {
    return false
  }
}

export const FormatOnSavePlugin: Plugin = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      const tool = input.tool
      if (tool !== "edit" && tool !== "write") return

      const args = input.args as Record<string, string>
      const filePath: string = args.filePath ?? ""
      if (!filePath || !existsSync(filePath)) return

      const ext = filePath.split(".").pop() ?? ""

      switch (ext) {
        case "py":
          if (hasCmd("ruff")) {
            tryFormat(`ruff check --fix --quiet "${filePath}"`)
            tryFormat(`ruff format --quiet "${filePath}"`)
          }
          if (hasCmd("black")) {
            tryFormat(`black --quiet "${filePath}"`)
          }
          break

        case "ts":
        case "tsx":
        case "js":
        case "jsx":
        case "mjs":
        case "cjs":
          if (hasCmd("prettier")) {
            tryFormat(`prettier --write --log-level silent "${filePath}"`)
          }
          break

        case "json":
        case "yaml":
        case "yml":
          if (hasCmd("prettier")) {
            tryFormat(`prettier --write --log-level silent "${filePath}"`)
          }
          break

        case "sql":
          if (hasCmd("sqlfluff")) {
            tryFormat(`sqlfluff fix --dialect postgres --quiet "${filePath}"`)
          }
          break
      }

      // Always exit cleanly — format-on-save never blocks
    },
  }
}
