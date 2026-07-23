# ============================================================================
# APIM AI-gateway configuration — the RAG app routes BOTH model calls through
# APIM: the gpt-oss chat API (generation) and the Embeddings API (retrieval).
#
# Provisioning (APIM, App Insights, Content Safety, Redis) is in ../00-infra; the
# model endpoint is from ../01-models. This root only CONFIGURES the gateway: backends,
# resiliency (circuit breaker + priority pool), APIs, policies, logger, cache.
# ============================================================================

# --- Primary gpt-oss backend (with circuit breaker) -------------------------
resource "azurerm_api_management_backend" "gptoss_primary" {
  name                = "gptoss-primary"
  resource_group_name = local.rg
  api_management_name = local.apim_name
  protocol            = "http"
  url                 = local.backend_gptoss_url
  title               = "gpt-oss (primary)"

  dynamic "credentials" {
    for_each = var.backend_key == "" ? [] : [1]
    content {
      header = {
        (var.backend_auth_header_name) = "{{backend-key}}"
      }
    }
  }

  circuit_breaker_rule {
    name                       = "gptoss-overload"
    trip_duration              = "PT1M"
    accept_retry_after_enabled = true

    failure_condition {
      interval_duration = "PT1M"
      count             = 5

      # 429 = backend shedding load; 5xx = backend unhealthy.
      status_code_range {
        min = 429
        max = 429
      }
      status_code_range {
        min = 500
        max = 599
      }
    }
  }
}

# --- Optional failover backend (priority-2 in the pool) ---------------------
resource "azurerm_api_management_backend" "gptoss_failover" {
  count = var.failover_backend_url == "" ? 0 : 1

  name                = "gptoss-failover"
  resource_group_name = local.rg
  api_management_name = local.apim_name
  protocol            = "http"
  url                 = var.failover_backend_url
  title               = "gpt-oss (failover / spillover)"

  dynamic "credentials" {
    for_each = var.backend_key == "" ? [] : [1]
    content {
      header = {
        (var.backend_auth_header_name) = "{{backend-key}}"
      }
    }
  }
}

# --- Embeddings backend (the app's retrieval hot path) ----------------------
resource "azurerm_api_management_backend" "embeddings" {
  count = local.embeddings_on ? 1 : 0

  name                = "embeddings"
  resource_group_name = local.rg
  api_management_name = local.apim_name
  protocol            = "http"
  url                 = local.backend_embeddings_url
  title               = "Qwen embeddings"

  dynamic "credentials" {
    for_each = var.backend_key == "" ? [] : [1]
    content {
      header = {
        (var.backend_auth_header_name) = "{{backend-key}}"
      }
    }
  }
}

# --- Priority-based load-balanced pool (azapi) ------------------------------
# APIM routes to a lower-priority group only when all higher-priority backends
# are unavailable because their circuit breaker tripped — automatic failover on
# overload. Only created when a failover backend is configured.
resource "azapi_resource" "gptoss_pool" {
  count = var.failover_backend_url == "" ? 0 : 1

  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "gptoss-pool"
  parent_id = local.apim_id

  body = {
    properties = {
      type = "Pool"
      pool = {
        services = [
          {
            id       = azurerm_api_management_backend.gptoss_primary.id
            priority = 1
            weight   = 1
          },
          {
            id       = azurerm_api_management_backend.gptoss_failover[0].id
            priority = 2
            weight   = 1
          },
        ]
      }
    }
  }
}

# --- Application Insights logger --------------------------------------------
resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights"
  api_management_name = local.apim_name
  resource_group_name = local.rg
  resource_id         = local.app_insights_id

  application_insights {
    connection_string = local.app_insights_connection_string
  }
}

# --- Optional shared backend secret -----------------------------------------
resource "azurerm_api_management_named_value" "backend_key" {
  count = var.backend_key == "" ? 0 : 1

  name                = "backend-key"
  resource_group_name = local.rg
  api_management_name = local.apim_name
  display_name        = "backend-key"
  secret              = true
  value               = var.backend_key
}

# --- Content Safety backend (for the llm-content-safety policy) --------------
# Defined via azapi so it can carry a managedIdentity credential: APIM uses its
# system identity (Cognitive Services User role) to authenticate to the keyless
# Content Safety account — no keys. (azurerm backends don't expose this yet.)
resource "azapi_resource" "content_safety" {
  count = local.content_safety_on ? 1 : 0

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "content-safety-backend"
  parent_id = local.apim_id

  # managedIdentity is a preview credential the provider schema doesn't model yet.
  schema_validation_enabled = false

  body = {
    properties = {
      description = "Azure AI Content Safety"
      url         = local.content_safety_endpoint
      protocol    = "http"
      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

# ============================================================================
# Governed APIs — following Microsoft's self-hosted-ollama lab (api-key header,
# catch-all operations).
# ============================================================================

# --- gpt-oss chat API (generation) ------------------------------------------
resource "azurerm_api_management_api" "gptoss" {
  name                  = "gpt-oss"
  resource_group_name   = local.rg
  api_management_name   = local.apim_name
  revision              = "1"
  display_name          = "gpt-oss chat"
  path                  = "gpt-oss"
  protocols             = ["https"]
  subscription_required = true
  service_url           = local.backend_gptoss_url

  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }
}

resource "azurerm_api_management_api_operation" "gptoss_post" {
  operation_id        = "post-all"
  api_name            = azurerm_api_management_api.gptoss.name
  api_management_name = local.apim_name
  resource_group_name = local.rg
  display_name        = "POST Catch-all"
  method              = "POST"
  url_template        = "/{*path}"
  description         = "Forwards any OpenAI-compatible POST (e.g. /chat/completions)."

  template_parameter {
    name     = "path"
    required = true
    type     = "string"
  }

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_operation" "gptoss_get" {
  operation_id        = "get-all"
  api_name            = azurerm_api_management_api.gptoss.name
  api_management_name = local.apim_name
  resource_group_name = local.rg
  display_name        = "GET Catch-all"
  method              = "GET"
  url_template        = "/{*path}"
  description         = "Forwards any OpenAI-compatible GET (e.g. /models)."

  template_parameter {
    name     = "path"
    required = true
    type     = "string"
  }

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "gptoss" {
  api_name            = azurerm_api_management_api.gptoss.name
  api_management_name = local.apim_name
  resource_group_name = local.rg

  xml_content = templatefile("${path.module}/policies/gpt-oss-api.xml.tftpl", {
    counter_key                 = "@(context.Subscription.Id)"
    tokens_per_minute           = var.gptoss_tokens_per_minute
    backend_id                  = var.failover_backend_url == "" ? "gptoss-primary" : "gptoss-pool"
    content_safety_enabled      = local.content_safety_on
    content_safety_backend_id   = "content-safety-backend"
    cache_enabled               = local.semantic_cache_on && local.embeddings_on
    cache_embeddings_backend_id = "embeddings"
  })

  depends_on = [
    azurerm_api_management_backend.gptoss_primary,
    azapi_resource.gptoss_pool,
    azapi_resource.content_safety,
    azurerm_api_management_backend.embeddings,
    azurerm_api_management_redis_cache.semantic,
    azurerm_api_management_named_value.backend_key,
  ]
}

# --- Embeddings API (retrieval hot path) ------------------------------------
resource "azurerm_api_management_api" "embeddings" {
  count = local.embeddings_on ? 1 : 0

  name                  = "embeddings"
  resource_group_name   = local.rg
  api_management_name   = local.apim_name
  revision              = "1"
  display_name          = "Embeddings"
  path                  = "embeddings"
  protocols             = ["https"]
  subscription_required = true
  service_url           = local.backend_embeddings_url

  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }
}

resource "azurerm_api_management_api_operation" "embeddings" {
  count = local.embeddings_on ? 1 : 0

  operation_id        = "post-all"
  api_name            = azurerm_api_management_api.embeddings[0].name
  api_management_name = local.apim_name
  resource_group_name = local.rg
  display_name        = "POST Catch-all"
  method              = "POST"
  url_template        = "/{*path}"
  description         = "Forwards any OpenAI-compatible POST (e.g. /embeddings)."

  template_parameter {
    name     = "path"
    required = true
    type     = "string"
  }

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "embeddings" {
  count = local.embeddings_on ? 1 : 0

  api_name            = azurerm_api_management_api.embeddings[0].name
  api_management_name = local.apim_name
  resource_group_name = local.rg

  xml_content = templatefile("${path.module}/policies/embeddings-api.xml.tftpl", {
    counter_key       = "@(context.Subscription.Id)"
    tokens_per_minute = var.embeddings_tokens_per_minute
  })

  depends_on = [
    azurerm_api_management_backend.embeddings,
    azurerm_api_management_named_value.backend_key,
  ]
}

# ============================================================================
# Semantic-cache external cache + LLM logging
# ============================================================================

# Managed Redis access key (data-plane listKeys) for the external cache string.
data "azapi_resource_action" "redis_keys" {
  count = local.semantic_cache_on ? 1 : 0

  type                   = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id            = local.redis_database_id
  action                 = "listKeys"
  response_export_values = ["primaryKey"]
}

# Register Azure Managed Redis as APIM's external cache. Managed Redis listens
# on 10000 with TLS.
resource "azurerm_api_management_redis_cache" "semantic" {
  count = local.semantic_cache_on ? 1 : 0

  name              = "semantic-cache"
  api_management_id = local.apim_id
  connection_string = "${local.redis_hostname}:10000,password=${data.azapi_resource_action.redis_keys[0].output.primaryKey},ssl=True,abortConnect=False"
  redis_cache_id    = local.redis_cache_id
  cache_location    = "default"
  description       = "Azure Managed Redis external cache for LLM semantic caching"
}

# LLM logging → Application Insights (token/prompt analytics + built-in dashboard).
resource "azurerm_api_management_api_diagnostic" "gptoss" {
  identifier               = "applicationinsights"
  resource_group_name      = local.rg
  api_management_name      = local.apim_name
  api_name                 = azurerm_api_management_api.gptoss.name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id

  sampling_percentage   = 100
  always_log_errors     = true
  verbosity             = "information"
  operation_name_format = "Name"
}

resource "azurerm_api_management_api_diagnostic" "embeddings" {
  count = local.embeddings_on ? 1 : 0

  identifier               = "applicationinsights"
  resource_group_name      = local.rg
  api_management_name      = local.apim_name
  api_name                 = azurerm_api_management_api.embeddings[0].name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id

  sampling_percentage   = 100
  always_log_errors     = true
  verbosity             = "information"
  operation_name_format = "Name"
}
