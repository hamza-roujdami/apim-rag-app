terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2"
    }
    # Backend pools + Managed Redis listKeys are preview/data-plane operations
    # not covered by azurerm.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.4"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

# Read the provisioning layer (APIM, App Insights, Content Safety, Redis, RG).
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../00-infra/terraform.tfstate"
  }
}

# Read the model-serving layer (the ACI Ollama endpoint the backends point at).
data "terraform_remote_state" "models" {
  backend = "local"
  config = {
    path = "../01-models/terraform.tfstate"
  }
}
