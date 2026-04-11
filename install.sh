#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# install.sh — selective installer for agent-toolkit-bundle.
#
# Copies agents, skills, hooks, commands, and plugins into the Claude Code
# and/or OpenCode install roots. Does not mutate settings.json files -
# prints the settings snippets the user should merge instead. Re-runnable;
# existing files are kept unless --force is set.
#
# MemPalace is NOT installed by this script. See docs/install-mempalace.md
# for how to bring your own MCP-compatible memory backend.

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

VALID_COMPONENTS=(agents skills hooks plugins commands)

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  -y, --yes                    Non-interactive (use defaults, no prompts)
      --force                  Overwrite existing files
      --profile PROFILE        claude | opencode | both | auto  (default: auto)
      --components LIST        Comma-separated subset
                               Valid: agents,skills,hooks,plugins,commands
      --templates              Also copy CLAUDE.md.example / AGENTS.md.example
                               into the current directory
      --target-claude DIR      Override Claude install root (default ~/.claude)
      --target-opencode DIR    Override OpenCode install root (default ~/.config/opencode)
  -h, --help                   Show this message

Profiles:
  auto      Detect which of Claude Code / OpenCode is installed and install
            for whichever is present (both if both are present).
  claude    Install only Claude-facing components (agents/claude, commands/claude,
            skills, hooks) - skips plugins and opencode agents/commands.
  opencode  Install only OpenCode-facing components (agents/opencode,
            commands/opencode, plugins) - skips skills, hooks, claude agents.
  both      Install everything for both tools.

Components:
  If --components is omitted, every component applicable to the selected
  profile is installed. MemPalace integration is not shipped by this
  installer - see docs/install-mempalace.md for how to bring your own
  MCP-compatible memory backend.
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
      [[ $# -ge 2 ]] || die "--profile requires an argument"
      PROFILE="$2"
      shift 2
      ;;
    --components)
      [[ $# -ge 2 ]] || die "--components requires an argument"
      COMPONENTS_RAW="$2"
      shift 2
      ;;
    --templates)
      WITH_TEMPLATES=1
      shift
      ;;
    --target-claude)
      [[ $# -ge 2 ]] || die "--target-claude requires an argument"
      TARGET_CLAUDE="$2"
      shift 2
      ;;
    --target-opencode)
      [[ $# -ge 2 ]] || die "--target-opencode requires an argument"
      TARGET_OPENCODE="$2"
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

resolve_profile() {
  case "$PROFILE" in
    claude | opencode | both) return 0 ;;
    auto)
      local has_claude=0 has_opencode=0
      [[ -d "$TARGET_CLAUDE" ]] && has_claude=1
      [[ -d "$TARGET_OPENCODE" ]] && has_opencode=1
      if [[ $has_claude -eq 1 && $has_opencode -eq 1 ]]; then
        PROFILE=both
      elif [[ $has_claude -eq 1 ]]; then
        PROFILE=claude
      elif [[ $has_opencode -eq 1 ]]; then
        PROFILE=opencode
      else
        printf 'neither %s nor %s exists - create one or pass --profile explicitly\n' \
          "$TARGET_CLAUDE" "$TARGET_OPENCODE" >&2
        exit 1
      fi
      ;;
    *)
      die "invalid profile: $PROFILE (valid: claude, opencode, both, auto)"
      ;;
  esac
}

resolve_profile

# ---- component resolution --------------------------------------------------

# COMPONENTS_SELECTED is a space-separated list the rest of the script inspects
# via contains().
COMPONENTS_SELECTED=""

contains() {
  local needle="$1"
  local haystack=" $2 "
  [[ "$haystack" == *" $needle "* ]]
}

is_valid_component() {
  local candidate="$1"
  local v
  for v in "${VALID_COMPONENTS[@]}"; do
    if [[ "$candidate" == "$v" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ -n "$COMPONENTS_RAW" ]]; then
  IFS=',' read -r -a raw_tokens <<<"$COMPONENTS_RAW"
  for tok in "${raw_tokens[@]}"; do
    tok="${tok// /}"
    [[ -z "$tok" ]] && continue
    if ! is_valid_component "$tok"; then
      printf 'unknown component: %s\n' "$tok" >&2
      exit 1
    fi
    COMPONENTS_SELECTED="$COMPONENTS_SELECTED $tok"
  done
  COMPONENTS_SELECTED="${COMPONENTS_SELECTED# }"
else
  # Default = all core components
  COMPONENTS_SELECTED="agents skills hooks plugins commands"
fi

# ---- source / target table --------------------------------------------------
#
# For each (source, target) pair the installer considers copying, decide
# whether it applies based on the active profile and selected components.
# Source dirs are guarded behind `if [ -d ]` because the markdown sweep
# (agents/skills/commands/templates) runs as a separate task and may not
# exist yet during a dry-run.

declare -a COPY_PLAN=()

want_component() { contains "$1" "$COMPONENTS_SELECTED"; }
want_profile_claude() { [[ "$PROFILE" == "claude" || "$PROFILE" == "both" ]]; }
want_profile_opencode() { [[ "$PROFILE" == "opencode" || "$PROFILE" == "both" ]]; }

plan_add() {
  # plan_add <src_dir> <target_dir> <mode>
  local src="$1" tgt="$2" mode="$3"
  if [[ ! -d "$src" ]]; then
    return
  fi
  COPY_PLAN+=("$src|$tgt|$mode")
}

# --- Core components --------------------------------------------------------

if want_component agents; then
  if want_profile_claude; then
    plan_add "$HERE/agents/claude" "$TARGET_CLAUDE/agents" 0644
  fi
  if want_profile_opencode; then
    plan_add "$HERE/agents/opencode" "$TARGET_OPENCODE/agent" 0644
  fi
fi

if want_component commands; then
  if want_profile_claude; then
    plan_add "$HERE/commands/claude" "$TARGET_CLAUDE/commands" 0644
  fi
  if want_profile_opencode; then
    plan_add "$HERE/commands/opencode" "$TARGET_OPENCODE/command" 0644
  fi
fi

if want_component skills; then
  if want_profile_claude; then
    plan_add "$HERE/skills" "$TARGET_CLAUDE/skills" 0644
  fi
  # skills are not an OpenCode concept - skipped silently for opencode profile
fi

if want_component hooks; then
  if want_profile_claude; then
    plan_add "$HERE/hooks" "$TARGET_CLAUDE/hooks" 0755
  fi
fi

if want_component plugins; then
  if want_profile_opencode; then
    plan_add "$HERE/plugins" "$TARGET_OPENCODE/plugins" 0644
  fi
fi

# ---- collision check --------------------------------------------------------
#
# For every target dir, build a list of (basename, source_path) entries from
# the selected sources. If any two sources map to the same target basename,
# fail before writing anything. The check treats the target dir as the
# grouping key, so two components whose source files share a basename would
# collide, but unrelated files in different target dirs would not. This is a
# general-purpose safety net for future contributors adding new component
# categories.

check_collisions() {
  local entry src tgt mode
  local -a targets=()
  local -a basenames=()
  local -a sources=()

  [[ ${#COPY_PLAN[@]} -eq 0 ]] && return 0

  for entry in "${COPY_PLAN[@]}"; do
    IFS='|' read -r src tgt mode <<<"$entry"
    while IFS= read -r -d '' f; do
      local base
      base="$(basename "$f")"
      local i
      if [[ ${#targets[@]} -gt 0 ]]; then
        for i in "${!targets[@]}"; do
          if [[ "${targets[$i]}" == "$tgt" && "${basenames[$i]}" == "$base" ]]; then
            printf 'collision: %s from %s and %s\n' "$base" "${sources[$i]}" "$f" >&2
            exit 1
          fi
        done
      fi
      targets+=("$tgt")
      basenames+=("$base")
      sources+=("$f")
    done < <(find "$src" -maxdepth 1 -mindepth 1 -type f \
      -not -name 'node_modules' -not -name '.DS_Store' -print0 2>/dev/null || true)
  done
}

check_collisions

# ---- confirm ---------------------------------------------------------------

summarise() {
  printf '\n'
  printf 'agent-toolkit-bundle install plan\n'
  printf '  profile:    %s\n' "$PROFILE"
  printf '  components: %s\n' "$COMPONENTS_SELECTED"
  printf '  claude:     %s\n' "$TARGET_CLAUDE"
  printf '  opencode:   %s\n' "$TARGET_OPENCODE"
  printf '  force:      %s\n' "$([[ $FORCE -eq 1 ]] && echo yes || echo no)"
  if [[ ${#COPY_PLAN[@]} -eq 0 ]]; then
    printf '  (nothing to copy - source dirs not present yet)\n'
  else
    printf '  sources:\n'
    local entry src tgt mode
    for entry in "${COPY_PLAN[@]}"; do
      IFS='|' read -r src tgt mode <<<"$entry"
      printf '    %s -> %s\n' "${src#"$HERE"/}" "$tgt"
    done
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

# ---- copy ------------------------------------------------------------------

copy_file() {
  local src="$1" dst="$2" mode="$3"
  if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
    printf 'kept:      %s (re-run with --force to overwrite)\n' "$dst"
    return
  fi
  install -m "$mode" "$src" "$dst"
  printf 'installed: %s\n' "$dst"
}

copy_tree() {
  local src="$1" dst="$2" mode="$3"
  mkdir -p "$dst"
  # Copy regular files recursively while preserving the relative layout.
  # node_modules, .git, and .DS_Store are excluded as noise that sometimes
  # lingers in a developer checkout.
  while IFS= read -r -d '' f; do
    local rel="${f#"$src"/}"
    local target="$dst/$rel"
    mkdir -p "$(dirname "$target")"
    copy_file "$f" "$target" "$mode"
  done < <(find "$src" \
    -type d \( -name node_modules -o -name .git \) -prune -o \
    -type f -not -name '.DS_Store' -print0 2>/dev/null)
}

if [[ ${#COPY_PLAN[@]} -gt 0 ]]; then
  for entry in "${COPY_PLAN[@]}"; do
    IFS='|' read -r src tgt mode <<<"$entry"
    copy_tree "$src" "$tgt" "$mode"
  done
fi

# ---- templates (opt-in) ----------------------------------------------------

if [[ "$WITH_TEMPLATES" -eq 1 ]]; then
  for tmpl in CLAUDE.md.example AGENTS.md.example; do
    src="$HERE/templates/$tmpl"
    if [[ -f "$src" ]]; then
      dst="$(pwd)/$tmpl"
      copy_file "$src" "$dst" 0644
    else
      printf 'skipped:   templates/%s not present in the bundle\n' "$tmpl"
    fi
  done
fi

# ---- final instructions ----------------------------------------------------

cat <<EOF

Done.

Next steps:
  1. Merge the hook and plugin entries into your settings.json by hand -
     the installer deliberately never edits ~/.claude/settings.json or
     ~/.config/opencode/opencode.json. See docs/installation.md for the
     JSON snippets.
  2. (Optional) For persistent cross-session memory, see
     docs/install-mempalace.md - MemPalace integration is BYO and not
     shipped by this installer.
  3. Grep for placeholders:
       grep -r '<your-' ~/.claude ~/.config/opencode 2>/dev/null
     and replace them with real values for your project.
EOF
