# Install — CodeGraph

**Package**: `@colbymchenry/codegraph`
**Requires**: Node.js 18 or higher

---

## 1. Install the CLI

CodeGraph is distributed as an npm package and runs on Node.js. The same
package works on macOS and Linux.

### npm (recommended)

```bash
npm install -g @colbymchenry/codegraph@latest
```

### pnpm

```bash
pnpm add -g @colbymchenry/codegraph@latest
```

### yarn

```bash
yarn global add @colbymchenry/codegraph@latest
```

### Linux: ensure Node.js 18+ is available

Most Linux distributions ship an older Node.js. Install a current version via
[nvm](https://github.com/nvm-sh/nvm) or [NodeSource](https://github.com/nodesource/distributions):

```bash
# nvm (macOS + Linux)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 20
nvm use 20
npm install -g @colbymchenry/codegraph@latest

# NodeSource (Debian/Ubuntu)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g @colbymchenry/codegraph@latest

# NodeSource (RHEL/Fedora/CentOS)
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
npm install -g @colbymchenry/codegraph@latest
```

### Verify installation

```bash
codegraph --version
# 0.9.9
```

---

## 2. Initialize a project

Run once per repository. This creates the `.codegraph/` directory and builds
the initial index.

```bash
cd /path/to/your/repo
codegraph init -i
```

Expected output:

```
CodeGraph v0.9.9
Initializing project at /path/to/your/repo
Detected languages: typescript, python
Indexing 89 files...
Done. 1,247 symbols indexed in 3.2s

.codegraph/
├── config.json    ← edit to tune languages and exclusions
└── codegraph.db   ← SQLite index (gitignore this)
```

Add `.codegraph/` to your project's `.gitignore`:

```bash
echo '.codegraph/' >> .gitignore
```

---

## 3. Wire the MCP server into your agent

CodeGraph runs as a stdio MCP server. Register it once per agent install.

### Claude Code

Add to `.mcp.json` in your project root (or `~/.claude/mcp.json` globally):

```json
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"],
      "type": "stdio"
    }
  }
}
```

### OpenCode

Add to `.opencode.json` in your project root (or `~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"],
      "type": "stdio"
    }
  }
}
```

### Codex

Add to `.codex/config.toml`:

```toml
[[mcp_servers]]
name = "codegraph"
command = "codegraph"
args = ["serve", "--mcp"]
```

### Verify MCP registration

Start a session and call `codegraph_status`:

```
> codegraph_status()

{
  "version": "0.9.9",
  "project": "/path/to/your/repo",
  "symbols": 1247,
  "files": 89,
  "languages": { "typescript": 72, "python": 17 },
  "lastIndexed": "2026-06-03T10:15:42Z",
  "status": "ready"
}
```

---

## 4. Install the bundle integration layer

From the cloned `agent-toolkit-bundle` directory:

```bash
./install.sh --components codegraph
```

Or add it to an existing install:

```bash
./install.sh --components agents,skills,hooks,plugins,tools,commands,codegraph
```

This links the codegraph skill into `~/.agents/skills/` (and `~/.claude/skills/`
for Claude Code) so the `codegraph` skill is available in your sessions. The
repo is the source of truth — `git pull` propagates changes instantly.

---

## 5. Keep the index fresh

```bash
# After pulling changes or editing files
codegraph sync

# Force full re-index (if index seems stale)
codegraph index --force

# Check index health
codegraph status
```

The MCP server uses native file watchers to auto-sync when running — manual
`codegraph sync` is only needed when the server is not running.

---

## Uninstall

```bash
# Remove global CLI
npm uninstall -g @colbymchenry/codegraph

# Remove project index (per repo)
codegraph uninit
# or manually: rm -rf .codegraph/
```
