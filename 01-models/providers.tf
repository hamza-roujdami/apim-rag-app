terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

# Read the provisioning layer's outputs (ACR, pull identity, resource group,
# region). Local state for the PoC; switch to a shared azurerm remote state
# backend for team/production use.
data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = "../00-infra/terraform.tfstate"
  }
}
