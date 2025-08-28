# bgp/proxmox requires 1.3.0 or higher and hashicorp switched to BSL after 1.5.7, OpenTofu supported via .tofu file
terraform {
  required_version = ">= 1.3.0, < 1.5.8"
}
