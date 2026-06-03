# Install — OpenSpec

**Package**: `@fission-ai/openspec`
**Requires**: Node.js 20.19.0 or higher

---

## 1. Install the CLI

OpenSpec is distributed as an npm package. The same package works on macOS
and Linux.

### npm (recommended)

```bash
npm install -g @fission-ai/openspec@latest
```

### pnpm

```bash
pnpm add -g @fission-ai/openspec@latest
```

### yarn

```bash
yarn global add @fission-ai/openspec@latest
```

### bun

Bun can install OpenSpec globally, but OpenSpec runs on Node.js. You still
need Node.js 20.19.0 or higher on `PATH`.

```bash
bun add -g @fission-ai/openspec@latest
```

### nix (run without installing)

```bash
nix run github:Fission-AI/OpenSpec -- init
```

Or add to a development shell in `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
    openspec.url  = "github:Fission-AI/OpenSpec";
  };

  outputs = { nixpkgs, openspec, ... }: {
    devShells.x86_64-linux.default =
      nixpkgs.legacyPackages.x86_64-linux.mkShell {
        buildInputs = [ openspec.packages.x86_64-linux.default ];
      };
  };
}
```

### Linux: ensure Node.js 20.19.0+ is available

```bash
# nvm (macOS + Linux)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 20
nvm use 20
npm install -g @fission-ai/openspec@latest

# NodeSource (Debian/Ubuntu)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g @fission-ai/openspec@latest

# NodeSource (RHEL/Fedora/CentOS)
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
npm install -g @fission-ai/openspec@latest
```

### Verify installation

```bash
openspec --version
# 1.4.1
```

---

## 2. Initialize in a project

Run once per repository. Creates the `openspec/` directory structure.

```bash
cd /path/to/your/repo
openspec init
```

This creates:

```
openspec/
├── changes/     ← active work (one subdirectory per change)
└── specs/       ← archived specifications (promoted after implementation)
```

OpenSpec also writes agent instruction files into the project root based on
which tool you use:

```bash
openspec init --tools claude    # writes CLAUDE.md instructions
openspec init --tools opencode  # writes AGENTS.md instructions
openspec init --tools codex     # writes AGENTS.md instructions
openspec init                   # auto-detects or writes for all
```

---

## 3. Install the bundle integration layer

From the cloned `agent-toolkit-bundle` directory:

```bash
./install.sh --components openspec
```

Or add it to an existing install:

```bash
./install.sh --components agents,skills,hooks,plugins,tools,commands,openspec
```

This links the four OpenSpec skills into `~/.agents/skills/` (and
`~/.claude/skills/` for Claude Code) so the `/opsx:*` slash commands are
available in your sessions. The repo is the source of truth — `git pull`
propagates changes instantly.

---

## 4. Verify

Open a session in your AI coding tool and run:

```bash
openspec list
```

If no changes exist yet, you will see:

```
No active changes.
Run /opsx:propose to start one.
```

Start your first change:

```
/opsx:propose add-dark-mode
```

---

## 5. Keep OpenSpec updated

```bash
# Upgrade the package
npm install -g @fission-ai/openspec@latest

# Refresh agent instructions in each project
cd /path/to/your/repo
openspec update
```

Run `openspec update` inside each project after upgrading to regenerate agent
guidance files and ensure the latest slash commands are active.

---

## Uninstall

```bash
npm uninstall -g @fission-ai/openspec
```

The `openspec/` directory in each project is plain Markdown — no cleanup
required unless you want to remove it.
