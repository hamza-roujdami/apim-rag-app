"""MAF agent factory + RAG prompt assembly.

The agent is a Microsoft Agent Framework `Agent` backed by an OpenAI-compatible
chat client pointed at the APIM gateway, so agent traffic flows through the
AI-gateway policies.

RAG strategy: deterministic retrieve-then-generate — we fetch context from the
knowledge base and inject it into the user turn. This does not depend on the
model's tool-calling reliability. (An agentic variant using MAF tools or a
`ContextProvider` is a straightforward extension.)
"""

from __future__ import annotations

from agent_framework import Agent
from agent_framework.openai import OpenAIChatClient

from .config import Settings
from .retrieval import Passage, format_context

SYSTEM_PROMPT = (
    "You are an enterprise knowledge assistant. Answer strictly using the "
    "provided context passages. Cite the passage number in square brackets for "
    "every claim, e.g. [1]. If the context does not contain the answer, say you "
    "do not have enough information. Be concise and precise."
)


def build_agent(settings: Settings) -> Agent:
    """Create the MAF agent bound to the configured chat backend."""
    client = OpenAIChatClient(
        model=settings.llm_model,
        api_key=settings.llm_api_key,
        base_url=settings.llm_base_url,
        default_headers=(
            {settings.apim_key_header: settings.llm_api_key} if settings.llm_api_key else None
        ),
    )
    return client.as_agent(name="rag-agent", instructions=SYSTEM_PROMPT)


def build_prompt(question: str, passages: list[Passage]) -> str:
    """Assemble the RAG-augmented user turn."""
    return f"Context:\n{format_context(passages)}\n\nQuestion: {question}"
