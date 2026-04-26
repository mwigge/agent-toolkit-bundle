# shellcheck shell=bash
# mode.sh — source this file from ~/.zshrc, ~/.bashrc, or ~/.kshrc.
#
# Compatible with bash 4+, zsh 5+, and ksh93+. Written in POSIX-compatible
# syntax where practical: single-bracket [ ... ] tests, printf instead of
# echo, typeset instead of local.
#
# Provides:
#   mode          # show current mode
#   mode company  # switch to company (block private paths)
#   mode private  # switch to private (block company paths)
#
# Also initialises ~/.claude/mode to "company" on first load,
# and defines mode_prompt() for an optional prompt marker.

mode() {
  if [ -z "${1:-}" ]; then
    cat "$HOME/.claude/mode" 2>/dev/null || printf 'company\n'
    return
  fi
  if [ "$1" != "company" ] && [ "$1" != "private" ]; then
    printf 'Usage: mode [company|private]\n' >&2
    return 1
  fi
  mkdir -p "$HOME/.claude"
  printf '%s\n' "$1" >"$HOME/.claude/mode"
  printf 'Mode: %s\n' "$1"
}

if [ ! -f "$HOME/.claude/mode" ]; then
  mkdir -p "$HOME/.claude"
  printf 'company\n' >"$HOME/.claude/mode"
fi

mode_prompt() {
  typeset m
  m=$(cat "$HOME/.claude/mode" 2>/dev/null || printf 'company')
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$m" = "company" ]; then
      printf '%%F{blue}[company]%%f'
    else
      printf '%%F{magenta}[private]%%f'
    fi
  else
    if [ "$m" = "company" ]; then
      printf '\001\033[34m\002[company]\001\033[0m\002'
    else
      printf '\001\033[35m\002[private]\001\033[0m\002'
    fi
  fi
}
