import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, mkdirSync, writeFileSync, readdirSync, readFileSync, existsSync } from "fs"
import { join } from "path"
import { createHash } from "crypto"

// observe.ts — universal audit trail (mirrors observe.sh)
// Writes structured NDJSON to .claude/logs/events.ndjson on every tool call.
// + OTel span emission via @opentelemetry/api when the SDK is available.
// Never throws — audit and tracing failures are silently ignored.

// transcript-backup — fires on session compacting (mirrors transcript-backup.sh)
// Saves compaction payload to .claude/backups/transcript-*.jsonl.
// Keeps the 10 most recent files.

// NOTE: No console.warn — OpenCode plugins share stderr with the TUI.
//       All output goes to .claude/logs/events.ndjson only.

// ── OTel tracing (best-effort — degrades silently if SDK not loaded) ────────

let otelTracer: any = null
let otelSessionSpan: any = null
let otelSessionStarted = false

try {
  const otelApi = require("@opentelemetry/api")
  const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node")
  const { OTLPTraceExporter } = require("@opentelemetry/exporter-trace-otlp-http")
  const { SimpleSpanProcessor } = require("@opentelemetry/sdk-trace-node")
  const { Resource } = require("@opentelemetry/resources")

  const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || "http://localhost:4318"
  const exporter = new OTLPTraceExporter({ url: `${endpoint}/v1/traces` })
  const provider = new NodeTracerProvider({
    resource: new Resource({ "service.name": "ai-agent-opencode" }),
  })
  provider.addSpanProcessor(new SimpleSpanProcessor(exporter))
  provider.register()
  otelTracer = otelApi.trace.getTracer("ai-agent-opencode", "1.0.0")
} catch {
  // OTel SDK not available — tracing disabled, audit trail continues
}

// ── OTel metrics (best-effort) ──────────────────────────────────────────────

let toolCallCounter: any = null
let costGauge: any = null

try {
  const { MeterProvider } = require("@opentelemetry/sdk-metrics")
  const { OTLPMetricExporter } = require("@opentelemetry/exporter-metrics-otlp-http")
  const { PeriodicExportingMetricReader } = require("@opentelemetry/sdk-metrics")
  const { Resource } = require("@opentelemetry/resources")

  const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || "http://localhost:4318"
  const metricExporter = new OTLPMetricExporter({ url: `${endpoint}/v1/metrics` })
  const meterProvider = new MeterProvider({
    resource: new Resource({ "service.name": "ai-agent-opencode" }),
    readers: [new PeriodicExportingMetricReader({ exporter: metricExporter, exportIntervalMillis: 30000 })],
  })
  const meter = meterProvider.getMeter("ai-agent-opencode")
  toolCallCounter = meter.createCounter("ai_session_tool_calls_total", { description: "Total tool calls per session" })
  costGauge = meter.createUpDownCounter("ai_session_cost_usd", { description: "Session cost in USD" })
} catch {
  // Metrics SDK not available — continue without metrics
}

const MAX_BACKUPS = 10

function logDir(cwd: string): string {
  const dir = join(cwd, ".claude", "logs")
  mkdirSync(dir, { recursive: true })
  return dir
}

function backupDir(cwd: string): string {
  const dir = join(cwd, ".claude", "backups")
  mkdirSync(dir, { recursive: true })
  return dir
}

function riskScore(tool: string, summary: string): number {
  if (tool === "bash") {
    if (/rm\s+-rf|drop\s+table|truncate|curl|wget|ssh\s|scp\s|rsync|git\s+push|git\s+reset|pip\s+install|npm\s+install/i.test(summary)) return 3
    if (/\.env|migration|alter\s+table|create\s+table|chmod|chown/i.test(summary)) return 2
    return 1
  }
  if (tool === "edit" || tool === "write") {
    if (/\.env|settings\.local|pdm\.lock|package-lock/i.test(summary)) return 2
    return 1
  }
  if (tool === "webfetch") return 1
  return 0
}

function summarise(tool: string, args: Record<string, string>): string {
  if (!args || typeof args !== "object") return ""
  try {
    switch (tool) {
      case "bash":    return (args.command ?? "").slice(0, 200)
      case "edit":
      case "write":   return args.filePath ?? args.file_path ?? ""
      case "read":
      case "glob":
      case "grep":    return args.filePath ?? args.file_path ?? args.pattern ?? ""
      case "webfetch": return args.url ?? ""
      default:        return JSON.stringify(args).slice(0, 200)
    }
  } catch { return "" }
}

function pruneBackups(dir: string): void {
  try {
    const files = readdirSync(dir)
      .filter((f) => f.startsWith("transcript-") && f.endsWith(".jsonl"))
      .map((f) => join(dir, f))
      .sort()
    if (files.length > MAX_BACKUPS) {
      for (const f of files.slice(0, files.length - MAX_BACKUPS)) {
        try { require("fs").unlinkSync(f) } catch { /* ignore */ }
      }
    }
  } catch { /* ignore */ }
}

function lastHash(eventsPath: string): string {
  try {
    if (!existsSync(eventsPath)) return "genesis"
    const content = readFileSync(eventsPath, "utf8").trimEnd()
    if (!content) return "genesis"
    const lastLine = content.split("\n").pop() ?? ""
    const parsed = JSON.parse(lastLine)
    return parsed._hash ?? "genesis"
  } catch {
    return "genesis"
  }
}

function writeChainedEntry(eventsPath: string, entryObj: Record<string, unknown>): void {
  const prevHash = lastHash(eventsPath)
  const body = { ...entryObj, _prev_hash: prevHash }
  const bodyStr = JSON.stringify(body)
  const hash = createHash("sha256").update(bodyStr).digest("hex")
  const final = { ...body, _hash: hash }
  appendFileSync(eventsPath, JSON.stringify(final) + "\n")
}

export const ObservePlugin: Plugin = async () => {
  return {
    // tool.execute.before: args live on output.args (mutable)
    "tool.execute.before": async (input, output) => {
      const tool = input.tool ?? ""
      const args = ((output?.args ?? input?.args ?? {}) as Record<string, string>) ?? {}
      const cwd = process.cwd()
      const summary = summarise(tool, args)
      const risk = riskScore(tool, summary)
      const entryObj = {
        ts: new Date().toISOString(),
        event: "PreToolUse",
        tool,
        input_summary: summary,
        outcome: "ok",
        risk,
      }
      try {
        writeChainedEntry(join(logDir(cwd), "events.ndjson"), entryObj)
        if (risk >= 3) {
          appendFileSync(join(cwd, ".claude", "audit.log"), `${new Date().toISOString()} HIGH-RISK tool=${tool} ${summary.slice(0, 150)}\n`)
        }
      } catch { /* ignore */ }

      // OTel: session span (once per process lifetime)
      if (otelTracer && !otelSessionStarted) {
        otelSessionStarted = true
        try {
          otelSessionSpan = otelTracer.startSpan("ai.session", {
            attributes: { "ai.session.id": process.pid.toString() },
          })
        } catch { /* ignore */ }
      }

      // OTel: tool-call span + metrics
      if (otelTracer) {
        try {
          const toolSpan = otelTracer.startSpan("ai.tool.call", {
            attributes: {
              "ai.tool.name": tool,
              "ai.tool.risk_level": risk,
            },
          })
          toolSpan.end()
        } catch { /* ignore */ }
      }
      if (toolCallCounter) {
        try {
          toolCallCounter.add(1, { tool, outcome: "ok", risk_level: String(risk) })
        } catch { /* ignore */ }
      }
    },

    // tool.execute.after: args live on input.args (read-only); result on output.output
    "tool.execute.after": async (input, _output) => {
      const tool = input.tool ?? ""
      const args = ((input?.args ?? {}) as Record<string, string>) ?? {}
      const cwd = process.cwd()
      const summary = summarise(tool, args)
      const risk = riskScore(tool, summary)
      const entryObj2 = {
        ts: new Date().toISOString(),
        event: "PostToolUse",
        tool,
        input_summary: summary,
        outcome: "ok",
        risk,
      }
      try {
        writeChainedEntry(join(logDir(cwd), "events.ndjson"), entryObj2)
      } catch { /* ignore */ }
    },

    "experimental.session.compacting": async (_input, _output) => {
      const cwd = process.cwd()
      const ts = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15)
      const outFile = join(backupDir(cwd), `transcript-${ts}.jsonl`)
      try {
        const payload = JSON.stringify(_input ?? {})
        writeFileSync(outFile, payload + "\n")
        pruneBackups(backupDir(cwd))
        appendFileSync(
          join(logDir(cwd), "events.ndjson"),
          JSON.stringify({ ts: new Date().toISOString(), event: "PreCompact", backup: outFile }) + "\n",
        )
      } catch { /* ignore */ }
    },
  }
}
