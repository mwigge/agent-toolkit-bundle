import type { Plugin } from "@opencode-ai/plugin"
import { execSync } from "child_process"
import { existsSync } from "fs"
import { join } from "path"

export const CheckAlembicSync: Plugin = async () => {
  return {
    "tool.execute.before": async (_input, output) => {
      const tool = _input.tool
      if (tool !== "bash") return

      const command: string = (output.args as Record<string, string>).command ?? ""
      if (!command.includes("git commit")) return

      const cwd = process.cwd()
      if (!existsSync(join(cwd, "alembic", "versions"))) return

      let stagedSql: string
      let stagedAlembic: string
      try {
        stagedSql = execSync("git diff --cached --name-only --diff-filter=A", { cwd })
          .toString()
          .split("\n")
          .filter((f) => /^migrations\/.*\.sql$/.test(f))
          .join("\n")
          .trim()
      } catch {
        return
      }

      if (!stagedSql) return

      try {
        stagedAlembic = execSync("git diff --cached --name-only --diff-filter=A", { cwd })
          .toString()
          .split("\n")
          .filter((f) => /^alembic\/versions\/.*\.py$/.test(f))
          .join("\n")
          .trim()
      } catch {
        stagedAlembic = ""
      }

      if (!stagedAlembic) {
        throw new Error(
          `BLOCKED: New SQL migration(s) staged without a matching Alembic version file.\n\n` +
          `  Staged SQL files:\n` +
          stagedSql.split("\n").map((f) => `    ${f}`).join("\n") +
          `\n\n  Create alembic/versions/XXXX_*.py covering the SQL, then re-stage.`
        )
      }
    },
  }
}
