"""Runtime configuration (pydantic-settings + .env)."""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All values are env-overridable; see .env.example.

    The model base URLs point at the APIM gateway so the agent's traffic flows
    through the AI gateway policies.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- LLM (OpenAI-compatible, via the APIM gateway) ---
    llm_base_url: str = ""
    llm_model: str = "gpt-oss"
    llm_api_key: str = ""

    # --- Embeddings (OpenAI-compatible, via the APIM gateway) ---
    embed_base_url: str = ""
    embed_model: str = "qwen3-embedding:0.6b"
    embed_api_key: str = ""

    # APIM expects its subscription key in this header (the gpt-oss / embeddings
    # APIs). The key value comes from LLM_API_KEY / EMBED_API_KEY.
    apim_key_header: str = "api-key"

    # --- Knowledge store (Azure AI Search) ---
    search_endpoint: str = ""
    search_index: str = "knowledge"
    search_api_key: str = ""
    top_k: int = 4


def get_settings() -> Settings:
    return Settings()
