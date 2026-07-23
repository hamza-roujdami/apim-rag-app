// Representative RAG-shaped prompts.
//
// A real request to this stack is not "hello world" — it is a system prompt +
// several retrieved context chunks + a user question. These fixtures mimic that
// shape at three sizes so the load test exercises realistic prompt-token counts
// (short ~600, medium ~1500, long ~3500 input tokens, roughly). Keeping the
// input distribution realistic matters: TTFT and prefill cost scale with input
// length, so trivial prompts would massively overstate capacity.

const SYSTEM_PROMPT =
  "You are an enterprise knowledge assistant. Answer strictly using the provided " +
  "context passages. Cite the passage number in square brackets for every claim. " +
  "If the context does not contain the answer, say you do not have enough " +
  "information. Be concise and precise.";

// A block of realistic-looking retrieved context. Repeated/sliced to reach
// target sizes without shipping a huge fixture file.
const CONTEXT_UNIT = `
[Passage {n}] The service level objective for the platform defines a p95 latency
target of 800 milliseconds for interactive queries measured at the gateway. When
concurrent demand exceeds provisioned capacity, the recommended mitigation is to
shed non-critical traffic at the edge rather than allow queue depth on the
inference tier to grow unbounded, because unbounded queueing degrades tail
latency for all tenants simultaneously. Historical incident reviews show that
backpressure applied early — via token-rate limiting and request admission
control — preserves goodput far better than reactive scaling, which is subject to
cold-start delays on GPU-backed pools. Capacity planning assumes a steady-state
utilisation ceiling of seventy percent to retain headroom for bursts and for the
failover of a single availability zone. Operators should track time-to-first-token
as the leading indicator of saturation, as it rises before end-to-end latency and
before error rates climb.`;

function buildContext(passageCount) {
  const parts = [];
  for (let i = 1; i <= passageCount; i++) {
    parts.push(CONTEXT_UNIT.replace("{n}", String(i)).trim());
  }
  return parts.join("\n\n");
}

const QUESTIONS = [
  "What is the recommended mitigation when demand exceeds capacity, and why is it preferred over reactive scaling?",
  "Which metric should operators watch as the earliest signal of saturation, and what is the reasoning?",
  "Summarise the capacity-planning utilisation assumptions and the rationale behind the headroom.",
  "How does early backpressure affect goodput compared to letting the queue grow?",
];

function makeMessage(passageCount, questionIndex) {
  const context = buildContext(passageCount);
  const question = QUESTIONS[questionIndex % QUESTIONS.length];
  return [
    { role: "system", content: SYSTEM_PROMPT },
    {
      role: "user",
      content: `Context:\n${context}\n\nQuestion: ${question}`,
    },
  ];
}

// Three weighted prompt sizes. Adjust the mix to match observed production
// traffic once real telemetry is available.
export const PROMPT_MIX = [
  { label: "short", passages: 2, weight: 0.3 },
  { label: "medium", passages: 5, weight: 0.5 },
  { label: "long", passages: 12, weight: 0.2 },
];

export function pickMessages() {
  const r = Math.random();
  let cum = 0;
  let chosen = PROMPT_MIX[PROMPT_MIX.length - 1];
  for (const p of PROMPT_MIX) {
    cum += p.weight;
    if (r <= cum) {
      chosen = p;
      break;
    }
  }
  const qIndex = Math.floor(Math.random() * QUESTIONS.length);
  return { label: chosen.label, messages: makeMessage(chosen.passages, qIndex) };
}
