# Ollama image with the models baked in, so the Container App starts fast
# (no multi-minute model download on cold start). Built with `az acr build`.
#
# The chat model is a small REASONING stand-in for gpt-oss (same request shape:
# it streams a thinking phase). Swap CHAT_MODEL for the real gpt-oss endpoint in
# production — only the model name / backend URL changes.
FROM ollama/ollama:latest

ARG CHAT_MODEL=qwen3:1.7b
ARG EMBED_MODEL=qwen3-embedding:0.6b

# Bind to all interfaces so the Container App ingress can reach it.
ENV OLLAMA_HOST=0.0.0.0:11434

# Start the server, pull both models into the image; the resulting /root/.ollama
# is committed to this layer (models travel with the image).
RUN ollama serve & \
    sleep 8 && \
    ollama pull ${CHAT_MODEL} && \
    ollama pull ${EMBED_MODEL}

EXPOSE 11434
