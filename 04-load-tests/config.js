// Central configuration for the Phase 1 baseline load test.
// Everything is overridable via environment variables so the same script
// can target the raw backend today and the APIM front door later.
//
// Example:
//   BASE_URL=https://gpt-oss.internal MODEL=gpt-oss \
//   k6 run baseline-test.js

function envInt(name, fallback) {
  const v = __ENV[name];
  const n = v === undefined ? NaN : parseInt(v, 10);
  return Number.isFinite(n) ? n : fallback;
}

function envFloat(name, fallback) {
  const v = __ENV[name];
  const n = v === undefined ? NaN : parseFloat(v);
  return Number.isFinite(n) ? n : fallback;
}

export const config = {
  // --- Target endpoint (OpenAI-compatible chat completions) ---
  // URL is intentionally a config var. Point at the backend directly for the
  // raw baseline, then re-run against the APIM gateway URL for comparison.
  baseUrl: __ENV.BASE_URL || "http://localhost:8000",
  chatPath: __ENV.CHAT_PATH || "/v1/chat/completions",
  model: __ENV.MODEL || "gpt-oss",

  // Auth. For APIM this is typically the subscription key or a bearer token.
  apiKey: __ENV.API_KEY || "",
  apiKeyHeader: __ENV.API_KEY_HEADER || "Authorization", // e.g. "api-key" or "Ocp-Apim-Subscription-Key"
  apiKeyPrefix: __ENV.API_KEY_PREFIX === undefined ? "Bearer " : __ENV.API_KEY_PREFIX,

  // --- Generation parameters ---
  maxTokens: envInt("MAX_TOKENS", 512),
  temperature: envFloat("TEMPERATURE", 0.7),

  // --- Timeouts ---
  requestTimeoutMs: envInt("REQUEST_TIMEOUT_MS", 120000),

  // --- Load profile ---
  // Ramping-VUs staircase. Each VU behaves as one concurrent user issuing
  // back-to-back streamed completions. Tune the stairs to bracket the point
  // where TTFT / error-rate degrade — that inflection is the capacity ceiling.
  stages: parseStages(
    __ENV.STAGES ||
      "2m:10,2m:25,2m:50,2m:100,2m:150,2m:200,1m:0"
  ),

  // Optional pacing (seconds) between iterations per VU to model think-time.
  thinkTimeMin: envFloat("THINK_TIME_MIN", 0.5),
  thinkTimeMax: envFloat("THINK_TIME_MAX", 2.0),
};

// STAGES format: "duration:target,duration:target,..."  e.g. "2m:50,1m:0"
function parseStages(spec) {
  return spec
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((pair) => {
      const [duration, target] = pair.split(":");
      return { duration: duration.trim(), target: parseInt(target, 10) };
    });
}

export function chatUrl() {
  return `${config.baseUrl.replace(/\/$/, "")}${config.chatPath}`;
}

export function authHeaders() {
  const headers = { "Content-Type": "application/json" };
  if (config.apiKey) {
    headers[config.apiKeyHeader] = `${config.apiKeyPrefix}${config.apiKey}`;
  }
  return headers;
}
