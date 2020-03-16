

# supply you own info

provider "azurerm" {
    subscription_id = ""
   
    tenant_id       = ""
}

# Resource location
variable "service_location" {
  type = "string"
  default  = "eastus2"
  
}

# Existing resource group
data "azurerm_resource_group" "test" {
  name = "<existing resource group>"
}


# Existing storage account for diagnostics
data "azurerm_storage_account" "test" {
  name                = "<yourown>"
  resource_group_name = "<Exising RG where storage account is>"
}

# Existing key vault with a secret. This is the password that will be used for the VM
data "azurerm_key_vault_secret" "Secret" {
name = "vmpassword"
key_vault_id = "<key vault URI"
}

#Existing VNET
data "azurerm_virtual_network" "VNET" {
  name                 = "<yourown>"
  resource_group_name  = "<existing RG where Vnet is >"
}



#refer to a subnet
data "azurerm_subnet" "test" {
  name                 = "default"
  virtual_network_name = "VNET1"
  resource_group_name  = "<existing RG where Vnet is >"
}


#Resources will be created after this line 

resource "azurerm_log_analytics_workspace" "test" {
  name                = "<New Log analytic workspace name>"
  location            = "${var.service_location}"
  resource_group_name = "${data.azurerm_resource_group.test.name}"
  sku                 = "Free"
//  retention_in_days   = "30"
}

resource "azurerm_public_ip" "pip" {
    name                         = "myPublicIP3"
    location                     = "${var.service_location}"

    resource_group_name          = "${data.azurerm_resource_group.test.name}"
    allocation_method            = "Dynamic"

    tags = {
        environment = "Terraform Demo"
    }
}



resource "azurerm_network_interface" "nic" {
    name                        = "myNIC3"
    location                    = "${var.service_location}"
    resource_group_name          = "${data.azurerm_resource_group.test.name}"
    

    ip_configuration {
        name                          = "myNicConfiguration3"
        subnet_id                     = "${data.azurerm_subnet.test.id}"
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = "${azurerm_public_ip.pip.id}"
    }

    tags = {
        environment = "Terraform and Log Analytics"
    }
}


resource "azurerm_virtual_machine" "linux" {
    name                  = "myVM3"
    location              = "${var.service_location}"
    resource_group_name   = "${data.azurerm_resource_group.test.name}"
    network_interface_ids = ["${azurerm_network_interface.nic.id}"]
    vm_size               = "Standard_DS1_v2"

    storage_os_disk {
        name              = "myOsDisk3"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "chaimmavm"
        admin_username = "chaiadmin"
        admin_password = "${data.azurerm_key_vault_secret.Secret.value}"
        
    }

    os_profile_linux_config {
        
        disable_password_authentication = false
        
    }

    boot_diagnostics {
        enabled     = "true"
        storage_uri = "${data.azurerm_storage_account.test.primary_blob_endpoint}"
    }

    tags = {
        environment = "Quick Unbuntu VM with diag extension"
    }
}




/*
// This is used for Microsoft.OSTCExtensions 2.3 (the portal default)
data "template_file" "wadcfg" {
  template = "${file("${path.module}/diagnostics/wadcfg.xml.tpl")}"

  vars {
    virtual_machine_id = "${azurerm_virtual_machine.linux.id}"
  }
}

// This is used for Microsoft.OSTCExtensions 2.3 (the portal default)
data "template_file" "settings" {
  template = "${file("${path.module}/diagnostics/settings2.3.json.tpl")}"

  vars {
    xml_cfg           = "${base64encode(data.template_file.wadcfg.rendered)}"
    diag_storage_name = "${var.diag_storage_name}"
  }
}
*/


// This is used only if you require the Azure.Linux.Diagnostics 3.0 extension

data "azurerm_storage_account_sas" "diagnostics" {
  connection_string = "${data.azurerm_storage_account.test.primary_connection_string}"
  https_only        = true
  resource_types {
    service   = false
    container = true
    object    = true
  }
  services {
    blob  = true
    queue = false
    table = true
    file  = false
  }
  start  = "2018-06-01"
  expiry = "2118-06-01"
  permissions {
    read    = true
    write   = true
    delete  = false
    list    = true
    add     = true
    create  = true
    update  = true
    process = false
  }
}

data "template_file" "settings" {
  template = "${file("${path.module}/settings3.x.json.tpl")}"
  vars = {
    diag_storage_name = "${data.azurerm_storage_account.test.name}"
    virtual_machine_id = "${azurerm_virtual_machine.linux.id}"
  }
}


data "template_file" "protected_settings" {
  template = "${file("${path.module}/protected_settings3.0.json.tpl")}"

  vars = {
    diag_storage_name               = "${data.azurerm_storage_account.test.name}"
    diag_storage_primary_access_key = "${data.azurerm_storage_account.test.primary_access_key}"

    # if using Azure.Linux.Diagnostics 3.0, you MUST supply a SAS and skip the leading "?".
     diag_storage_sas = "${substr(data.azurerm_storage_account_sas.diagnostics.sas,1,-1)}"
  }
}

resource "azurerm_virtual_machine_extension" "vmdiagextension" {
  name                       = "diagextension"
  resource_group_name        = "${data.azurerm_resource_group.test.name}"
  location                   = "${var.service_location}"
  virtual_machine_name       = "${azurerm_virtual_machine.linux.name}"
  publisher = "Microsoft.Azure.Diagnostics"
  type                       = "LinuxDiagnostic"
  type_handler_version       = "3.0"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine.linux] 
  settings           = "${data.template_file.settings.rendered}"
  protected_settings = "${data.template_file.protected_settings.rendered}"
  
}
output "virtual_machine" {
  value = "${azurerm_virtual_machine.linux.id}"
}

output "workspace_id" {
    value = "${azurerm_log_analytics_workspace.test.workspace_id}"
}

output "workspace_key" {
    value = "${azurerm_log_analytics_workspace.test.primary_shared_key}"
}


resource "azurerm_virtual_machine_extension" "MMA" {
  name = "AzureMonitorAgent1"
  location             = "${var.service_location}"
  resource_group_name  = "${data.azurerm_resource_group.test.name}"
  virtual_machine_name = "${azurerm_virtual_machine.linux.name}"
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "OmsAgentForLinux"
  type_handler_version = "1.9"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.vmdiagextension]
 

  settings = <<SETTINGS
        {
          "workspaceId": "${azurerm_log_analytics_workspace.test.workspace_id}"
        }
        SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
        {
          "workspaceKey": "${azurerm_log_analytics_workspace.test.primary_shared_key }"
        }
        PROTECTED_SETTINGS
}
