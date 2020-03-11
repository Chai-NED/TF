# TF - Sample Terraform scripts

# Use them at your own risk

newvmwithdiagandloganalytics.tf
  Pre-req: An existing VNET, subnet, storage account, a key vault with vmpassword secret
  Actions: Create a new VM, enable VM diag extention, create log analytics workspace and connect the VM to it
