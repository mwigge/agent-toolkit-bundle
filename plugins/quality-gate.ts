import type { Plugin } from "@opencode-ai/plugin"
import { execSync } from "child_process"
import { existsSync, readFileSync } from "fs"
import { join } from "path"

// ── Detectors ─────────────────────────────────────────────────────────────────

function hasPrintInLibCode(filePath: string): string | null {
  if (filePath.includes("test") || filePath.includes("spec")) return null
  try {
    const lines = readFileSync(filePath, "utf8").split("\n")
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (/^\s*print\(/.test(line) && !line.trimStart().startsWith("#")) {
        return `Line ${i + 1}: print() in library code — use structured logging`
      }
    }
  } catch { /* ignore */ }
  return null
}

function hasBareExcept(filePath: string): string | null {
  try {
    const lines = readFileSync(filePath, "utf8").split("\n")
    for (let i = 0; i < lines.length; i++) {
      if (/^\s*except\s*:/.test(lines[i])) {
        return `Line ${i + 1}: bare except: — catch specific exceptions`
      }
    }
  } catch { /* ignore */ }
  return null
}

function hasDeprecatedTyping(filePath: string): string | null {
  try {
    const lines = readFileSync(filePath, "utf8").split("\n")
    for (let i = 0; i < lines.length; i++) {
      if (/from typing import.*\b(Dict|List|Tuple|Set|Optional)\b/.test(lines[i])) {
        return `Line ${i + 1}: deprecated typing.Dict/List/Optional — use dict / list / X | None (Python 3.10+)`
      }
    }
  } catch { /* ignore */ }
  return null
}

function hasConsoleLog(filePath: string): string | null {
  if (filePath.includes(".test.") || filePath.includes(".spec.")) return null
  try {
    const lines = readFileSync(filePath, "utf8").split("\n")
    for (let i = 0; i < lines.length; i++) {
      if (/console\.(log|error|warn|info|debug)\(/.test(lines[i])) {
        return `Line ${i + 1}: console.log in src/ — use structured logger`
      }
    }
  } catch { /* ignore */ }
  return null
}

function runTsc(cwd: string): string | null {
  if (!existsSync(join(cwd, "tsconfig.json"))) return null
  try {
    execSync("npx --no-install tsc --noEmit", { cwd, stdio: "pipe", timeout: 30000 })
    return null
  } catch (err: unknown) {
    const e = err as { stderr?: Buffer; stdout?: Buffer }
    const output = (e.stderr?.toString() ?? "") + (e.stdout?.toString() ?? "")
    return `tsc --noEmit failed:\n${output.slice(0, 500)}`
  }
}

function runEslint(filePath: string, cwd: string): string | null {
  const eslintConfigs = [
    "eslint.config.js", "eslint.config.mjs", "eslint.config.ts",
    ".eslintrc", ".eslintrc.json", ".eslintrc.js", ".eslintrc.cjs",
  ]
  const hasConfig = eslintConfigs.some((c) => existsSync(join(cwd, c)))
  if (!hasConfig) return null
  const eslintBin = join(cwd, "node_modules", ".bin", "eslint")
  if (!existsSync(eslintBin)) return null
  try {
    execSync(`${eslintBin} --max-warnings=0 "${filePath}"`, { cwd, stdio: "pipe", timeout: 20000 })
    return null
  } catch (err: unknown) {
    const e = err as { stderr?: Buffer; stdout?: Buffer }
    const output = (e.stdout?.toString() ?? "") + (e.stderr?.toString() ?? "")
    // Distinguish errors (exit 1) from warnings (exit 2 / max-warnings)
    return `ESLint errors on ${filePath.split("/").pop()}:\n${output.slice(0, 400)}`
  }
}

// ── Plugin ────────────────────────────────────────────────────────────────────

export const QualityGatePlugin: Plugin = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      const tool = input.tool
      if (tool !== "edit" && tool !== "write") return

      const args = (input.args ?? output.args ?? {}) as Record<string, string>
      const filePath: string = args.filePath ?? ""
      if (!filePath || !existsSync(filePath)) return

      const ext = filePath.split(".").pop() ?? ""
      const cwd = process.cwd()
      const issues: string[] = []

      // ── Python ──────────────────────────────────────────────────────────────
      if (ext === "py") {
        const p = hasPrintInLibCode(filePath)
        if (p) issues.push(p)
        const b = hasBareExcept(filePath)
        if (b) issues.push(b)
        const d = hasDeprecatedTyping(filePath)
        if (d) issues.push(d)
      }

      // ── TypeScript ──────────────────────────────────────────────────────────
      if (ext === "ts" || ext === "tsx") {
        const c = hasConsoleLog(filePath)
        if (c) issues.push(c)
        const eslint = runEslint(filePath, cwd)
        if (eslint) issues.push(eslint)
        // tsc is expensive — only run on .ts files, not .tsx to avoid double-hit
        if (ext === "ts") {
          const tsc = runTsc(cwd)
          if (tsc) issues.push(tsc)
        }
      }

      // ── Surface as error forcing self-correction ─────────────────────────────
      if (issues.length > 0) {
        const name = filePath.split("/").pop()
        throw new Error(
          `QUALITY GATE — fix before continuing (${name}):\n` +
          issues.map((i) => `  • ${i}`).join("\n"),
        )
      }
    },
  }
}
