#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# install.sh — symlink-based installer for agent-toolkit-bundle.
#
# The cloned repo is the golden copy. This installer creates symlinks from
# each tool's canonical install location (~/.claude, ~/.config/opencode,
# ~/.agents) back into the repo. No files are copied. A `git pull` in the
# repo instantly propagates to every installed component.
#
# Chain for skills (2-hop via the tool-neutral ~/.agents path):
#
#   $REPO/skills/<name>/                    (real git-tracked files)
#       ^
#       | symlink
#       |
#   ~/.agents/skills/<name>                 (tool-neutral canonical)
#       ^
#       | symlink
#       |
#   ~/.claude/skills/<name>                 (Claude reads here)
#
# OpenCode reads ~/.agents/skills/ natively via its 6th discovery path, so
# no ~/.config/opencode/skills/ symlink is needed.
#
# Agents, commands, hooks, plugins, and tools symlink directly from the
# tool-specific install path to the corresponding file in the repo —
# no .agents middleman, because those components have no cross-tool
# neutral convention.
#
# MemPalace is an optional sub-package under mempalace/. See its docs.
# MemPalace is NOT installed unless --components includes it.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults --------------------------------------------------------------

NON_INTERACTIVE=0
FORCE=0
PROFILE="auto"
COMPONENTS_RAW=""
WITH_TEMPLATES=0
TARGET_CLAUDE="$HOME/.claude"
TARGET_OPENCODE="$HOME/.config/opencode"
TARGET_AGENTS="$HOME/.agents"
# TODO: confirm Copilot CLI skills path and add TARGET_COPILOT — see docs/copilot.md

VALID_COMPONENTS=(agents skills hooks plugins tools scripts commands mempalace codegraph openspec)

usage() {
	cat <<'EOF'
Usage: install.sh [options]

Options:
  -y, --yes                    Non-interactive (use defaults, no prompts)
      --force                  Overwrite real files / directories at target
                               paths. Existing symlinks are always replaced.
      --profile PROFILE        claude | opencode | both | auto  (default: auto)
       --components LIST        Comma-separated subset (default: all for profile)
                                Valid: agents,skills,hooks,plugins,tools,
                                       scripts,commands,mempalace,codegraph,
                                       openspec
      --templates              Also copy CLAUDE.md.example / AGENTS.md.example /
                               GEMINI.md.example into the current directory and
                               create .codex/config.toml from the Codex starter
                               template (templates are the one exception to the
                               symlink rule — users edit their project copy)
      --target-claude DIR      Override Claude install root (default ~/.claude)
      --target-opencode DIR    Override OpenCode install root
                               (default ~/.config/opencode)
      --target-agents DIR      Override tool-neutral skills root
                               (default ~/.agents)
  -h, --help                   Show this message

Profiles:
  auto      Detect which of Claude Code / OpenCode is installed and install
            for whichever is present (both if both are present).
  claude    Install only Claude-facing components.
  opencode  Install only OpenCode-facing components.
  both      Install everything for both tools.

Components:
  If --components is omitted, every component applicable to the selected
  profile is installed EXCEPT mempalace. Mempalace is opt-in via
  --components mempalace (or a list that contains it).

Install model:
  This installer uses symlinks, not copies. The cloned repo IS the golden
  source of truth. Keep the repo in a persistent location — moving it
  after install breaks all symlinks (re-run this script from the new
  location to repair).
EOF
}

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

# ---- argument parsing ------------------------------------------------------

while [[ $# -gt 0 ]]; do
	case "$1" in
	-y | --yes | --non-interactive)
		NON_INTERACTIVE=1
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	--profile)
		PROFILE="$2"
		shift 2
		;;
	--components)
		COMPONENTS_RAW="$2"
		shift 2
		;;
	--templates)
		WITH_TEMPLATES=1
		shift
		;;
	--target-claude)
		TARGET_CLAUDE="$2"
		shift 2
		;;
	--target-opencode)
		TARGET_OPENCODE="$2"
		shift 2
		;;
	--target-agents)
		TARGET_AGENTS="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'unknown option: %s\n' "$1" >&2
		usage >&2
		exit 1
		;;
	esac
done

# ---- profile resolution ----------------------------------------------------

case "$PROFILE" in
auto)
	if [[ -d "$TARGET_CLAUDE" && -d "$TARGET_OPENCODE" ]]; then
		PROFILE="both"
	elif [[ -d "$TARGET_CLAUDE" ]]; then
		PROFILE="claude"
	elif [[ -d "$TARGET_OPENCODE" ]]; then
		PROFILE="opencode"
	else
		die "neither $TARGET_CLAUDE nor $TARGET_OPENCODE exists — create one or pass --profile explicitly"
	fi
	;;
claude | opencode | both) ;;
*)
	die "invalid profile: $PROFILE (expected: claude, opencode, both, auto)"
	;;
esac

# ---- component selection ---------------------------------------------------

contains() {
	local needle="$1" hay="$2"
	[[ " $hay " == *" $needle "* ]]
}

COMPONENTS_SELECTED=""
if [[ -n "$COMPONENTS_RAW" ]]; then
	IFS=',' read -ra tokens <<<"$COMPONENTS_RAW"
	for tok in "${tokens[@]}"; do
		local_valid=0
		for v in "${VALID_COMPONENTS[@]}"; do
			[[ "$tok" == "$v" ]] && local_valid=1 && break
		done
		if [[ "$local_valid" -ne 1 ]]; then
			printf 'unknown component: %s (valid: %s)\n' \
				"$tok" "$(
					IFS=,
					echo "${VALID_COMPONENTS[*]}"
				)" >&2
			exit 1
		fi
		COMPONENTS_SELECTED="$COMPONENTS_SELECTED $tok"
	done
	COMPONENTS_SELECTED="${COMPONENTS_SELECTED# }"
else
	# Default = all core components, NO mempalace (opt-in only)
	COMPONENTS_SELECTED="agents skills hooks plugins tools scripts commands"
fi

want_component() { contains "$1" "$COMPONENTS_SELECTED"; }
want_profile_claude() { [[ "$PROFILE" == "claude" || "$PROFILE" == "both" ]]; }
want_profile_opencode() { [[ "$PROFILE" == "opencode" || "$PROFILE" == "both" ]]; }

# ---- link plan -------------------------------------------------------------
#
# Each entry is "source|target|mode" where mode is either:
#   file      — src is a file, target is a file symlink
#   dir       — src is a dir, target is a dir symlink (the whole subtree)
#   tree      — src is a dir, create one symlink per direct child
#
# `tree` mode is used for skills/, agents/, commands/, hooks/, plugins/,
# tools/ — we want to drop individual symlinks into the target dir so that
# the user's own content in the same dir isn't disturbed.

declare -a LINK_PLAN=()

plan() {
	# plan <source> <target> <mode>
	local src="$1" tgt="$2" mode="$3"
	[[ -e "$src" ]] || return 0
	LINK_PLAN+=("$src|$tgt|$mode")
}

# --- .agents canonical skills path (for both profiles) ---------------------

if want_component skills; then
	plan "$HERE/skills" "$TARGET_AGENTS/skills" tree
fi

# --- Claude profile --------------------------------------------------------

if want_profile_claude; then
	if want_component skills; then
		# Claude's skills dir symlinks to ~/.agents/skills (2-hop chain)
		# Actually: we create per-skill symlinks that point directly at the
		# repo to avoid fragile 2-hop chains. ~/.agents/skills already points
		# at the repo, so both resolve to the same real files.
		plan "$HERE/skills" "$TARGET_CLAUDE/skills" tree
	fi
	if want_component agents; then
		plan "$HERE/agents/claude" "$TARGET_CLAUDE/agents" tree
	fi
	if want_component commands; then
		plan "$HERE/commands/claude" "$TARGET_CLAUDE/commands" tree
	fi
	if want_component hooks; then
		plan "$HERE/hooks" "$TARGET_CLAUDE/hooks" tree
	fi
fi

# --- OpenCode profile ------------------------------------------------------

if want_profile_opencode; then
	# Skills: OpenCode reads ~/.agents/skills/ natively (6th discovery path),
	# so no separate ~/.config/opencode/skills/ symlink is needed.
	if want_component agents; then
		plan "$HERE/agents/opencode" "$TARGET_OPENCODE/agent" tree
	fi
	if want_component commands; then
		plan "$HERE/commands/opencode" "$TARGET_OPENCODE/command" tree
	fi
	if want_component plugins; then
		plan "$HERE/plugins" "$TARGET_OPENCODE/plugin" tree
	fi
	if want_component tools; then
		plan "$HERE/tools" "$TARGET_OPENCODE/tools" tree
	fi
	if want_component scripts; then
		plan "$HERE/scripts" "$TARGET_OPENCODE/scripts" tree
	fi
fi

# --- MemPalace (opt-in) ----------------------------------------------------

if want_component mempalace; then
	# Central mempalace sub-package — single source of truth in $HERE/mempalace,
	# with tool-specific install paths symlinking into the relevant subdirs.
	plan "$HERE/mempalace" "$TARGET_AGENTS/mempalace" dir
	if want_profile_claude; then
		plan "$HERE/mempalace/skill" "$TARGET_CLAUDE/skills/mempalace" dir
		plan "$HERE/mempalace/hooks" "$TARGET_CLAUDE/hooks" tree
		plan "$HERE/mempalace/commands/claude" "$TARGET_CLAUDE/commands" tree
	fi
	if want_profile_opencode; then
		plan "$HERE/mempalace/plugins" "$TARGET_OPENCODE/plugin" tree
		plan "$HERE/mempalace/tools" "$TARGET_OPENCODE/tools" tree
		plan "$HERE/mempalace/commands/opencode" "$TARGET_OPENCODE/command" tree
	fi
fi

# --- CodeGraph (opt-in) ----------------------------------------------------
#
# CodeGraph is an npm-based code intelligence MCP server. This bundle ships
# docs and configuration reference under codegraph/ — the skill is already
# in skills/ (installed by the skills component). The codegraph/ directory
# is linked into $TARGET_AGENTS so it is reachable tool-neutrally.

if want_component codegraph; then
	plan "$HERE/codegraph" "$TARGET_AGENTS/codegraph" dir
fi

# --- OpenSpec (opt-in) -----------------------------------------------------
#
# OpenSpec is an npm-based spec-driven development CLI. This bundle ships
# docs and configuration reference under openspec/ — the four skills are
# already in skills/ (installed by the skills component). The openspec/
# directory is linked into $TARGET_AGENTS so it is reachable tool-neutrally.

if want_component openspec; then
	plan "$HERE/openspec" "$TARGET_AGENTS/openspec" dir
fi

# ---- planner helpers -------------------------------------------------------
#
# Expand the LINK_PLAN into concrete (src, target) pairs.

declare -a LINKS=()

expand_plan() {
	[[ ${#LINK_PLAN[@]} -eq 0 ]] && return 0
	local entry src tgt mode
	for entry in "${LINK_PLAN[@]}"; do
		IFS='|' read -r src tgt mode <<<"$entry"
		case "$mode" in
		dir | file)
			LINKS+=("$src|$tgt")
			;;
		tree)
			# One symlink per direct child of $src, dropped into $tgt.
			local child base
			for child in "$src"/*; do
				[[ -e "$child" ]] || continue
				base="$(basename "$child")"
				# Skip dotfiles and node_modules.
				case "$base" in
				.* | node_modules | package.json | package-lock.json | tsconfig.json)
					continue
					;;
				esac
				LINKS+=("$child|$tgt/$base")
			done
			;;
		esac
	done
}

expand_plan

# ---- collision check -------------------------------------------------------
#
# Fail early if any two source paths resolve to the same target. This is
# a safety net against future contributors adding components whose files
# would overwrite each other.

check_collisions() {
	[[ ${#LINKS[@]} -eq 0 ]] && return 0
	local entry src tgt prev
	local -a seen=()
	for entry in "${LINKS[@]}"; do
		IFS='|' read -r src tgt <<<"$entry"
		if [[ ${#seen[@]} -gt 0 ]]; then
			for prev in "${seen[@]}"; do
				if [[ "$prev" == "$tgt" ]]; then
					printf 'collision: two sources map to %s\n' "$tgt" >&2
					exit 1
				fi
			done
		fi
		seen+=("$tgt")
	done
}

check_collisions

# ---- summary + confirm -----------------------------------------------------

summarise() {
	printf '\n'
	printf 'agent-toolkit-bundle install plan\n'
	printf '  repo:       %s\n' "$HERE"
	printf '  profile:    %s\n' "$PROFILE"
	printf '  components: %s\n' "$COMPONENTS_SELECTED"
	printf '  claude:     %s\n' "$TARGET_CLAUDE"
	printf '  opencode:   %s\n' "$TARGET_OPENCODE"
	printf '  agents:     %s\n' "$TARGET_AGENTS"
	printf '  force:      %s\n' "$([[ $FORCE -eq 1 ]] && echo yes || echo no)"
	if [[ ${#LINKS[@]} -eq 0 ]]; then
		printf '  (no symlinks to create — source dirs not present in this checkout)\n'
	else
		printf '  symlinks to create: %d\n' "${#LINKS[@]}"
	fi
	printf '\n'
}

summarise

if [[ "$NON_INTERACTIVE" -ne 1 ]]; then
	printf 'Proceed? [y/N] '
	IFS= read -r answer || answer=""
	case "$answer" in
	y | Y | yes | YES) ;;
	*)
		printf 'aborted\n'
		exit 0
		;;
	esac
fi

# ---- link creator ----------------------------------------------------------

create_link() {
	local src="$1" tgt="$2"

	mkdir -p "$(dirname "$tgt")"

	if [[ -L "$tgt" ]]; then
		# Existing symlink — always replace.
		ln -sfn "$src" "$tgt"
		printf 'relinked:  %s -> %s\n' "$tgt" "$src"
		return
	fi

	if [[ -d "$tgt" && ! -L "$tgt" ]]; then
		if [[ "$FORCE" -eq 1 ]]; then
			printf 'warning:   replacing real directory %s\n' "$tgt" >&2
			rm -rf "$tgt"
			ln -sfn "$src" "$tgt"
			printf 'linked:    %s -> %s\n' "$tgt" "$src"
		else
			printf 'kept:      %s (real directory — re-run with --force to replace)\n' "$tgt"
		fi
		return
	fi

	if [[ -f "$tgt" && ! -L "$tgt" ]]; then
		if [[ "$FORCE" -eq 1 ]]; then
			printf 'warning:   replacing real file %s\n' "$tgt" >&2
			rm -f "$tgt"
			ln -sfn "$src" "$tgt"
			printf 'linked:    %s -> %s\n' "$tgt" "$src"
		else
			printf 'kept:      %s (real file — re-run with --force to replace)\n' "$tgt"
		fi
		return
	fi

	# Target doesn't exist — clean install.
	ln -sfn "$src" "$tgt"
	printf 'linked:    %s -> %s\n' "$tgt" "$src"
}

if [[ ${#LINKS[@]} -gt 0 ]]; then
	for entry in "${LINKS[@]}"; do
		IFS='|' read -r src tgt <<<"$entry"
		create_link "$src" "$tgt"
	done
fi

# ---- templates (opt-in, actually copied, not symlinked) --------------------

if [[ "$WITH_TEMPLATES" -eq 1 ]]; then
	for tmpl in CLAUDE.md.example AGENTS.md.example GEMINI.md.example; do
		src="$HERE/templates/$tmpl"
		if [[ -f "$src" ]]; then
			dst="$(pwd)/$tmpl"
			if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
				printf 'kept:      %s (re-run with --force to overwrite)\n' "$dst"
			else
				install -m 0644 "$src" "$dst"
				printf 'copied:    %s\n' "$dst"
			fi
		else
			printf 'skipped:   templates/%s not present in the bundle\n' "$tmpl"
		fi
	done

	src="$HERE/templates/codex.config.toml.example"
	if [[ -f "$src" ]]; then
		mkdir -p "$(pwd)/.codex"
		dst="$(pwd)/.codex/config.toml"
		if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
			printf 'kept:      %s (re-run with --force to overwrite)\n' "$dst"
		else
			install -m 0644 "$src" "$dst"
			printf 'copied:    %s\n' "$dst"
		fi
	else
		printf 'skipped:   templates/codex.config.toml.example not present in the bundle\n'
	fi
fi

# ---- final instructions ----------------------------------------------------

cat <<EOF

Done.

Next steps:
  1. Merge the hook and plugin entries into your settings.json by hand -
     the installer deliberately never edits ~/.claude/settings.json or
     ~/.config/opencode/opencode.json. See docs/installation.md for the
     JSON snippets.
  2. Keep the repo at its current location ($HERE) - symlinks point here.
     If you move the repo later, re-run this installer from the new path.
  3. (Optional) For persistent cross-session memory, re-run with
       --components mempalace and then read docs/install-mempalace.md for
       the MCP server (BYO) setup and environment variables.
  4. (Optional) For code intelligence, re-run with --components codegraph
       and then read codegraph/docs/install.md to install the npm package
       and wire the MCP server into your agent config.
  5. (Optional) For spec-driven development, re-run with
       --components openspec and then read openspec/docs/install.md to
       install the npm package and initialise each project.
  6. Grep for placeholders in your shell or AGENTS.md / CLAUDE.md:
       grep -r '<your-' ~/.claude ~/.config/opencode 2>/dev/null
     and replace them with real values for your project.
EOF
