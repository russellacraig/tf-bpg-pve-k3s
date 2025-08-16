# bgp/proxmox requires 1.3.0 or higher and hashicorp switched to BSL after 1.5.7 (will test with OpenTofu later)
terraform {
  required_version = ">= 1.3.0, < 1.5.8"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }
}

# provider configuration, see: https://registry.terraform.io/providers/bpg/proxmox/latest/docs#example-usage
provider "proxmox" {
  api_token = var.bpg_provider["api_token"]
  insecure = var.bpg_provider["insecure"]
  endpoint = var.bpg_provider["endpoint"]

  ssh {
    agent       = var.bpg_provider["agent"]
    username    = var.bpg_provider["username"]
    private_key = file("${var.bpg_provider["private_key_file"]}")
  }
}

# variable to store provider configuration, populate these in your local terraform.tfvars (terraform.tfvars.example can be used as a reference)
variable "bpg_provider" {
  description = "list of bpg proxmox provider configuration details"
  type = object({
    agent             = bool 
    api_token         = string
    endpoint          = string
    insecure          = bool
    private_key_file  = string
    username          = string
  })
  default = null
}

# variable to store the domain to append to the hosts created (may move to virtualmachines variable later)
variable "domain" {
  description = "domain to append to hosts for fqdn"
  type        = string
  default     = "lan"
}

# variable to store the k3s token used when setting up the k3s cluster, populate this in your local terraform.tfvars (terraform.tfvars.example can be used as a reference)
variable "k3s_token" {
  description = "k3s token used when setting up the k3s cluster"
  type        = string
  default     = null
}

# variable to store the ssh public key file location so we can access our virtual machines (may move to virtualmachines variable later)
variable "ssh_pub_key_file" {
  description = "ssh public key file that'll be used in places like user-data authorized keys"
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

# variable to define common proxmox details like datastores for disks, iso, snippets
variable "proxmox" {
  description = "list of pve configuration details like datastore disks, iso, snippets"
  type = object({
    datastore_id_disks    = string # where to store vm disks
    datastore_id_iso      = string # where to store iso images
    datastore_id_snippets = string # where to store snippets for things like user-data cloud-init
    node_name             = string # which proxmox node to use
  })
  default = {
    datastore_id_disks    = "local-lvm"
    datastore_id_iso      = "local"
    datastore_id_snippets = "local"
    node_name             = "pve"
  }
}

# variable to define virtual machine types and their configurations, supporting multiple counts of each type (this will be flattened and expanded using locals)
variable "virtualmachines" {
  description = "map of virtual machine types and their configurations"
  type = map(object({
    base_cidr      = string # base cidr like "192.168.1.0/24" for use with cidrhost later
    base_ip_offset = number # base cidr ip offset like "20" for use with base_cidr and cidrhost later (ie. 192.168.1.21/24 end result)
    base_vmid      = number # base vmid which incriments per vm, ensure your counts and base leave enough room per type
    bridge         = string # pve bridge to use for vm networking, typically vmbr0 unless you've setup additional bridges/networks
    count          = number # number of vm to create for this type
    cpu            = number # number of cpu to assign per vm for this type
    gateway        = string # networking gateway like "192.168.1.1"
    memory         = number # amount of memory to assign per vm for this type
  }))
  default = {
    agent = {
      base_cidr      = "192.168.1.0/24"
      base_ip_offset = 30
      base_vmid      = 3000
      bridge         = "vmbr0"
      count          = 2
      cpu            = 2
      gateway        = "192.168.1.1"
      memory         = 2048
    }
    control = {
      base_cidr      = "192.168.1.0/24"
      base_ip_offset = 20
      base_vmid      = 2000
      bridge         = "vmbr0"
      count          = 1
      cpu            = 2
      gateway        = "192.168.1.1"
      memory         = 2048
    }
  }
}

locals {
 
  # flattening and expanding (based off count) of virtualmachines map allowing us to create multiple instances of each type
  virtualmachines = flatten([
    for vm_type, vm_config in var.virtualmachines : [
      for i in range(vm_config.count) : {
        bridge   = vm_config.bridge
        cpu      = vm_config.cpu
        index    = i
        ip       = cidrhost(vm_config.base_cidr, vm_config.base_ip_offset + i + 1)
        memory   = vm_config.memory
        gateway  = vm_config.gateway
        name     = "${vm_type}-${i + 1}"
        type     = vm_type
        vmid     = vm_config.base_vmid + (i + 1)
      }
    ]
  ])

  # we will push control-1 ip address into our get.k3s.io provisioning later
  k3s_join_ip = one([
    for vm in local.virtualmachines : vm.ip
    if vm.name == "control-1"
  ])

}

# upload the noble cloudimg to the iso datastore
resource "proxmox_virtual_environment_download_file" "image" {
  content_type = "iso"
  datastore_id = var.proxmox["datastore_id_iso"]
  file_name    = "tf-bpg-pve-k3s_noble-server-cloudimg-amd64.img"
  node_name    = var.proxmox["node_name"] 

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# generate user-data cloud-init from our template
data "template_file" "user_data_cloud_config" {
  for_each = {
    for vm in local.virtualmachines : vm.name => vm
  }

  template = file("templates/user-data.yaml.tpl")

  vars = {
    fqdn           = "${each.key}.${var.domain}"
    hostname       = each.key
    username       = "ubuntu"
    ssh_public_key = trimspace(file("${var.ssh_pub_key_file}"))
  }

}

# upload our generated user-data cloud-init to the snippets datastore
resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  for_each = {
    for vm in local.virtualmachines : vm.name => vm
  }

  content_type = "snippets"
  datastore_id = var.proxmox["datastore_id_snippets"]
  node_name    = var.proxmox["node_name"]

  source_raw {
    data = data.template_file.user_data_cloud_config[each.key].rendered
    file_name    = "${each.value.vmid}-user-data-cloud-config.yaml"
  }

}

# create our virtualmachines
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = {
    for vm in local.virtualmachines : vm.name => vm
  }

  name      = each.key
  node_name = var.proxmox["node_name"]
  vm_id     = each.value.vmid

  cpu {
    cores   = each.value.cpu
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = each.value.bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.proxmox["datastore_id_disks"] 
    file_id      = proxmox_virtual_environment_download_file.image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = each.value.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config[each.key].id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("${var.bpg_provider["private_key_file"]}")
    host        = each.value.ip
  }

  provisioner "file" {
    destination = "/tmp/k3s.sh"
      content = templatefile("templates/k3s.sh.tpl",
        {
          k3s_token = var.k3s_token,
          k3s_join_ip = local.k3s_join_ip
        }
    )
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod 700 /tmp/k3s.sh",
      "sudo /tmp/k3s.sh"
    ]
  }

}

# download remote /etc/rancher/k3s/k3s.yaml and make it viable as a drop in for ~/.kube/config (we won't place this ourselves to avoid overwriting an existing valid config on the local host)
resource "null_resource" "download_kubeconfig" {

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.bpg_provider["private_key_file"]} ubuntu@${local.k3s_join_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig"
  }
  provisioner "local-exec" {
    command = "sed -i 's|https://127.0.0.1:6443|https://${local.k3s_join_ip}:6443|' ./kubeconfig"
  }

  depends_on = [
    proxmox_virtual_environment_vm.vm["control-1"]
  ]

}

# helpful output for viewing the flattened and expanded virtualmachines local
output "virtualmachines_details" {
  value = local.virtualmachines
}

# virtual machine ip addresses (for easy consolidated human readability)
output "virtualmachines_ip_addresses" {
  value = {
    for vm in local.virtualmachines : vm.name => vm.ip
  }
}
