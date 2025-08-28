# bgp/proxmox requires 1.3.0 or higher and hashicorp switched to BSL after 1.5.7, this .tofu file enables OpenTofu initial release and higher
terraform {
  required_version = ">= 1.6.0"
}
