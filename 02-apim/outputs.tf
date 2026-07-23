output "gptoss_api_url" {
  description = "APIM URL for the gpt-oss chat API — set the app's LLM_BASE_URL / k6 BASE_URL here (no /v1)."
  value       = "${local.infra.apim_gateway_url}/gpt-oss"
}

output "embeddings_api_url" {
  description = "APIM URL for the Embeddings API — set the app's EMBED_BASE_URL here."
  value       = local.embeddings_on ? "${local.infra.apim_gateway_url}/embeddings" : null
}

output "subscription_key" {
  description = "APIM subscription key — send as the `api-key` header (app LLM_API_KEY / k6 API_KEY)."
  value       = azurerm_api_management_subscription.poc.primary_key
  sensitive   = true
}
