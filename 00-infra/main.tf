# ============================================================================
# Provisioning layer — the Azure resources the AI gateway needs.
#
# Creates the resource group, the APIM instance (AVM module), the observability
# plane (Log Analytics + Application Insights), the container registry (ACR) that
# stores the model image, the Azure AI Search knowledge store, and the optional
# Content Safety + Managed Redis used by the gateway policies.
#
# This root provisions resources only. The gateway configuration (APIs,
# backends, policies, loggers) lives in ../02-apim/; the model serving in
# ../01-models/.
# ============================================================================

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ----------------------------------------------------------------------------
# CAF-compliant, globally-unique names (AVM naming module). `name_unique`
# appends a stable random suffix so globally-scoped names (APIM, ACR, Search)
# don't collide.
# ----------------------------------------------------------------------------
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"

  suffix = [var.name_prefix]
}

# ----------------------------------------------------------------------------
# APIM instance — the AI gateway (Azure Verified Module).
# ----------------------------------------------------------------------------
module "apim" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.9.0"

  name                = module.naming.api_management.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  publisher_email = var.publisher_email
  publisher_name  = var.publisher_name
  sku_name        = var.sku_name

  # System-assigned identity so APIM can authenticate to Azure backends /
  # Key Vault / App Insights without secrets.
  managed_identities = {
    system_assigned = true
  }

  # Send APIM resource logs + metrics to the Log Analytics workspace so the
  # gateway is observable from the first deploy (GatewayLogs surface the
  # throttling / failover behaviour we build next).
  diagnostic_settings = {
    law = {
      name                  = "apim-to-law"
      workspace_resource_id = module.log_analytics.resource_id
    }
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Observability plane — Log Analytics + Application Insights (AVM).
# App Insights is the sink for the `llm-emit-token-metric` policy (token /
# latency telemetry) and for APIM diagnostics.
# ----------------------------------------------------------------------------
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = module.naming.log_analytics_workspace.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  log_analytics_workspace_retention_in_days = var.log_retention_days

  tags = var.tags
}

module "app_insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.4.0"

  name                = module.naming.application_insights.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  # Workspace-based Application Insights.
  workspace_id     = module.log_analytics.resource_id
  application_type = "web"

  tags = var.tags
}

# NOTE: the APIM Application Insights logger + `llm-emit-token-metric` policy
# are gateway configuration — see ../02-apim/. App Insights (provisioned above) is
# their sink.

# ----------------------------------------------------------------------------
# Container platform — ACR stores the Ollama model image. The image build/push
# and the container deployment (Azure Container Instances) are done by
# ../01-models/. A user-assigned identity with AcrPull lets the container pull
# the image without admin credentials.
# ----------------------------------------------------------------------------
resource "azurerm_container_registry" "acr" {
  name                = module.naming.container_registry.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false

  tags = var.tags
}

resource "azurerm_user_assigned_identity" "aca_pull" {
  name                = "id-aca-pull-${var.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  tags = var.tags
}

resource "azurerm_role_assignment" "aca_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca_pull.principal_id
}

# ----------------------------------------------------------------------------
# Knowledge store — Azure AI Search (the RAG vector DB). The app embeds the
# query and runs a vector search here. API-key auth is enabled so the app can
# use a key (keyless via managed identity is a later hardening step).
# ----------------------------------------------------------------------------
resource "azurerm_search_service" "search" {
  count = var.enable_ai_search ? 1 : 0

  name                = module.naming.search_service.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.search_sku

  local_authentication_enabled = true

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Content safety (AI-gateway "security & safety" pillar) — Azure AI Content
# Safety account. The `llm-content-safety` policy moderates prompts before they
# reach the LLM. APIM authenticates via its managed identity (role assignment
# below); the policy references it through an APIM backend wired in ../02-apim/.
# ----------------------------------------------------------------------------
module "content_safety" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  count = var.enable_content_safety ? 1 : 0

  name                  = "cs-${module.naming.cognitive_account.name_unique}"
  location              = var.location
  parent_id             = azurerm_resource_group.this.id
  kind                  = "ContentSafety"
  sku_name              = var.content_safety_sku
  custom_subdomain_name = "cs-${module.naming.cognitive_account.name_unique}"

  # APIM authenticates to Content Safety with its managed identity: the
  # llm-content-safety backend in ../02-apim carries a managedIdentity
  # credential, and the APIM MI holds the Cognitive Services User role assigned
  # below. So local (key) auth stays disabled.
  local_auth_enabled = false

  tags = var.tags
}

# Let APIM's system-assigned identity call the Content Safety data plane
# (managed-identity auth in the llm-content-safety policy — no keys).
resource "azurerm_role_assignment" "apim_content_safety" {
  count = var.enable_content_safety ? 1 : 0

  scope                = module.content_safety[0].resource_id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim.resource.identity[0].principal_id
}

# ----------------------------------------------------------------------------
# Semantic caching (AI-gateway "scalability & performance" pillar) — Azure
# Managed Redis (Redis Enterprise) used as APIM's external cache. The
# `llm-semantic-cache-lookup/-store` policies store completions keyed by prompt
# embeddings so near-duplicate prompts skip the LLM.
# ----------------------------------------------------------------------------
module "redis" {
  source  = "Azure/avm-res-cache-redisenterprise/azurerm"
  version = "0.2.0"

  count = var.enable_semantic_cache ? 1 : 0

  name      = module.naming.redis_cache.name_unique
  location  = var.location
  parent_id = azurerm_resource_group.this.id
  sku_name  = var.redis_sku

  tags = var.tags
}

# The AVM module creates the database with access-key auth disabled (Entra-only).
# APIM registers Redis as its external cache using a key-based connection string,
# so enable access keys on the database.
resource "azapi_update_resource" "redis_access_keys" {
  count = var.enable_semantic_cache ? 1 : 0

  type        = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id = module.redis[0].database_id

  body = {
    properties = {
      accessKeysAuthentication = "Enabled"
    }
  }
}

# NOTE: registering Redis as APIM's external cache and creating the
# content-safety APIM backend are gateway configuration — see ../02-apim/.

# ----------------------------------------------------------------------------
# Networking (optional) — VNet + APIM subnet for outbound VNet integration.
# Only created when enable_vnet = true — needed when APIM must reach a backend
# over a private network. Off by default.
# ----------------------------------------------------------------------------
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.19.0"

  count = var.enable_vnet ? 1 : 0

  name          = module.naming.virtual_network.name_unique
  location      = var.location
  parent_id     = azurerm_resource_group.this.id
  address_space = var.vnet_address_space

  subnets = {
    apim = {
      name             = "snet-apim"
      address_prefixes = [var.apim_subnet_prefix]
      # TODO: APIM StandardV2 outbound VNet integration requires this subnet to
      # be delegated to "Microsoft.Web/serverFarms". Add the delegation block
      # here and set the APIM module's virtual-network settings when enabling
      # VNet integration.
    }
  }

  tags = var.tags
}
