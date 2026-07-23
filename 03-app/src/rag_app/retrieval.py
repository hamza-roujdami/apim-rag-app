"""Vector retrieval over Azure AI Search.

The query is embedded with MAF's OpenAI-compatible embedding client (routed
through the APIM gateway) and used for a vector search against the AI Search
index seeded by ``scripts/seed.py``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from agent_framework.openai import OpenAIEmbeddingClient
from azure.core.credentials import AzureKeyCredential
from azure.search.documents.aio import SearchClient
from azure.search.documents.models import VectorizedQuery

from .config import Settings

VECTOR_FIELD = "text_vector"


@dataclass(slots=True)
class Passage:
    text: str
    source: str | None
    score: float


def _to_vector(item: Any) -> list[float]:
    """Normalise a single MAF embedding result into a plain float vector."""
    for attr in ("vector", "embedding", "values"):
        value = getattr(item, attr, None)
        if value is not None:
            return list(value)
    return list(item)


class KnowledgeBase:
    """Embeds queries and runs vector search against Azure AI Search."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._embedder = OpenAIEmbeddingClient(
            model=settings.embed_model,
            api_key=settings.embed_api_key,
            base_url=settings.embed_base_url,
            default_headers=(
                {settings.apim_key_header: settings.embed_api_key} if settings.embed_api_key else None
            ),
        )
        self._client = SearchClient(
            endpoint=settings.search_endpoint,
            index_name=settings.search_index,
            credential=AzureKeyCredential(settings.search_api_key),
        )

    async def _embed(self, text: str) -> list[float]:
        result = await self._embedder.get_embeddings(values=[text])
        return _to_vector(result[0])

    async def search(self, query: str, top_k: int | None = None) -> list[Passage]:
        k = top_k or self._settings.top_k
        vector = await self._embed(query)
        results = await self._client.search(
            search_text=None,
            vector_queries=[
                VectorizedQuery(vector=vector, k_nearest_neighbors=k, fields=VECTOR_FIELD)
            ],
            select=["text", "source"],
            top=k,
        )
        passages: list[Passage] = []
        async for r in results:
            passages.append(
                Passage(
                    text=str(r.get("text", "")),
                    source=r.get("source"),
                    score=float(r.get("@search.score", 0.0)),
                )
            )
        return passages

    async def aclose(self) -> None:
        await self._client.close()


def format_context(passages: list[Passage]) -> str:
    """Render retrieved passages as numbered context for the prompt."""
    if not passages:
        return "(no relevant context found)"
    return "\n\n".join(
        f"[{i}] {p.text}" + (f"\n(source: {p.source})" if p.source else "")
        for i, p in enumerate(passages, start=1)
    )
