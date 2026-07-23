"""FastAPI surface for the RAG agent.

Endpoints:
- GET  /health          liveness
- POST /chat            non-streamed answer + sources
- POST /chat/stream     SSE stream of answer tokens (mirrors the load-test path)
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from .agent import build_agent, build_prompt
from .config import get_settings
from .retrieval import KnowledgeBase


class ChatRequest(BaseModel):
    question: str = Field(min_length=1)
    top_k: int | None = Field(default=None, ge=1, le=50)


class Source(BaseModel):
    text: str
    source: str | None
    score: float


class ChatResponse(BaseModel):
    answer: str
    sources: list[Source]


@dataclass(slots=True)
class AppState:
    settings: object
    kb: KnowledgeBase
    agent: object


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    kb = KnowledgeBase(settings)
    agent = build_agent(settings)
    app.state.ctx = AppState(settings=settings, kb=kb, agent=agent)
    try:
        yield
    finally:
        await kb.aclose()


app = FastAPI(title="RAG Agent (MAF)", version="0.1.0", lifespan=lifespan)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    ctx: AppState = app.state.ctx
    passages = await ctx.kb.search(req.question, top_k=req.top_k)
    prompt = build_prompt(req.question, passages)
    result = await ctx.agent.run(prompt)
    return ChatResponse(
        answer=result.text,
        sources=[Source(text=p.text, source=p.source, score=p.score) for p in passages],
    )


@app.post("/chat/stream")
async def chat_stream(req: ChatRequest) -> StreamingResponse:
    ctx: AppState = app.state.ctx
    passages = await ctx.kb.search(req.question, top_k=req.top_k)
    prompt = build_prompt(req.question, passages)

    async def event_stream() -> AsyncIterator[str]:
        sources = [
            {"text": p.text, "source": p.source, "score": p.score} for p in passages
        ]
        yield f"event: sources\ndata: {json.dumps(sources)}\n\n"
        async for update in ctx.agent.run(prompt, stream=True):
            if update.text:
                yield f"data: {json.dumps({'delta': update.text})}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
