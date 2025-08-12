# tf-bpg-pve-k3s
Deploy a [k3s](https://k3s.io/) cluster on an existing [Proxmox VE](https://www.proxmox.com/en/products/proxmox-virtual-environment/overview) host for homelab scenarios using [Terraform](https://www.hashicorp.com/en/products/terraform) leveraging the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider
> [!IMPORTANT]
> Tested with PVE 8.4.1, Terraform 1.5.7 and bpg/proxmox 0.70.0.\
> Requirements may change in PVE 9.x and have not been tested (by me).

The onboarding steps can be skipped if you've already configured this for bpg/proxmox.
## Terraform PVE Onboarding (API)
SSH to your pve instance:
```bash
$ ssh root@pve.lan
```
Create the user pve terraform account:
```bash
$ pveum user add terraform@pve
```
Create the pve terraform role with required privledges:
```bash
$ pveum role add Terraform -privs "\
Datastore.Allocate \
Datastore.AllocateSpace \
Datastore.AllocateTemplate \
Datastore.Audit Pool.Allocate \
Sys.Audit \
Sys.Console \
Sys.Modify \
SDN.Use \
VM.Allocate \
VM.Audit \
VM.Clone \
VM.Config.CDROM \
VM.Config.Cloudinit \
VM.Config.CPU \
VM.Config.Disk \
VM.Config.HWType \
VM.Config.Memory \
VM.Config.Network \
VM.Config.Options \
VM.Migrate \
VM.Monitor \
VM.PowerMgmt \
User.Modify"
```
Assign the PVE terraform role to the PVE terraform user account:
```bash
$ pveum aclmod / -user terraform@pve -role Terraform
```
Create a token for the PVE terraform user account:
> [!IMPORTANT]
> Record this for terraform.tfvars, you will not be able to recover this later.
```bash
$ pveum user token add terraform@pve token -privsep 0
```
Enable snippets on local storage:
```bash
$ pvesm set local --content vztmpl,backup,iso,snippets
```
## Terraform PVE Onboarding (SSH)
Due to limitations with the PVE, some provider actions must be performed via SSH, so create a linux system user on the PVE host:
```bash
$ useradd -m terraform
```
Install sudo
```bash
$ apt install sudo
```
Add the terraform user to sudoers:
```bash
$ visudo -f /etc/sudoers.d/terraform
```
Content to be added to /etc/sudoers.d/terraform:
```
terraform ALL=(root) NOPASSWD: /sbin/pvesm
terraform ALL=(root) NOPASSWD: /sbin/qm
terraform ALL=(root) NOPASSWD: /usr/bin/tee /var/lib/vz/*
```
Add your public key to the authorized_keys of the terraform account:
```bash
$ mkdir ~terraform/.ssh
$ chmod 700 ~terraform/.ssh
# add the public key you're going to use with the provider to the authorized_keys
$ vi ~terraform/.ssh/authorized_keys
$ chmod 600 ~terraform/.ssh/authorized_keys
$ chown -R terraform:terraform ~terraform/.ssh
```
Verify connectivity from your workstation that you'll be excuting the terraform from:
```bash
$ ssh terraform@pve.lan "sudo pvesm apiinfo"
```
## Providers Configuration (terraform.tfvars)
An example is provided (terraform.tfvars.example) which you can use as a reference:
```
bpg_provider = {
    agent            = false
    api_token        = "terraform@pve!token=00000000-0000-0000-0000-000000000000"
    endpoint         = "https://proxmox-hostname-or-ip-address:8006/"
    insecure         = true
    private_key_file = "~/.ssh/id_ed25519"
    username         = "terraform"
}

k3s_token = "MySuperSecretValue"
```
Copy the example to terraform.tfvars and update with your details.

## Terraform Deployment
```bash
$ terraform init
$ terraform plan
$ terraform apply
```
## Terraform Cleanup
```bash
$ terraform destroy
```
## Terraform Variables
The variables are declared in main.tf with their defaults (These might be moved to a variables.tf later) and you can override as needed... the virtualmachine defaults will create 1 control host and 2 agents:
> [!IMPORTANT]
> The k3s.tpl is configured to taint the control host(s) not to run any user workloads.\
> You'll need to modify this if you decide to run only a single control host with no agents.
```
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
```
## Kubectl Config
A copy of the k3s.yaml will be downloaded from the primary control host and saved locally in the working terraform directory as "kubeconfig" and automatically updated to have the remote ip... copy this to ~/.kube/config or copy the contents to your existing config.