// skill_ref.ts — OpenCode custom tool: load a ref/script/template from a skill.
// SPDX-License-Identifier: Apache-2.0
//
// Purpose: load a specific ref / script / template file from one of the
// installed skills. Works from inside any OpenCode session.
//
// Discovery order (matches OpenCode's 6 skill discovery paths):
//   1. $CWD/.opencode/skills/<skill>/<subpath>
//   2. $HOME/.config/opencode/skills/<skill>/<subpath>
//   3. $CWD/.claude/skills/<skill>/<subpath>
//   4. $HOME/.claude/skills/<skill>/<subpath>
//   5. $CWD/.agents/skills/<skill>/<subpath>
//   6. $HOME/.agents/skills/<skill>/<subpath>
//
// The first matching path wins. Follows symlinks (since the installer
// creates symlinks pointing into the repo).

import { tool } from "@opencode-ai/plugin"
import { readFileSync, existsSync, statSync } from "fs"
import { homedir } from "os"
import { join } from "path"

const DISCOVERY_ROOTS: Array<(cwd: string) => string> = [
  (cwd: string) => join(cwd, ".opencode", "skills"),
  () => join(homedir(), ".config", "opencode", "skills"),
  (cwd: string) => join(cwd, ".claude", "skills"),
  () => join(homedir(), ".claude", "skills"),
  (cwd: string) => join(cwd, ".agents", "skills"),
  () => join(homedir(), ".agents", "skills"),
]

export default tool({
  description:
    "Load a specific reference file, script, or template from an installed skill. " +
    "Use this when the skill's SKILL.md references a file like 'refs/X.md' or " +
    "'templates/Y.yaml' and you need its content. The path is the relative " +
    "subpath within the skill directory (e.g., 'refs/postgresql-design.md').",
  args: {
    skill: tool.schema
      .string()
      .describe(
        "Skill name, matching the skill's directory name (e.g., 'database', 'python').",
      ),
    path: tool.schema
      .string()
      .describe(
        "Subpath within the skill directory (e.g., 'refs/postgresql-design.md'). " +
          "Must NOT start with '/' or contain '..'.",
      ),
  },
  async execute(args, context) {
    // Path-traversal guard — subpath must be relative and contain no ..
    if (args.path.startsWith("/") || args.path.includes("..")) {
      throw new Error(
        `invalid path: ${args.path} (must be relative, no .. segments)`,
      )
    }

    // Skill name validation — matches OpenCode's own regex.
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(args.skill)) {
      throw new Error(`invalid skill name: ${args.skill}`)
    }

    const cwd = context.directory ?? process.cwd()
    const candidates = DISCOVERY_ROOTS.map((fn) =>
      join(fn(cwd), args.skill, args.path),
    )

    for (const candidate of candidates) {
      if (!existsSync(candidate)) continue
      const st = statSync(candidate)
      if (!st.isFile()) continue
      // Size guard — refuse to load files larger than 2 MB.
      if (st.size > 2_000_000) {
        throw new Error(
          `file too large: ${candidate} (${st.size} bytes, max 2MB)`,
        )
      }
      return readFileSync(candidate, "utf8")
    }

    throw new Error(
      `not found: skill '${args.skill}' subpath '${args.path}' in any of the ${candidates.length} discovery roots`,
    )
  },
})
