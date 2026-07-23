# Aliases over the upstream layers' remote-state outputs, so the resource
# definitions stay readable.
locals {
  infra  = data.terraform_remote_state.infra.outputs
  models = data.terraform_remote_state.models.outputs

  rg                             = local.infra.resource_group_name
  apim_name                      = local.infra.apim_name
  apim_id                        = local.infra.apim_id
  app_insights_id                = local.infra.app_insights_id
  app_insights_connection_string = local.infra.app_insights_connection_string

  # Content safety / semantic cache are on only if ../00-infra provisioned them.
  content_safety_on       = local.infra.content_safety_id != null
  content_safety_endpoint = local.infra.content_safety_endpoint

  semantic_cache_on = local.infra.redis_cache_id != null
  redis_database_id = local.infra.redis_database_id
  redis_hostname    = local.infra.redis_hostname
  redis_cache_id    = local.infra.redis_cache_id

  # Both models are served by the same ACI Ollama endpoint; the model is chosen
  # by the request body, so the gpt-oss and embeddings backends share the URL.
  # (Swap for a self-hosted GPU LLM endpoint in production.)
  backend_gptoss_url     = local.models.ollama_openai_base_url
  backend_embeddings_url = local.models.ollama_openai_base_url
  embeddings_on          = true
}
