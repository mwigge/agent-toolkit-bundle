import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync } from "fs"
import { homedir } from "os"
import { join } from "path"

// Company paths: /dev/src/{ghorg,docs_local,chaostooling*,tokens,scripts}
// Private paths: /dev/src/{pprojects,api_projects}
// Neutral: /dev/src/ai_local, ~/.ssh, ~/.claude, ~/.config, everything else

const COMPANY_PATTERN = /dev\/src\/(ghorg|docs_local|chaostooling[^/]*|tokens|scripts)(\/|$)/
const PRIVATE_PATTERN = /dev\/src\/(pprojects|api_projects)(\/|$)/

function readMode(): string {
  try {
    return readFileSync(join(homedir(), ".claude", "mode"), "utf8").trim()
  } catch {
    return "company"
  }
}

function checkPath(path: string, mode: string): string | null {
  if (!path) return null
  if (COMPANY_PATTERN.test(path) && mode === "private") {
    return `'${path}' is a COMPANY path but mode is PRIVATE`
  }
  if (PRIVATE_PATTERN.test(path) && mode === "company") {
    return `'${path}' is a PRIVATE path but mode is COMPANY`
  }
  return null
}

export const ModeGuardPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const mode = readMode()
      const tool = input.tool

      // Edit / Write: check target file path
      if (tool === "edit" || tool === "write") {
        const filePath: string = (output.args as Record<string, string>).filePath ?? ""
        const violation = checkPath(filePath, mode)
        if (violation) {
          throw new Error(
            `BLOCKED (mode-guard): ${violation}\nCurrent mode: ${mode}. Switch with: mode company  |  mode private`,
          )
        }
      }

      // Bash: scan command string for dev/src/<path> patterns
      if (tool === "bash") {
        const command: string = (output.args as Record<string, string>).command ?? ""
        // Extract all dev/src/... path fragments from the command
        const matches = command.match(/(?:\/Users\/\w+|\$HOME|~)?(?:\/)?dev\/src\/[\w./-]+/g) ?? []
        for (const match of matches) {
          const violation = checkPath(match, mode)
          if (violation) {
            throw new Error(
              `BLOCKED (mode-guard): ${violation}\nCurrent mode: ${mode}. Switch with: mode company  |  mode private`,
            )
          }
        }
      }
    },
  }
}
