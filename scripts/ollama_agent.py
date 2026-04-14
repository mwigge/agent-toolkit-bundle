#!/usr/bin/env python3
"""
ollama_agent.py — Direct ollama agentic loop, bypasses opencode entirely.

Implements Read/Write/Edit/Bash tool loop against ollama /api/chat.
Accepts the same interface as delegate.sh.

Usage:
    python3 ollama_agent.py --agent coder-go --dir /repo --spec-file /tmp/task.md
    python3 ollama_agent.py --agent coder-go --dir /repo --prompt "Add Ping()..."

Exit codes:
    0  completed with output (files written or committed)
    1  bad arguments
    2  max turns exhausted with no output
    3  ollama unreachable / model error
    4  completed but no files changed (silent run)
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import requests

OLLAMA_URL   = "http://localhost:11434"
DEFAULT_MODEL = "devstral:latest"
# Script's own directory — allows bundle-local agent files to be found
# without requiring installation to ~/.config/opencode/
_SCRIPT_DIR = Path(__file__).resolve().parent

AGENT_DIRS   = [
    Path.home() / ".config/opencode/agents",
    Path.home() / ".config/opencode/agent",
    _SCRIPT_DIR.parent / "agents" / "opencode",   # bundle layout: scripts/../agents/opencode/
    _SCRIPT_DIR,                                   # agents co-located with script
]
MAX_TOOL_OUTPUT = 8000
MAX_FILE_READ   = 6000

# ── Tool schemas ──────────────────────────────────────────────────────────────

TOOLS = [
    {"type": "function", "function": {
        "name": "bash",
        "description": "Run a shell command in workdir. Use for go test, git, grep, ls, cat, go build, etc.",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string"},
            "timeout": {"type": "integer", "default": 60},
        }, "required": ["command"]},
    }},
    {"type": "function", "function": {
        "name": "read_file",
        "description": "Read a file. Path may be absolute or relative to workdir.",
        "parameters": {"type": "object", "properties": {
            "path":   {"type": "string"},
            "offset": {"type": "integer", "default": 1,   "description": "Start line (1-indexed)"},
            "limit":  {"type": "integer", "default": 200, "description": "Max lines"},
        }, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "write_file",
        "description": "Write (overwrite) a file with new content. Creates parent dirs.",
        "parameters": {"type": "object", "properties": {
            "path":    {"type": "string"},
            "content": {"type": "string"},
        }, "required": ["path", "content"]},
    }},
    {"type": "function", "function": {
        "name": "edit_file",
        "description": "Replace an exact string in a file with a new string (must appear exactly once).",
        "parameters": {"type": "object", "properties": {
            "path":       {"type": "string"},
            "old_string": {"type": "string"},
            "new_string": {"type": "string"},
        }, "required": ["path", "old_string", "new_string"]},
    }},
    {"type": "function", "function": {
        "name": "list_dir",
        "description": "List files and directories at a path.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "default": "."},
        }, "required": []},
    }},    {"type": "function", "function": {
        "name": "append_file",
        "description": "Append content to the END of an existing file without overwriting it.",
        "parameters": {"type": "object", "properties": {
            "path":    {"type": "string"},
            "content": {"type": "string", "description": "Text to append (newline prepended if file not empty)"},
        }, "required": ["path", "content"]},
    }},
]

# ── Tool implementations ──────────────────────────────────────────────────────

def _resolve(path: str, workdir: Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else workdir / p

def tool_bash(command: str, workdir: Path, timeout: int = 60) -> str:
    try:
        r = subprocess.run(command, shell=True, cwd=str(workdir),
                           capture_output=True, text=True, timeout=timeout)
        out = (r.stdout + r.stderr)[:MAX_TOOL_OUTPUT]
        return out.strip() or f"[exit {r.returncode}]"
    except subprocess.TimeoutExpired:
        return f"[ERROR: timed out after {timeout}s]"
    except Exception as e:
        return f"[ERROR: {e}]"

def tool_read_file(path: str, workdir: Path, offset: int = 1, limit: int = 200) -> str:
    try:
        lines = _resolve(path, workdir).read_text(errors="replace").splitlines()
        start = max(0, offset - 1)
        chunk = lines[start: start + limit]
        text = "\n".join(f"{start+i+1}: {l}" for i, l in enumerate(chunk))
        return text[:MAX_FILE_READ] or "[empty file]"
    except FileNotFoundError:
        return f"[ERROR: not found: {path}]"
    except Exception as e:
        return f"[ERROR: {e}]"

def tool_write_file(path: str, content: str, workdir: Path) -> str:
    try:
        p = _resolve(path, workdir)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return f"[wrote {len(content)} chars to {p}]"
    except Exception as e:
        return f"[ERROR: {e}]"

def tool_edit_file(path: str, old: str, new: str, workdir: Path) -> str:
    try:
        p = _resolve(path, workdir)
        text = p.read_text(errors="replace")
        n = text.count(old)
        if n == 0: return f"[ERROR: old_string not found in {path}]"
        if n > 1:  return f"[ERROR: old_string found {n} times — be more specific]"
        p.write_text(text.replace(old, new, 1))
        return f"[edited {p}]"
    except FileNotFoundError:
        return f"[ERROR: not found: {path}]"
    except Exception as e:
        return f"[ERROR: {e}]"

def tool_list_dir(path: str, workdir: Path) -> str:
    try:
        p = _resolve(path or ".", workdir)
        entries = sorted(p.iterdir(), key=lambda x: (x.is_file(), x.name))
        return "\n".join(e.name + ("/" if e.is_dir() else "") for e in entries) or "[empty]"
    except Exception as e:
        return f"[ERROR: {e}]"


def tool_append_file(path: str, content: str, workdir: Path) -> str:
    try:
        p = _resolve(path, workdir)
        if not p.exists():
            return f"[ERROR: file not found: {path}]"
        existing = p.read_text(errors="replace")
        sep = "\n" if existing and not existing.endswith("\n") else ""
        p.write_text(existing + sep + content)
        return f"[appended {len(content)} chars to {p}]"
    except Exception as e:
        return f"[ERROR: {e}]"

# ── Hard-limit hooks ─────────────────────────────────────────────────────────
# These run at the dispatch layer — the model cannot bypass them.
# Applied regardless of agent, language, or task type.

def _apply_hooks(name: str, args: dict, workdir: Path) -> tuple[str, dict]:
    """
    Intercept tool calls before execution.
    Returns (possibly-redirected name, possibly-redirected args).
    """
    # Hook: write_file on existing file → redirect to append_file
    # Rationale: write_file overwrites; for existing files the correct
    # operation is always append_file (add to end) or edit_file (replace
    # a specific block). This is a hard limit for ALL coding languages.
    if name == "write_file":
        file_path = args.get("path", "")
        if file_path:
            p = _resolve(file_path, workdir)
            if p.exists():
                print(
                    f"[hook] write_file blocked on existing file '{file_path}' "
                    f"— redirected to append_file",
                    file=__import__("sys").stderr,
                )
                return "append_file", args
    return name, args


def dispatch(name: str, args: dict, workdir: Path, timeout: int) -> str:
    name, args = _apply_hooks(name, args, workdir)
    match name:
        case "bash":       return tool_bash(args["command"], workdir, args.get("timeout", timeout))
        case "read_file":  return tool_read_file(args["path"], workdir, args.get("offset", 1), args.get("limit", 200))
        case "write_file": return tool_write_file(args["path"], args["content"], workdir)
        case "edit_file":  return tool_edit_file(args["path"], args["old_string"], args["new_string"], workdir)
        case "list_dir":   return tool_list_dir(args.get("path", "."), workdir)
        case "append_file": return tool_append_file(args["path"], args["content"], workdir)
        case _:            return f"[ERROR: unknown tool '{name}']"

# ── Agent loader ──────────────────────────────────────────────────────────────

def load_agent(name: str) -> tuple[str, str]:
    for d in AGENT_DIRS:
        p = d / f"{name}.md"
        if p.exists():
            text = p.read_text()
            model = DEFAULT_MODEL
            if text.startswith("---"):
                end = text.find("\n---", 3)
                if end != -1:
                    for line in text[3:end].splitlines():
                        if line.strip().startswith("model:"):
                            model = line.split(":", 1)[1].strip().removeprefix("ollama/")
                    text = text[end + 4:].strip()
            return model, text
    raise FileNotFoundError(f"Agent '{name}' not found in {AGENT_DIRS}")

# ── Git helpers ───────────────────────────────────────────────────────────────

def git_head(workdir: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=str(workdir),
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def git_commit_count(workdir: Path, pre: str) -> int:
    if not pre: return 0
    try:
        n = subprocess.check_output(
            ["git", "rev-list", "--count", f"{pre}..HEAD"],
            cwd=str(workdir), text=True).strip()
        return int(n)
    except Exception:
        return 0

# ── Ollama call ───────────────────────────────────────────────────────────────

def ollama_chat(model: str, messages: list, url: str) -> dict:
    resp = requests.post(
        f"{url.rstrip('/')}/api/chat",
        json={
            "model":    model,
            "messages": messages,
            "tools":    TOOLS,
            "stream":   False,
            "options":  {"num_ctx": 16384, "num_predict": 2048},
        },
        timeout=300,
    )
    resp.raise_for_status()
    return resp.json()

# ── Main loop ─────────────────────────────────────────────────────────────────

def run_agent(agent: str, workdir: Path, prompt: str, model_override: str | None,
              max_turns: int, tool_timeout: int, ollama_url: str, verbose: bool) -> int:

    model, system_prompt = load_agent(agent)
    if model_override:
        model = model_override

    # Look for subagent_AGENTS.md: first in ~/.config/opencode/, then next to script
    _subagent_candidates = [
        Path.home() / ".config/opencode/subagent_AGENTS.md",
        _SCRIPT_DIR / "subagent_AGENTS.md",
    ]
    for _sr in _subagent_candidates:
        if _sr.exists():
            system_prompt = _sr.read_text() + "\n\n---\n\n" + system_prompt
            break

    messages: list[dict] = [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": prompt},
    ]

    pre_hash     = git_head(workdir)
    files_written = 0
    turn          = 0

    _log = lambda msg: print(f"[ollama_agent] {msg}", file=sys.stderr)

    if verbose:
        _log(f"model={model} workdir={workdir} max_turns={max_turns}")

    for turn in range(1, max_turns + 1):
        _log(f"turn {turn}/{max_turns} — calling {model}...")

        try:
            resp = ollama_chat(model, messages, ollama_url)
        except requests.RequestException as e:
            _log(f"ERROR: ollama unreachable: {e}")
            return 3

        msg        = resp.get("message", {})
        content    = msg.get("content", "")
        tool_calls = msg.get("tool_calls") or []

        # Build the assistant message for history
        assistant_msg: dict = {"role": "assistant", "content": content}
        if tool_calls:
            assistant_msg["tool_calls"] = tool_calls
        messages.append(assistant_msg)

        if verbose and content:
            _log(f"  assistant: {content[:300]}")

        if not tool_calls:
            _log(f"no tool calls — finished after {turn} turns")
            break

        for tc in tool_calls:
            fn      = tc.get("function", {})
            tname   = fn.get("name", "")
            raw     = fn.get("arguments", {})
            call_id = tc.get("id", f"call_{turn}")

            if isinstance(raw, str):
                try:   raw = json.loads(raw)
                except json.JSONDecodeError: raw = {}

            if verbose:
                _log(f"  → {tname}({json.dumps(raw)[:200]})")

            result = dispatch(tname, raw, workdir, tool_timeout)

            if tname in ("write_file", "edit_file", "append_file") and not result.startswith("[ERROR"):
                files_written += 1

            if verbose:
                _log(f"  ← {result[:300]}")

            messages.append({"role": "tool", "content": result, "tool_call_id": call_id})

    else:
        _log(f"WARNING: max_turns ({max_turns}) exhausted without finishing")

    commits = git_commit_count(workdir, pre_hash)
    _log(f"done — turns={turn} files_written={files_written} commits={commits}")

    if commits == 0 and files_written == 0:
        return 4
    return 0

# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(description="Direct ollama agent loop")
    p.add_argument("--agent",      required=True)
    p.add_argument("--dir",        default=os.getcwd())
    p.add_argument("--prompt",     default="")
    p.add_argument("--spec-file",  default="", dest="spec_file")
    p.add_argument("--model",      default="")
    p.add_argument("--max-turns",  type=int, default=40, dest="max_turns")
    p.add_argument("--timeout",    type=int, default=60)
    p.add_argument("--ollama-url", default=OLLAMA_URL, dest="ollama_url")
    p.add_argument("--verbose",    action="store_true")
    args = p.parse_args()

    if not args.prompt and not args.spec_file:
        p.error("--prompt or --spec-file required")
    if args.prompt and args.spec_file:
        p.error("--prompt and --spec-file are mutually exclusive")

    workdir = Path(args.dir).resolve()
    if not workdir.is_dir():
        print(f"[ollama_agent] ERROR: '{workdir}' is not a directory", file=sys.stderr)
        sys.exit(1)

    prompt = Path(args.spec_file).read_text() if args.spec_file else args.prompt

    sys.exit(run_agent(
        agent=args.agent, workdir=workdir, prompt=prompt,
        model_override=args.model or None, max_turns=args.max_turns,
        tool_timeout=args.timeout, ollama_url=args.ollama_url, verbose=args.verbose,
    ))

if __name__ == "__main__":
    main()
