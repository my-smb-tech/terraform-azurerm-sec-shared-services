provider "azurerm" {
  version = "~>2.0"
  features {}
}

/* Ideally policies should be instantiated once at a management or subscription level. To demonstrate policy coverage the below policies have been applied mulitple times
at the resource group level.
*/

locals {
  cis_policy_display_name      = "CIS Microsoft Azure Foundations Benchmark 1.1.0"
  official_policy_display_name = "UK OFFICIAL and UK NHS"
  #auto_diagnostics_display_name = "Auto Diagnostics Policy Initiative"
}

resource "azurerm_policy_assignment" "cis_assignment" {
  name                 = local.cis_policy_display_name
  scope                = var.target_resource_group.id
  policy_definition_id = data.azurerm_policy_set_definition.cis_set_definition.id
  description          = data.azurerm_policy_set_definition.cis_set_definition.description
  display_name         = local.cis_policy_display_name
}

resource "azurerm_policy_assignment" "official_assignment" {
  name                 = local.official_policy_display_name
  scope                = var.target_resource_group.id
  policy_definition_id = data.azurerm_policy_set_definition.official_set_definition.id
  description          = data.azurerm_policy_set_definition.official_set_definition.description
  display_name         = local.official_policy_display_name
  location             = var.target_resource_group.location

  #Specifying a system assigned identity here due to this policy having create if not exists effect policies. 
  identity {
    type = "SystemAssigned"
  }
}

/*This policy is used to ensure that all new resources are automatically registered to send their diagnostic and metric logs to
an audit and diagnostics monitoring solution. While this policy can be applied at the resource group level it is advised to apply this at the management
or subscription level in a deploy once utilise mulitple times capacity.*/

/* resource "azurerm_policy_assignment" "diagnostics_assignment" {
  name                 = local.auto_diagnostics_display_name
  scope                = var.target_resource_group.id
  policy_definition_id = data.azurerm_policy_set_definition.auto_diagnostics_set_definition.id
  description          = data.azurerm_policy_set_definition.auto_diagnostics_set_definition.description
  display_name         = local.auto_diagnostics_display_name
  location             = var.target_resource_group.location

  identity {
    type = "SystemAssigned"
  }

  parameters = <<PARAMETERS
    {
        "requiredRetentionDays": {
            "value": "${var.log_retention_days}"
        },
        "workspaceId": {
            "value": "${var.log_analytics_workspace_id}"
        },
        "storageAccountName": {
            "value" : "${var.log_storage_account_name}"
        },
        "resourceLocation": {
            "value" : "${var.target_resource_group.location}"
        }
    }
PARAMETERS
} */
