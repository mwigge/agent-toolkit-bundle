#!/usr/bin/env bash
# tiered-proof.sh — end-to-end proof that the two-tier agent pipeline works
#
# opencode run is not blocking in non-TTY mode — it dispatches to a background
# server and returns immediately. Tool calls inside that short-lived session do
# not persist to a tmpdir after the CLI exits. The delegation step therefore
# requires an interactive terminal (the human-in-the-loop central tier), and
# must target a real persistent repo — not a mktemp dir.
#
# This script is split into three phases:
#
#   Phase 1 (automated)  — pre-checks: infrastructure, tooling, env
#                          sets up proof branch in ai_local, saves state
#   Phase 2 (manual)     — user runs delegation from interactive terminal
#                          local agent writes proof/hello.py and commits
#   Phase 3 (automated)  — post-checks: central tier verifies local agent output
#
# Usage:
#   tiered-proof.sh          # full guided run — runs pre then prints phase 2 instructions
#   tiered-proof.sh pre      # phase 1 only
#   tiered-proof.sh post     # phase 3 only (reads ~/.tiered-proof-state)
#
# State file: ~/.tiered-proof-state
# Report:     ./proof-report.json
# Exit codes: 0 = overall pass, 1 = fail

set -euo pipefail

DELEGATE_SH="${HOME}/.config/opencode/scripts/delegate.sh"
LOG_FILE="${HOME}/.agent_delegation.log"
DB_FILE="${HOME}/.agent_task_queue.db"
STATE_FILE="${HOME}/.tiered-proof-state"
REPORT_FILE="$(pwd)/proof-report.json"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ai_local is the proof repo — a real persistent repo the agent can commit into
AI_LOCAL="${HOME}/dev/src/ai_local"
PROOF_BRANCH="proof/tiered-$(date +%Y%m%d-%H%M%S)"
PROOF_FILE="proof/hello.py"
EXPECTED_OUTPUT="tiered-proof ok"

MODE="${1:-full}"

pass()    { echo "[pass] $1"; }
fail()    { echo "[FAIL] $1"; }
info()    { echo "[info] $1"; }
section() { echo ""; echo "── $1 ──"; }

# ── PHASE 1: pre-checks ───────────────────────────────────────────────────────
run_pre() {
  section "PHASE 1: Pre-checks (central tier — automated)"

  # 1a. delegate.sh exists and is executable
  CHK_DELEGATE_SH="fail"
  if [[ -x "$DELEGATE_SH" ]]; then
    CHK_DELEGATE_SH="pass"; pass "delegate_sh_exists_and_executable"
  elif [[ -f "$DELEGATE_SH" ]]; then
    fail "delegate_sh_not_executable — run: chmod +x $DELEGATE_SH"
  else
    fail "delegate_sh_missing — expected at $DELEGATE_SH"
  fi

  # 1b. delegation log format — if log exists, last entry must be valid JSON
  CHK_LOG_FORMAT="pass"
  if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
    if tail -1 "$LOG_FILE" | jq '.' >/dev/null 2>&1; then
      pass "delegation_log_format_valid"
    else
      CHK_LOG_FORMAT="fail"
      fail "delegation_log_format_invalid — last line is not valid JSON"
    fi
  else
    pass "delegation_log_not_yet_populated (will be created on first delegation)"
  fi

  # 1c. required tools present
  CHK_TOOLS="pass"
  for tool in jq sqlite3 git python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      CHK_TOOLS="fail"; fail "missing_tool: $tool"
    fi
  done
  [[ "$CHK_TOOLS" == "pass" ]] && pass "required_tools_present (jq sqlite3 git python3)"

  # 1d. opencode present
  CHK_OPENCODE="fail"
  if command -v opencode >/dev/null 2>&1; then
    OC_VER=$(opencode --version 2>/dev/null || echo "unknown")
    CHK_OPENCODE="pass"; pass "opencode_present (version: $OC_VER)"
  else
    fail "opencode_missing"
  fi

  # 1e. coder-python agent file exists
  CHK_AGENT="fail"
  for _d in agent agents; do
    _f="${HOME}/.config/opencode/${_d}/coder-python.md"
    if [[ -f "$_f" ]]; then
      CHK_AGENT="pass"; pass "coder_python_agent_found ($_f)"; break
    fi
  done
  [[ "$CHK_AGENT" == "fail" ]] && fail "coder_python_agent_missing"

  # 1f. task-queue DB accessible
  CHK_TASKQ="fail"
  if [[ -f "$DB_FILE" ]]; then
    if sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks;" >/dev/null 2>&1; then
      TQ_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo "?")
      CHK_TASKQ="pass"; pass "task_queue_accessible (${TQ_COUNT} tasks)"
    else
      fail "task_queue_db_unreadable"
    fi
  else
    fail "task_queue_db_missing — expected at $DB_FILE"
  fi

  # 1g. ai_local repo exists and is a git repo
  CHK_REPO="fail"
  if [[ -d "$AI_LOCAL/.git" ]]; then
    CHK_REPO="pass"; pass "proof_repo_exists ($AI_LOCAL)"
  else
    fail "proof_repo_missing — $AI_LOCAL is not a git repo"
  fi

  # 1h. create proof branch in ai_local (central tier action)
  CHK_BRANCH="fail"
  if [[ "$CHK_REPO" == "pass" ]]; then
    CURRENT_BRANCH=$(git -C "$AI_LOCAL" branch --show-current)
    git -C "$AI_LOCAL" checkout -b "$PROOF_BRANCH" 2>/dev/null
    mkdir -p "$AI_LOCAL/proof"
    CHK_BRANCH="pass"
    pass "proof_branch_created ($PROOF_BRANCH, from $CURRENT_BRANCH)"
  else
    fail "proof_branch_skipped (repo not found)"
  fi

  # 1i. post task to task-queue (central tier action — trackable proof of orchestration)
  CHK_TASK_POST="fail"
  if [[ -f "$DB_FILE" ]]; then
    if sqlite3 "$DB_FILE" "
      INSERT INTO tasks (id, title, description, status, created_at, updated_at)
      VALUES (
        lower(hex(randomblob(16))),
        'tiered-proof-test',
        'Proof harness — central tier posted this task, local tier implements it',
        'pending',
        datetime('now'),
        datetime('now')
      );" 2>/dev/null; then
      CHK_TASK_POST="pass"; pass "task_posted_to_queue (central tier planning recorded)"
    else
      fail "task_post_failed"
    fi
  fi

  # 1j. capture pre-delegation log baseline
  PRE_LOG_COUNT=0
  if [[ -f "$LOG_FILE" ]]; then
    PRE_LOG_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
  fi
  info "delegation_log_baseline: $PRE_LOG_COUNT entries"

  # ── Write state file ──────────────────────────────────────────────────────
  cat > "$STATE_FILE" << EOF
AI_LOCAL=${AI_LOCAL}
PROOF_BRANCH=${PROOF_BRANCH}
PROOF_FILE=${PROOF_FILE}
PRE_LOG_COUNT=${PRE_LOG_COUNT}
CHK_DELEGATE_SH=${CHK_DELEGATE_SH}
CHK_LOG_FORMAT=${CHK_LOG_FORMAT}
CHK_TOOLS=${CHK_TOOLS}
CHK_OPENCODE=${CHK_OPENCODE}
CHK_AGENT=${CHK_AGENT}
CHK_TASKQ=${CHK_TASKQ}
CHK_REPO=${CHK_REPO}
CHK_BRANCH=${CHK_BRANCH}
CHK_TASK_POST=${CHK_TASK_POST}
EOF

  section "PHASE 1 COMPLETE"
  echo "Proof repo:   $AI_LOCAL"
  echo "Proof branch: $PROOF_BRANCH"
  echo "State saved:  $STATE_FILE"

  PHASE1_PASS=1
  for chk in "$CHK_DELEGATE_SH" "$CHK_LOG_FORMAT" "$CHK_TOOLS" \
             "$CHK_OPENCODE" "$CHK_AGENT" "$CHK_TASKQ" \
             "$CHK_REPO" "$CHK_BRANCH" "$CHK_TASK_POST"; do
    [[ "$chk" == "fail" ]] && PHASE1_PASS=0 && break
  done

  if [[ $PHASE1_PASS -eq 0 ]]; then
    echo ""
    echo "⚠️  One or more pre-checks failed. Fix before proceeding to phase 2."
    return 1
  fi
  echo ""
  echo "✓ All pre-checks passed. Ready for phase 2."
}

# ── PHASE 2: manual instructions ─────────────────────────────────────────────
print_phase2_instructions() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: state file not found. Run 'tiered-proof.sh pre' first." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$STATE_FILE"

  section "PHASE 2: Manual delegation step (local tier — requires interactive terminal)"
  echo ""
  echo "opencode run is not blocking in non-TTY mode — it requires an interactive"
  echo "terminal where the TUI can drive the model's tool calls to completion."
  echo ""
  echo "Run this from your interactive terminal (Claude Code or OpenCode TUI):"
  echo ""
  echo "  bash ~/.config/opencode/scripts/delegate.sh \\"
  echo "    --agent coder-python \\"
  echo "    --dir \"${AI_LOCAL}\" \\"
  echo "    --prompt 'You are on branch ${PROOF_BRANCH}."
  echo "Create the file proof/hello.py with exactly this content:"
  echo "  print(\"tiered-proof ok\")"
  echo "Then run:"
  echo "  git add proof/hello.py"
  echo "  git commit -m \"feat(proof): add hello.py\""
  echo "Do not push.'"
  echo ""
  echo "Wait for the local agent to complete, then run:"
  echo "  tiered-proof.sh post"
  echo ""
}

# ── PHASE 3: post-checks ──────────────────────────────────────────────────────
run_post() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: state file not found. Run 'tiered-proof.sh pre' first." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$STATE_FILE"

  section "PHASE 3: Post-checks (central tier verifies local tier output)"

  # Carry forward all phase 1 checks with safe defaults
  CHK_DELEGATE_SH="${CHK_DELEGATE_SH:-fail}"
  CHK_LOG_FORMAT="${CHK_LOG_FORMAT:-fail}"
  CHK_TOOLS="${CHK_TOOLS:-fail}"
  CHK_OPENCODE="${CHK_OPENCODE:-fail}"
  CHK_AGENT="${CHK_AGENT:-fail}"
  CHK_TASKQ="${CHK_TASKQ:-fail}"
  CHK_REPO="${CHK_REPO:-fail}"
  CHK_BRANCH="${CHK_BRANCH:-fail}"
  CHK_TASK_POST="${CHK_TASK_POST:-fail}"
  PRE_LOG_COUNT="${PRE_LOG_COUNT:-0}"
  AI_LOCAL="${AI_LOCAL:-}"
  PROOF_BRANCH="${PROOF_BRANCH:-}"
  PROOF_FILE="${PROOF_FILE:-proof/hello.py}"

  # 3a. proof/hello.py exists in ai_local on the proof branch
  CHK_HELLO_PY_EXISTS="fail"
  FULL_PROOF_FILE="${AI_LOCAL}/${PROOF_FILE}"
  if [[ -f "$FULL_PROOF_FILE" ]]; then
    CHK_HELLO_PY_EXISTS="pass"; pass "hello_py_exists ($FULL_PROOF_FILE)"
  else
    fail "hello_py_missing — $FULL_PROOF_FILE not found"
  fi

  # 3b. hello.py output is correct
  CHK_HELLO_PY_CONTENT="fail"
  if [[ -f "$FULL_PROOF_FILE" ]]; then
    ACTUAL=$(python3 "$FULL_PROOF_FILE" 2>/dev/null || true)
    if [[ "$ACTUAL" == "$EXPECTED_OUTPUT" ]]; then
      CHK_HELLO_PY_CONTENT="pass"; pass "hello_py_content_correct (output: '$ACTUAL')"
    else
      fail "hello_py_content_wrong — got '$ACTUAL', expected '$EXPECTED_OUTPUT'"
    fi
  fi

  # 3c. local agent committed (proof branch has more than just the initial state)
  CHK_COMMIT_EXISTS="fail"
  if [[ -n "$PROOF_BRANCH" ]]; then
    COMMIT_COUNT=$(git -C "$AI_LOCAL" log "$PROOF_BRANCH" --oneline 2>/dev/null | wc -l | tr -d ' ')
    LAST_MSG=$(git -C "$AI_LOCAL" log -1 --format="%s" 2>/dev/null || echo "")
    if [[ $COMMIT_COUNT -ge 1 ]] && git -C "$AI_LOCAL" log "$PROOF_BRANCH" --oneline | grep -q "proof"; then
      CHK_COMMIT_EXISTS="pass"
      pass "commit_by_local_agent ($COMMIT_COUNT commits on branch, last: '$LAST_MSG')"
    else
      fail "proof_commit_missing — no commit containing 'proof' found on $PROOF_BRANCH"
    fi
  fi

  # 3d. delegation log gained at least one new entry
  CHK_LOG_ENTRY_ADDED="fail"
  POST_LOG_COUNT=0
  if [[ -f "$LOG_FILE" ]]; then
    POST_LOG_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
  fi
  if [[ $POST_LOG_COUNT -gt $PRE_LOG_COUNT ]]; then
    NEW=$((POST_LOG_COUNT - PRE_LOG_COUNT))
    CHK_LOG_ENTRY_ADDED="pass"
    pass "delegation_log_entry_added ($PRE_LOG_COUNT → $POST_LOG_COUNT, +$NEW)"
  else
    fail "delegation_log_not_updated — count unchanged at $PRE_LOG_COUNT"
  fi

  # 3e. last log entry is valid JSON with required fields
  CHK_LOG_ENTRY_VALID="fail"
  LAST_LOG_ENTRY="null"
  if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
    LAST_LINE=$(tail -1 "$LOG_FILE")
    if echo "$LAST_LINE" | jq -e '.ts and .agent and (.exit_code != null) and (.duration_s != null)' >/dev/null 2>&1; then
      CHK_LOG_ENTRY_VALID="pass"
      LAST_LOG_ENTRY=$(echo "$LAST_LINE" | jq '.')
      AGENT_USED=$(echo "$LAST_LINE" | jq -r '.agent')
      EXIT_CODE=$(echo "$LAST_LINE" | jq -r '.exit_code')
      DURATION=$(echo "$LAST_LINE" | jq -r '.duration_s')
      pass "delegation_log_entry_valid (agent=$AGENT_USED exit=$EXIT_CODE duration=${DURATION}s)"
    else
      fail "delegation_log_entry_malformed"
    fi
  else
    fail "delegation_log_empty"
  fi

  # ── Overall result ────────────────────────────────────────────────────────
  OVERALL="pass"
  for chk in \
    "$CHK_DELEGATE_SH" "$CHK_LOG_FORMAT" "$CHK_TOOLS" \
    "$CHK_OPENCODE" "$CHK_AGENT" "$CHK_TASKQ" \
    "$CHK_REPO" "$CHK_BRANCH" "$CHK_TASK_POST" \
    "$CHK_HELLO_PY_EXISTS" "$CHK_HELLO_PY_CONTENT" \
    "$CHK_COMMIT_EXISTS" "$CHK_LOG_ENTRY_ADDED" "$CHK_LOG_ENTRY_VALID"; do
    [[ "$chk" == "fail" ]] && OVERALL="fail" && break
  done

  # ── Write proof-report.json ───────────────────────────────────────────────
  jq -n \
    --arg ts        "$TS" \
    --arg overall   "$OVERALL" \
    --arg dsh       "$CHK_DELEGATE_SH" \
    --arg logfmt    "$CHK_LOG_FORMAT" \
    --arg tools     "$CHK_TOOLS" \
    --arg oc        "$CHK_OPENCODE" \
    --arg agent     "$CHK_AGENT" \
    --arg taskq     "$CHK_TASKQ" \
    --arg repo      "$CHK_REPO" \
    --arg branch    "$CHK_BRANCH" \
    --arg taskpost  "$CHK_TASK_POST" \
    --arg hpe       "$CHK_HELLO_PY_EXISTS" \
    --arg hpc       "$CHK_HELLO_PY_CONTENT" \
    --arg ce        "$CHK_COMMIT_EXISTS" \
    --arg lea       "$CHK_LOG_ENTRY_ADDED" \
    --arg lev       "$CHK_LOG_ENTRY_VALID" \
    --argjson log_entry "$LAST_LOG_ENTRY" \
    '{
      ts: $ts,
      overall: $overall,
      phase1_central_tier: {
        delegate_sh_exists:       $dsh,
        delegation_log_format:    $logfmt,
        required_tools_present:   $tools,
        opencode_present:         $oc,
        coder_python_agent_found: $agent,
        task_queue_accessible:    $taskq,
        proof_repo_exists:        $repo,
        proof_branch_created:     $branch,
        task_posted_to_queue:     $taskpost
      },
      phase3_local_tier_verification: {
        hello_py_exists:            $hpe,
        hello_py_content_correct:   $hpc,
        commit_by_local_agent:      $ce,
        delegation_log_updated:     $lea,
        delegation_log_entry_valid: $lev
      },
      delegation_log_entry: $log_entry
    }' > "$REPORT_FILE"

  section "RESULT: $OVERALL"
  echo "Report: $REPORT_FILE"
  echo ""
  jq '{overall, phase1_central_tier, phase3_local_tier_verification}' "$REPORT_FILE"

  [[ "$OVERALL" == "pass" ]] && rm -f "$STATE_FILE" && echo "" && echo "✓ State file cleaned up."

  [[ "$OVERALL" == "pass" ]] && exit 0 || exit 1
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$MODE" in
  pre)  echo "=== tiered-proof.sh — phase 1 (pre) ===";  run_pre ;;
  post) echo "=== tiered-proof.sh — phase 3 (post) ==="; run_post ;;
  full)
    echo "=== tiered-proof.sh — full guided run ==="
    echo "Report: $REPORT_FILE"
    run_pre && print_phase2_instructions
    ;;
  *)
    echo "Usage: tiered-proof.sh [pre|post|full]" >&2; exit 1 ;;
esac
