# Gateway policy tuning. Provisioning (APIM, Content Safety, Redis) lives in
# ../00-infra; the model endpoint comes from ../01-models. These vars only tune the
# policies attached here.

variable "gptoss_tokens_per_minute" {
  description = "Token-per-minute rate limit for the gpt-oss chat API (set just below the Phase-1 capacity ceiling)."
  type        = number
  default     = 100000
}

variable "embeddings_tokens_per_minute" {
  description = "Token-per-minute rate limit for the Embeddings API (single-GPU hot path — saturates before gpt-oss)."
  type        = number
  default     = 200000
}

variable "failover_backend_url" {
  description = "Optional secondary/failover LLM endpoint for the priority pool. Empty = single-backend routing (no pool)."
  type        = string
  default     = ""
}

variable "backend_key" {
  description = "Optional shared secret APIM sends to the backends (model API key). ACI Ollama needs none. Empty = no auth header."
  type        = string
  default     = ""
  sensitive   = true
}

variable "backend_auth_header_name" {
  description = "Header name APIM uses to send backend_key to the backends."
  type        = string
  default     = "Authorization"
}
