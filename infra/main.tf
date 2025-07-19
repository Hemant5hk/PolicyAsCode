terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70.0"  # Adjust version as needed
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }

  # COMMENT THIS BLOCK DURING INITIAL BACKEND BOOTSTRAP
  #backend "azurerm" {
  #  resource_group_name  = "tfstate-rg"
  #  storage_account_name = "yourtfstatestg"     # Must be globally unique
  #  container_name       = "tfstate"
  #  key                  = "keyvault.tfstate"
  #}
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

provider "random" {}

data "azurerm_client_config" "current" {}

##########################
# Backend Resources
##########################

resource "azurerm_resource_group" "tfstate_rg" {
  name     = "tfstate-rg"
  location = "East US"
}

resource "azurerm_storage_account" "tfstate_sa" {
  name                     = "yourtfstatestg"  # globally unique
  resource_group_name      = azurerm_resource_group.tfstate_rg.name
  location                 = azurerm_resource_group.tfstate_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate_sa.name
  container_access_type = "private"
}

##########################
# Main Infra Resources
##########################

resource "azurerm_resource_group" "main_rg" {
  name     = "kv-ci-rg"
  location = "East US"
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "kv-law-ci"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_key_vault" "keyvault" {
  name                        = "kv-ci-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main_rg.location
  resource_group_name         = azurerm_resource_group.main_rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions         = ["get", "list", "create", "delete"]
    secret_permissions      = ["get", "list", "set", "delete"]
    certificate_permissions = ["get", "list", "create", "delete"]
  }
}

resource "azurerm_monitor_diagnostic_setting" "kv_diag" {
  name                       = "keyvault-diag"
  target_resource_id         = azurerm_key_vault.keyvault.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  log {
    category = "AuditEvent"
    enabled  = true

    retention_policy {
      enabled = false
      days    = 0
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
      days    = 0
    }
  }
}
