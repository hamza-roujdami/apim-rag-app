# ============================================================================
# Model serving — Ollama on Azure Container Instances (ACI).
#
# Runs the baked-model image (built by build.sh) as a single container with a
# public FQDN on port 11434. ACI runs on plain compute — no AKS / Container Apps
# pool — so it isn't affected by Container Apps regional capacity limits. APIM
# (../02-apim) fronts the resulting endpoint as the chat + embeddings backends.
#
# The image is pulled from ACR (admin disabled) using the user-assigned identity
# (AcrPull) provisioned by ../00-infra. Destroy this layer after the demo to
# stop the cost.
# ============================================================================

locals {
  infra            = data.terraform_remote_state.infra.outputs
  acr_login_server = local.infra.acr_login_server
  image_ref        = "${local.acr_login_server}/${var.image}"
}

# A random suffix keeps the public DNS label unique within the region.
resource "random_string" "dns" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_group" "ollama" {
  name                = var.app_name
  resource_group_name = local.infra.resource_group_name
  location            = local.infra.location
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = "${var.app_name}-${random_string.dns.result}"

  identity {
    type         = "UserAssigned"
    identity_ids = [local.infra.aca_pull_identity_id]
  }

  image_registry_credential {
    server                    = local.acr_login_server
    user_assigned_identity_id = local.infra.aca_pull_identity_id
  }

  container {
    name   = "ollama"
    image  = local.image_ref
    cpu    = var.cpu
    memory = var.memory

    ports {
      port     = 11434
      protocol = "TCP"
    }

    environment_variables = {
      OLLAMA_HOST = "0.0.0.0:11434"
    }
  }

  tags = var.tags
}
