# ACI exposes the container on a public FQDN and port (no TLS termination).
# Ollama serves the OpenAI-compatible surface under /v1.
output "ollama_fqdn" {
  description = "Public FQDN of the Ollama container instance."
  value       = azurerm_container_group.ollama.fqdn
}

output "ollama_openai_base_url" {
  description = "OpenAI-compatible base URL — set as the APIM backend (../02-apim chat + embeddings)."
  value       = "http://${azurerm_container_group.ollama.fqdn}:11434/v1"
}
