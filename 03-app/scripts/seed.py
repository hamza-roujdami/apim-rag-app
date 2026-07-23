"""Seed the Azure AI Search index with a few sample passages.

Usage (after ``infra`` is applied and SEARCH_* are set in .env):
    cd 03-app
    source .venv/bin/activate
    python -m scripts.seed

Creates/updates the vector index and uploads the passages with their
embeddings. The vector dimension is detected from the first embedding.
"""

from __future__ import annotations

import asyncio
import uuid

from agent_framework.openai import OpenAIEmbeddingClient
from azure.core.credentials import AzureKeyCredential
from azure.search.documents.aio import SearchClient
from azure.search.documents.indexes.aio import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)

from rag_app.config import Settings, get_settings
from rag_app.retrieval import VECTOR_FIELD, _to_vector

PASSAGES: list[dict[str, str]] = [
    {
        "source": "slo-guide#latency",
        "text": (
            "The service level objective defines a p95 latency target of 800 ms "
            "for interactive queries measured at the gateway. When concurrent "
            "demand exceeds provisioned capacity, the recommended mitigation is "
            "to shed non-critical traffic at the edge rather than let queue depth "
            "on the inference tier grow unbounded."
        ),
    },
    {
        "source": "capacity-planning#headroom",
        "text": (
            "Capacity planning assumes a steady-state utilisation ceiling of 70 "
            "percent to retain headroom for bursts and for the failover of a "
            "single availability zone."
        ),
    },
    {
        "source": "ops-runbook#saturation",
        "text": (
            "Operators should track time-to-first-token as the leading indicator "
            "of saturation, because it rises before end-to-end latency and before "
            "error rates climb. Early backpressure via token-rate limiting and "
            "admission control preserves goodput far better than reactive scaling, "
            "which is subject to GPU cold-start delays."
        ),
    },
]


async def _embed(settings: Settings) -> list[list[float]]:
    embedder = OpenAIEmbeddingClient(
        model=settings.embed_model,
        api_key=settings.embed_api_key,
        base_url=settings.embed_base_url,
        default_headers=(
            {settings.apim_key_header: settings.embed_api_key} if settings.embed_api_key else None
        ),
    )
    embeddings = await embedder.get_embeddings(values=[p["text"] for p in PASSAGES])
    return [_to_vector(e) for e in embeddings]


async def _create_index(settings: Settings, credential: AzureKeyCredential, dim: int) -> None:
    index = SearchIndex(
        name=settings.search_index,
        fields=[
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SearchableField(name="text", type=SearchFieldDataType.String),
            SimpleField(name="source", type=SearchFieldDataType.String, filterable=True),
            SearchField(
                name=VECTOR_FIELD,
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=dim,
                vector_search_profile_name="hnsw-profile",
            ),
        ],
        vector_search=VectorSearch(
            algorithms=[HnswAlgorithmConfiguration(name="hnsw-algo")],
            profiles=[
                VectorSearchProfile(
                    name="hnsw-profile",
                    algorithm_configuration_name="hnsw-algo",
                )
            ],
        ),
    )
    index_client = SearchIndexClient(endpoint=settings.search_endpoint, credential=credential)
    await index_client.create_or_update_index(index)
    await index_client.close()


async def main() -> None:
    settings = get_settings()
    vectors = await _embed(settings)
    dim = len(vectors[0])
    print(f"embedding dim = {dim}")

    credential = AzureKeyCredential(settings.search_api_key)
    await _create_index(settings, credential, dim)

    documents = [
        {
            "id": str(uuid.uuid4()),
            "text": p["text"],
            "source": p["source"],
            VECTOR_FIELD: vector,
        }
        for p, vector in zip(PASSAGES, vectors, strict=True)
    ]
    search_client = SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=credential,
    )
    await search_client.upload_documents(documents=documents)
    await search_client.close()
    print(f"seeded {len(PASSAGES)} passages into AI Search index '{settings.search_index}'")


if __name__ == "__main__":
    asyncio.run(main())
