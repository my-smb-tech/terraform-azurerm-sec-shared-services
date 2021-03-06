provider "azurerm" {
  version = "~>2.0"
  features {}
}

locals {
  suffix                                = concat(["ss"], var.suffix)
  resource_group_location               = var.resource_group_location
  network_watcher_resource_group        = "NetworkWatcherRG"
  private_build_agent_subnet_id         = module.virtual_network.private_build_agent_subnet.id
  authorized_audit_subnet_ids           = concat(var.authorized_audit_subnet_ids, [local.private_build_agent_subnet_id])
  authorized_security_subnet_ids        = concat(var.authorized_security_subnet_ids, [local.private_build_agent_subnet_id])
  authorized_persistent_data_subnet_ids = concat(var.authorized_persistent_data_subnet_ids, [local.private_build_agent_subnet_id])
}

module "naming" {
  source = "git::https://github.com/Azure/terraform-azurerm-naming"
  suffix = local.suffix
}

///////////////////////////////////
// Shared Service Networking
///////////////////////////////////

module "virtual_network" {
  source                                  = "./submodules/virtual_networking"
  virtual_network_name                    = var.shared_services_virtual_network_name
  virtual_network_resource_group_location = var.resource_group_location
  virtual_network_resource_group_name     = var.shared_services_virtual_network_resource_group_name
  suffix                                  = local.suffix
  #firewall_public_ip_sku      = var.firewall_public_ip_sku
}

module "virtual_network_diagnostic_settings" {
  source                                  = "./submodules/diagnostic_settings/virtual_network"
  shared_service_virtual_network          = module.virtual_network.virtual_network
  shared_service_network_watcher_location = local.resource_group_location
  shared_service_subnet_nsg_ids           = module.virtual_network.nsg_ids
  shared_service_data_nsg                 = module.virtual_network.data_subnet_network_security_group
  shared_service_audit_nsg                = module.virtual_network.audit_subnet_network_security_group
  shared_service_secrets_nsg              = module.virtual_network.secrets_subnet_network_security_group
  shared_service_diag_storage             = module.audit_diagnostics_package.storage_account
  shared_service_diag_log_analytics       = module.audit_diagnostics_package.log_analytics_workspace
  shared_service_log_retention_duration   = var.log_retention_duration
  #shared_service_firewall                 = module.virtual_network.firewall
}

module "virtual_networking_policy" {
  source                     = "./submodules/policy_assignment"
  target_resource_group      = module.virtual_network.resource_group
  log_retention_days         = var.log_retention_duration
  log_analytics_workspace_id = module.audit_diagnostics_package.log_analytics_workspace.name
  log_storage_account_name   = module.audit_diagnostics_package.storage_account.name
}

///////////////////////////////////
// Shared Service Diagnostics
///////////////////////////////////

module "audit_diagnostics_package" {
  source                                     = "git::https://github.com/Azure/terraform-azurerm-sec-audit-diagnostics-package"
  storage_account_private_endpoint_subnet_id = module.virtual_network.audit_subnet.id
  use_existing_resource_group                = false
  resource_group_location                    = local.resource_group_location
  suffix                                     = local.suffix
  event_hub_namespace_sku                    = "Standard"
  event_hub_namespace_capacity               = "1"
  event_hubs = {
    "eh-ss" = {
      name              = module.naming.eventhub.name
      partition_count   = 1
      message_retention = 1
      authorisation_rules = {
        "ehra-ap" = {
          name   = module.naming.eventhub_authorization_rule.name
          listen = true
          send   = true
          manage = true
        }
      }
    }
  }
  log_analytics_workspace_sku           = "PerGB2018"
  log_analytics_retention_in_days       = var.log_retention_duration
  automation_account_alternate_location = local.resource_group_location
  automation_account_sku                = "Basic"
  storage_account_name                  = module.naming.storage_account.name_unique
  storage_account_tier                  = "Standard"
  storage_account_replication_type      = "LRS"

  #TODO: Work out what additional if any allowed ip ranges and permitted virtual network subnets there needs to be.

  allowed_ip_ranges                    = concat([], var.authorized_audit_client_ips)
  permitted_virtual_network_subnet_ids = concat([], local.authorized_audit_subnet_ids)
  bypass_internal_network_rules        = true
}

module "audit_diagnostic_settings" {
  source                                = "./submodules/diagnostic_settings/audit_diagnostics"
  shared_service_eventhub_namespace     = module.audit_diagnostics_package.event_hub_namespace
  shared_service_automation_account     = module.audit_diagnostics_package.automation_account
  shared_service_diag_storage           = module.audit_diagnostics_package.storage_account
  shared_service_diag_log_analytics     = module.audit_diagnostics_package.log_analytics_workspace
  shared_service_log_retention_duration = var.log_retention_duration
}

module "audit_diagnostics_policy" {
  source                     = "./submodules/policy_assignment"
  target_resource_group      = module.audit_diagnostics_package.resource_group
  log_retention_days         = var.log_retention_duration
  log_analytics_workspace_id = module.audit_diagnostics_package.log_analytics_workspace.name
  log_storage_account_name   = module.audit_diagnostics_package.storage_account.name
}

///////////////////////////////////
// Shared Service Security
///////////////////////////////////

module "security_package" {
  source                               = "git::https://github.com/Azure/terraform-azurerm-sec-security-package"
  use_existing_resource_group          = false
  resource_group_location              = local.resource_group_location
  key_vault_private_endpoint_subnet_id = module.virtual_network.secrets_subnet.id
  suffix                               = local.suffix

  #TODO: Work out what additional if any allowed ip ranges and permitted virtual network subnets there needs to be.

  allowed_ip_ranges                    = concat([], var.authorized_security_client_ips)
  permitted_virtual_network_subnet_ids = concat([], local.authorized_security_subnet_ids)
  sku_name                             = "standard"
  enabled_for_deployment               = true
  enabled_for_disk_encryption          = true
  enabled_for_template_deployment      = true
}

module "security_diagnostic_settings" {
  source                                = "./submodules/diagnostic_settings/security"
  shared_service_key_vault              = module.security_package.key_vault
  shared_service_diag_storage           = module.audit_diagnostics_package.storage_account
  shared_service_diag_log_analytics     = module.audit_diagnostics_package.log_analytics_workspace
  shared_service_log_retention_duration = var.log_retention_duration
}

module "security_policy" {
  source                     = "./submodules/policy_assignment"
  target_resource_group      = module.security_package.resource_group
  log_retention_days         = var.log_retention_duration
  log_analytics_workspace_id = module.audit_diagnostics_package.log_analytics_workspace.name
  log_storage_account_name   = module.audit_diagnostics_package.storage_account.name
}

///////////////////////////////////
// Shared Service Persistent Data
///////////////////////////////////

resource "azurerm_resource_group" "persistent_data" {
  name     = "${module.naming.resource_group.slug}-data-${join("-", local.suffix)}"
  location = var.resource_group_location
}

module "persistent_data" {
  source                           = "git::https://github.com/Azure/terraform-azurerm-sec-storage-account"
  resource_group_name              = azurerm_resource_group.persistent_data.name
  resource_group_location          = azurerm_resource_group.persistent_data.location
  storage_account_name             = join("", ["persistent", module.naming.storage_account.name_unique])
  storage_account_tier             = "Standard"
  storage_account_replication_type = "LRS"

  #TODO: Work out what additional if any allowed ip ranges and permitted virtual network subnets there needs to be.
  allowed_ip_ranges                    = concat([], var.authorized_persistent_data_client_ips)
  permitted_virtual_network_subnet_ids = concat([module.virtual_network.data_subnet.id], local.authorized_persistent_data_subnet_ids)
  enable_data_lake_filesystem          = false
  data_lake_filesystem_name            = module.naming.storage_data_lake_gen2_filesystem.name_unique
  bypass_internal_network_rules        = true
}

#TODO: Check for key standard i.e key bit length and preferred crypto algorithm
module "persistent_data_managed_encryption_key" {
  source                 = "git::https://github.com/Azure/terraform-azurerm-sec-storage-managed-encryption-key"
  storage_account        = module.persistent_data.storage_account
  key_vault_id           = module.security_package.key_vault.id
  client_key_permissions = ["get", "delete", "create", "unwrapkey", "wrapkey", "update"]
  suffix                 = local.suffix
}

module "data_policy" {
  source                     = "./submodules/policy_assignment"
  target_resource_group      = azurerm_resource_group.persistent_data
  log_retention_days         = var.log_retention_duration
  log_analytics_workspace_id = module.audit_diagnostics_package.log_analytics_workspace.name
  log_storage_account_name   = module.audit_diagnostics_package.storage_account.name
}
