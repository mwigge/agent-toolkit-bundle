// skill_list_refs.ts — OpenCode custom tool: enumerate assets of a skill.
// SPDX-License-Identifier: Apache-2.0
//
// Purpose: enumerate the non-SKILL.md assets of an installed skill.
// Returns a tree listing of files under refs/, scripts/, templates/
// (or any other subdir) inside the skill's directory, using the same
// 6-path discovery order as skill_ref.ts.

import { tool } from "@opencode-ai/plugin"
import { readdirSync, existsSync, statSync } from "fs"
import { homedir } from "os"
import { join, relative } from "path"

const DISCOVERY_ROOTS: Array<(cwd: string) => string> = [
  (cwd: string) => join(cwd, ".opencode", "skills"),
  () => join(homedir(), ".config", "opencode", "skills"),
  (cwd: string) => join(cwd, ".claude", "skills"),
  () => join(homedir(), ".claude", "skills"),
  (cwd: string) => join(cwd, ".agents", "skills"),
  () => join(homedir(), ".agents", "skills"),
]

function walk(dir: string, base: string, acc: string[], depth: number): void {
  if (depth > 5) return // cap recursion
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "SKILL.md") continue
    if (entry.name.startsWith(".")) continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) {
      walk(full, base, acc, depth + 1)
    } else if (entry.isFile()) {
      acc.push(relative(base, full))
    }
  }
}

export default tool({
  description:
    "List the non-SKILL.md files (refs, scripts, templates, etc.) available " +
    "inside an installed skill's directory. Use this before calling skill_ref " +
    "if you don't know the exact path of a ref you need.",
  args: {
    skill: tool.schema
      .string()
      .describe("Skill name, matching the skill's directory name."),
  },
  async execute(args, context) {
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(args.skill)) {
      throw new Error(`invalid skill name: ${args.skill}`)
    }

    const cwd = context.directory ?? process.cwd()

    for (const rootFn of DISCOVERY_ROOTS) {
      const skillDir = join(rootFn(cwd), args.skill)
      if (!existsSync(skillDir)) continue
      const st = statSync(skillDir)
      if (!st.isDirectory()) continue
      const acc: string[] = []
      walk(skillDir, skillDir, acc, 0)
      return acc.sort().join("\n")
    }

    throw new Error(`skill not found: ${args.skill}`)
  },
})
