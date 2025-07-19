terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  } 

  # NOTE: Comment this out until backend is bootstrapped
  #backend "azurerm" {
  #  resource_group_name  = "tfstate-rg"
  #  storage_account_name = "yourtfstatestg"
  #  container_name       = "tfstate"
  #  key                  = "keyvault.tfstate"
  #}
}

provider "azurerm" {
  features {}
}

provider "random" {}

data "azurerm_client_config" "current" {}

##########################
# 1. Backend Infrastructure
##########################

resource "azurerm_resource_group" "tfstate_rg" {
  name     = "tfstate-rg"
  location = "East US"
}

resource "azurerm_storage_account" "tfstate_sa" {
  name                     = "yourtfstatestg"  # globally unique, 3-24 lowercase letters/numbers
  resource_group_name      = azurerm_resource_group.tfstate_rg.name
  location                 = azurerm_resource_group.tfstate_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_blob_public_access = false
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate_sa.name
  container_access_type = "private"
}

#############################
# 2. Main Infra Deployment
#############################

resource "azurerm_resource_group" "main_rg" {
  name     = "kv-ci-rg"
  location = "East US"
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = "kv-law-ci"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Random string for unique Key Vault name
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Azure Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                        = "kv-ci-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main_rg.location
  resource_group_name         = azurerm_resource_group.main_rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  soft_delete_enabled         = true
  purge_protection_enabled    = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions         = ["get", "list", "create", "delete"]
    secret_permissions      = ["get", "list", "set", "delete"]
    certificate_permissions = ["get", "list", "create", "delete"]
  }
}

# Diagnostic Settings
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
