import type { Plugin } from "@opencode-ai/plugin"
import { execFile } from "child_process"
import { existsSync, statSync, readdirSync, readFileSync } from "fs"
import { homedir } from "os"
import { join } from "path"

const PYTHON_PYENV = join(homedir(), ".pyenv", "versions", "3.12.13", "bin", "python3")
const DOCS_LOCAL_CANDIDATES = [
  join(homedir(), "dev", "src", "docs_local"),
]
const MINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000  // 7 days
const TASKS_MAX_LINES = 150

function resolvePython(): string | null {
  if (existsSync(PYTHON_PYENV)) return PYTHON_PYENV
  // Fall back: check if python3 on PATH can import mempalace
  return null  // BunShell not available at module level; rely on pyenv path
}

function findDocsLocal(): string | null {
  for (const candidate of DOCS_LOCAL_CANDIDATES) {
    if (existsSync(candidate)) return candidate
  }
  return null
}

function lineCount(filePath: string): number {
  try {
    const content = readFileSync(filePath, "utf8")
    return content.split("\n").length
  } catch {
    return 999
  }
}

function recentlyModified(dirPath: string): boolean {
  try {
    const stat = statSync(dirPath)
    return Date.now() - stat.mtimeMs < MINE_WINDOW_MS
  } catch {
    return false
  }
}

function mineFile(python: string, filePath: string): Promise<boolean> {
  return new Promise((resolve) => {
    execFile(python, ["-m", "mempalace", "mine", filePath], { timeout: 15000 }, (err) => {
      resolve(!err)
    })
  })
}

export const MempalaceIngestPlugin: Plugin = async () => {
  return {
    "experimental.session.compacting": async (input, _output) => {
      const python = resolvePython()
      if (!python) return

      const docsLocal = findDocsLocal()
      if (!docsLocal) return

      const changesDir = join(docsLocal, "openspec", "changes")
      const memoryFile = join(homedir(), "dev", "src", "ai_local", "memory.md")

      const mines: Promise<boolean>[] = []

      // Mine recently modified OpenSpec change dirs
      if (existsSync(changesDir)) {
        const entries = readdirSync(changesDir, { withFileTypes: true })
        for (const entry of entries) {
          if (!entry.isDirectory() || entry.name === "archive") continue
          const changeDir = join(changesDir, entry.name)
          if (!recentlyModified(changeDir)) continue

          for (const artifact of ["proposal.md", "design.md", "delivery.md"]) {
            const f = join(changeDir, artifact)
            if (existsSync(f)) mines.push(mineFile(python, f))
          }

          const tasksFile = join(changeDir, "tasks.md")
          if (existsSync(tasksFile) && lineCount(tasksFile) < TASKS_MAX_LINES) {
            mines.push(mineFile(python, tasksFile))
          }
        }
      }

      // Mine memory.md
      if (existsSync(memoryFile)) {
        mines.push(mineFile(python, memoryFile))
      }

      // Fire and forget — compaction should not be blocked by mining
      Promise.all(mines).catch(() => {/* ignore */})
    },
  }
}
