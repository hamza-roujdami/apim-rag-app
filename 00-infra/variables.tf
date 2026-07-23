variable "name_prefix" {
  description = "Suffix fed to the AVM naming module to derive CAF-compliant, unique resource names."
  type        = string
  default     = "apimragpoc"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into (created by this config)."
  type        = string
  default     = "rg-apim-rag-poc"
}

variable "publisher_email" {
  description = "Publisher email for the APIM instance."
  type        = string
}

variable "publisher_name" {
  description = "Publisher organisation name for the APIM instance."
  type        = string
  default     = "APIM RAG PoC"
}

# StandardV2 is the default tier:
#  - supports all AI-gateway policies (token limit, token metrics, load-balanced
#    backend pools, circuit breaker)
#  - supports outbound VNet integration to reach a private LLM backend
#  - has an SLA and can scale units for the capacity load test
# Use Premium only if multi-region or classic VNet injection is required.
variable "sku_name" {
  description = "APIM SKU in '<tier>_<capacity>' form, e.g. StandardV2_1."
  type        = string
  default     = "StandardV2_1"

  validation {
    condition     = can(regex("^(Developer|BasicV2|StandardV2|Premium|PremiumV2)_[0-9]+$", var.sku_name))
    error_message = "sku_name must look like 'StandardV2_1', 'PremiumV2_2', etc."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "apim-rag-poc"
    purpose = "ai-gateway-load-test"
  }
}

# --- Observability ---
variable "log_retention_days" {
  description = "Log Analytics workspace retention in days (7 for Free tier, or 30-730)."
  type        = number
  default     = 30
}

# --- Networking (optional) ---
# Enable when APIM must reach a backend over a private network. Off by default.
variable "enable_vnet" {
  description = "Create a VNet + APIM subnet for outbound VNet integration."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "Address space for the VNet (used only when enable_vnet = true)."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "apim_subnet_prefix" {
  description = "Address prefix for the APIM subnet (used only when enable_vnet = true)."
  type        = string
  default     = "10.10.1.0/24"
}

# --- AI-gateway capabilities: content safety + semantic caching ---
# Microsoft AI-gateway "security & safety" and "scalability & performance"
# pillars. Flagged so you can opt out to avoid the extra billable resources;
# on by default.

variable "enable_content_safety" {
  description = "Provision an Azure AI Content Safety account for the llm-content-safety policy."
  type        = bool
  default     = true
}

variable "content_safety_sku" {
  description = "SKU for the Azure AI Content Safety (Cognitive Services) account."
  type        = string
  default     = "S0"
}

variable "enable_semantic_cache" {
  description = "Provision Azure Managed Redis as the APIM external cache for semantic caching."
  type        = bool
  default     = true
}

variable "redis_sku" {
  description = "Azure Managed Redis (Redis Enterprise) SKU backing the semantic cache, e.g. Balanced_B0."
  type        = string
  default     = "Balanced_B0"
}

# --- Container platform (ACR + ACA) for the self-hosted model containers ---
variable "acr_sku" {
  description = "SKU for the Azure Container Registry that stores the model image."
  type        = string
  default     = "Basic"
}

# --- Knowledge store (Azure AI Search — the RAG vector DB, like the labs) ---
variable "enable_ai_search" {
  description = "Provision Azure AI Search as the RAG knowledge/vector store."
  type        = bool
  default     = true
}

variable "search_sku" {
  description = "Azure AI Search SKU (free = $0, one per subscription, fine for the demo; basic/standard for real workloads)."
  type        = string
  default     = "free"
}
