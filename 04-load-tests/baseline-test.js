// Phase 1 baseline load test for the gpt-oss chat-completions deployment.
//
// Goal: ramp concurrent streamed requests against an OpenAI-compatible
// /v1/chat/completions endpoint and capture the metrics that reveal the
// concurrent-user capacity ceiling:
//   - TTFT (time to first token)        -> leading saturation indicator
//   - inter-token latency               -> decode-tier pressure
//   - total latency                     -> end-to-end user experience
//   - output-token throughput           -> tokens/sec per request + aggregate
//   - error rate                        -> hard capacity ceiling
//
// Streaming (SSE) is required to measure TTFT and inter-token latency, so this
// script uses the xk6-sse extension. Build a k6 binary that includes it:
//
//   xk6 build --with github.com/phymbert/xk6-sse
//   ./k6 run baseline-test.js
//
// See README.md for the full run recipe and env vars.

import sse from "k6/x/sse";
import { check } from "k6";
import { sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";
import { config, chatUrl, authHeaders } from "./config.js";
import { pickMessages } from "./prompts.js";

// --- Custom metrics ---
const ttft = new Trend("llm_ttft_ms", true);
const interToken = new Trend("llm_inter_token_ms", true);
const totalLatency = new Trend("llm_total_latency_ms", true);
const perReqThroughput = new Trend("llm_tokens_per_sec"); // per-request decode rate
const outputTokens = new Trend("llm_output_tokens");
const tokensCounter = new Counter("llm_output_tokens_total"); // aggregate throughput
const errorRate = new Rate("llm_errors");

export const options = {
  scenarios: {
    baseline: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: config.stages,
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    // Informational guardrails — tune to the real SLO once known. These do not
    // abort the run; they annotate the summary so the capacity inflection is
    // easy to spot.
    llm_ttft_ms: ["p(95)<3000"],
    llm_errors: ["rate<0.02"],
  },
};

function thinkTime() {
  const { thinkTimeMin: lo, thinkTimeMax: hi } = config;
  if (hi <= 0) return;
  sleep(lo + Math.random() * Math.max(0, hi - lo));
}

export default function () {
  const { label, messages } = pickMessages();

  const payload = JSON.stringify({
    model: config.model,
    messages,
    stream: true,
    stream_options: { include_usage: true },
    max_tokens: config.maxTokens,
    temperature: config.temperature,
  });

  const params = {
    method: "POST",
    headers: authHeaders(),
    body: payload,
    tags: { prompt_size: label },
    timeout: `${config.requestTimeoutMs}ms`,
  };

  const start = Date.now();
  let firstTokenAt = 0;
  let lastEventAt = 0;
  let tokenCount = 0;
  let usageOutputTokens = 0;
  let sawError = false;

  const response = sse.open(chatUrl(), params, function (client) {
    client.on("event", function (event) {
      const now = Date.now();

      if (event.data === "[DONE]" || event.data === undefined) {
        return;
      }

      let parsed;
      try {
        parsed = JSON.parse(event.data);
      } catch (e) {
        return; // ignore keep-alives / non-JSON frames
      }

      // Capture server-reported usage when present (final frame).
      if (parsed.usage && parsed.usage.completion_tokens) {
        usageOutputTokens = parsed.usage.completion_tokens;
      }

      // Count a token when the model streams EITHER visible content OR a
      // reasoning delta. gpt-oss (the real target) and qwen3 are reasoning
      // models: they emit `delta.reasoning`/`delta.reasoning_content` with an
      // empty `delta.content` during the thinking phase. Counting only content
      // would leave TTFT unset (and mark every request an error) until the
      // model finishes thinking, so TTFT here = time-to-first-*any*-token, the
      // true leading indicator of decode saturation.
      const d =
        parsed.choices && parsed.choices[0] && parsed.choices[0].delta;
      const delta =
        d && (d.content || d.reasoning_content || d.reasoning);

      if (delta) {
        if (firstTokenAt === 0) {
          firstTokenAt = now;
          ttft.add(now - start, { prompt_size: label });
        } else {
          interToken.add(now - lastEventAt, { prompt_size: label });
        }
        lastEventAt = now;
        tokenCount++;
      }
    });

    client.on("error", function (e) {
      sawError = true;
      // eslint-disable-next-line no-console
      console.error(`SSE error (${label}): ${e && e.error ? e.error() : e}`);
    });
  });

  const end = Date.now();
  const ok =
    check(response, {
      "status is 200": (r) => r && r.status === 200,
    }) && !sawError && firstTokenAt > 0;

  errorRate.add(!ok, { prompt_size: label });

  if (ok) {
    const totalMs = end - start;
    const tokens = usageOutputTokens || tokenCount;
    totalLatency.add(totalMs, { prompt_size: label });
    outputTokens.add(tokens, { prompt_size: label });
    tokensCounter.add(tokens, { prompt_size: label });
    const decodeMs = Math.max(1, end - firstTokenAt);
    perReqThroughput.add((tokens / decodeMs) * 1000, { prompt_size: label });
  }

  thinkTime();
}

// Write machine-readable + human-readable results into results/ with a
// timestamped filename so successive ramps don't overwrite each other.
export function handleSummary(data) {
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const target = (config.baseUrl || "unknown").replace(/[^a-zA-Z0-9]+/g, "_");
  const base = `results/baseline_${target}_${ts}`;

  const out = {};
  out[`${base}.json`] = JSON.stringify(data, null, 2);
  out[`${base}.txt`] = renderText(data);
  // Also echo a compact summary to stdout.
  out["stdout"] = renderText(data);
  return out;
}

function renderText(data) {
  const m = data.metrics || {};
  const line = (label, metric, keys) => {
    const src = m[metric] && m[metric].values ? m[metric].values : {};
    const parts = keys.map((k) => `${k}=${fmt(src[k])}`);
    return `  ${label.padEnd(24)} ${parts.join("  ")}`;
  };
  const L = [];
  L.push("=".repeat(72));
  L.push("gpt-oss baseline load test — summary");
  L.push(`target: ${config.baseUrl}${config.chatPath}   model: ${config.model}`);
  L.push("=".repeat(72));
  L.push(line("TTFT (ms)", "llm_ttft_ms", ["avg", "p(90)", "p(95)", "max"]));
  L.push(line("inter-token (ms)", "llm_inter_token_ms", ["avg", "p(90)", "p(95)"]));
  L.push(line("total latency (ms)", "llm_total_latency_ms", ["avg", "p(90)", "p(95)", "max"]));
  L.push(line("tokens/sec (per req)", "llm_tokens_per_sec", ["avg", "p(90)", "max"]));
  L.push(line("output tokens", "llm_output_tokens", ["avg", "max"]));
  L.push(line("total output tokens", "llm_output_tokens_total", ["count"]));
  L.push(line("error rate", "llm_errors", ["rate"]));
  L.push(line("iterations", "iterations", ["count", "rate"]));
  L.push(line("VUs (max)", "vus_max", ["value"]));
  L.push("=".repeat(72));
  return L.join("\n") + "\n";
}

function fmt(v) {
  if (v === undefined || v === null) return "-";
  return typeof v === "number" ? (Math.round(v * 100) / 100).toString() : String(v);
}
