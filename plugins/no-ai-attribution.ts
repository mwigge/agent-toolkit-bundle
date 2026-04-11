// no-ai-attribution.ts — OpenCode tool.execute.before guard.
// SPDX-License-Identifier: Apache-2.0
//
// Blocks git commits and PR-creation commands that attempt to inject
// AI co-authorship footers or "Generated with ..." lines. Mirrors the
// no-ai-attribution.sh hook. The rule is simple: human-authored history.
//
// Install:
//   cp plugins/no-ai-attribution.ts ~/.config/opencode/plugin/no-ai-attribution.ts

import type { Plugin } from "@opencode-ai/plugin"

// Patterns that indicate AI attribution in git commits or PR creation commands.
const AI_ATTRIBUTION_PATTERN =
  /Co-Authored-By:.*[Cc]laude|Co-Authored-By:.*[Oo]pen[Aa][Ii]|Co-Authored-By:.*[Aa]nthropic|Generated with.*[Cc]laude|Generated with.*AI/i

// Commands that produce git commits or GitHub PRs.
const COMMIT_PR_PATTERN = /git\s+commit|gh\s+pr\s+create/

export const NoAiAttributionPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      // Only gate bash commands.
      if (input.tool !== "bash") return

      const args = (output.args ?? {}) as Record<string, unknown>
      const command = typeof args.command === "string" ? args.command : ""

      // Only check git commit and gh pr create commands.
      if (!COMMIT_PR_PATTERN.test(command)) return

      if (AI_ATTRIBUTION_PATTERN.test(command)) {
        throw new Error(
          "BLOCKED: AI attribution detected in git commit or PR. " +
            "Remove Co-Authored-By, Generated-with footers, or AI references.",
        )
      }
    },
  }
}
