terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2"
    }
    # Required by the Content Safety (avm-res-cognitiveservices-account) and
    # Managed Redis (avm-res-cache-redisenterprise) AVM modules.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.4"
    }
  }

  # This root uses local state. For anything shared, switch to an azurerm remote
  # backend (storage account) — left commented until we pick a state location.
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "azapi" {}
