output "resource_group_name" {
  description = "Resource group containing the APIM instance."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region of the resource group (consumed by ../01-models/)."
  value       = azurerm_resource_group.this.location
}

output "apim_name" {
  description = "Name of the APIM instance."
  value       = module.apim.name
}

output "apim_id" {
  description = "Resource ID of the APIM instance (consumed by ../02-apim/)."
  value       = module.apim.resource_id
}

output "apim_gateway_url" {
  description = "APIM gateway base URL."
  value       = module.apim.apim_gateway_url
}

# --- Container platform (consumed by ../01-models/) ---
output "acr_login_server" {
  description = "ACR login server (e.g. myacr.azurecr.io)."
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "ACR name (for az acr build)."
  value       = azurerm_container_registry.acr.name
}

output "acr_id" {
  description = "ACR resource ID."
  value       = azurerm_container_registry.acr.id
}

output "aca_pull_identity_id" {
  description = "User-assigned identity (AcrPull) for the model container."
  value       = azurerm_user_assigned_identity.aca_pull.id
}

output "aca_pull_identity_client_id" {
  description = "Client ID of the AcrPull user-assigned identity."
  value       = azurerm_user_assigned_identity.aca_pull.client_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = module.log_analytics.resource_id
}

output "app_insights_id" {
  description = "Resource ID of the Application Insights component."
  value       = module.app_insights.resource_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (sink for token metrics)."
  value       = module.app_insights.connection_string
  sensitive   = true
}

output "vnet_id" {
  description = "Resource ID of the VNet (null when enable_vnet = false)."
  value       = var.enable_vnet ? module.vnet[0].resource_id : null
}

output "content_safety_id" {
  description = "Resource ID of the Azure AI Content Safety account (null when disabled)."
  value       = var.enable_content_safety ? module.content_safety[0].resource_id : null
}

output "content_safety_endpoint" {
  description = "Endpoint of the Azure AI Content Safety account (consumed by ../02-apim/)."
  value       = var.enable_content_safety ? module.content_safety[0].endpoint : null
}

output "redis_cache_id" {
  description = "Resource ID of the Azure Managed Redis semantic cache (null when disabled)."
  value       = var.enable_semantic_cache ? module.redis[0].resource_id : null
}

output "redis_database_id" {
  description = "Managed Redis database ID (for the APIM external-cache listKeys, consumed by ../02-apim/)."
  value       = var.enable_semantic_cache ? module.redis[0].database_id : null
}

output "redis_hostname" {
  description = "Managed Redis hostname (consumed by ../02-apim/)."
  value       = var.enable_semantic_cache ? module.redis[0].hostname : null
}

# --- Knowledge store (consumed by 03-app/.env) ---
output "search_endpoint" {
  description = "Azure AI Search endpoint (https://<name>.search.windows.net)."
  value       = var.enable_ai_search ? "https://${azurerm_search_service.search[0].name}.search.windows.net" : null
}

output "search_name" {
  description = "Azure AI Search service name."
  value       = var.enable_ai_search ? azurerm_search_service.search[0].name : null
}

output "search_api_key" {
  description = "Azure AI Search admin key (for 03-app; keyless MI is a later hardening step)."
  value       = var.enable_ai_search ? azurerm_search_service.search[0].primary_key : null
  sensitive   = true
}
