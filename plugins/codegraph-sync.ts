import type { Plugin } from "@opencode-ai/plugin"
import { execSync } from "child_process"

// codegraph-sync.ts — incremental codegraph sync on git add (mirrors codegraph-sync.sh)
// After a bash tool call containing `git add`, runs `codegraph sync` to keep
// the code knowledge graph up-to-date with staged changes.
// Never throws — sync failures are silently ignored.

function hasCmd(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, { stdio: "pipe" })
    return true
  } catch {
    return false
  }
}

const GIT_ADD_RE = /(^|\s|&&|\||\;)git\s+add(\s|$)/

export const CodeGraphSyncPlugin: Plugin = async () => {
  return {
    "tool.execute.after": async (input, _output) => {
      if (input.tool !== "bash") return

      const args = input.args as Record<string, string>
      const command = args.command ?? ""
      if (!command || !GIT_ADD_RE.test(command)) return

      if (!hasCmd("codegraph")) return

      try {
        execSync("codegraph sync", {
          stdio: "pipe",
          timeout: 15000,
          cwd: process.cwd(),
        })
      } catch {
        // sync failures are never blockers
      }
    },
  }
}
