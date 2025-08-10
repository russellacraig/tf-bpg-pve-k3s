#cloud-config
hostname: ${hostname}
fqdn: ${fqdn}
prefer_fqdn_over_hostname: true
create_hostname_file: true
manage_etc_hosts: true
users:
  - name: ${username}
    groups:
      - sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key} 
    sudo: ALL=(ALL) NOPASSWD:ALL
runcmd:
  - apt update
  - apt install -y qemu-guest-agent net-tools
  - timedatectl set-timezone America/Toronto
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "done" > /tmp/cloud-config.done