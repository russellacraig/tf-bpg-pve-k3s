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
packages:
  - qemu-guest-agent
  - net-tools
runcmd:
  # set timezone for EST
  - timedatectl set-timezone America/Toronto
  # enable and start qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  # user-data-cloud-config done
  - echo "done" > /var/log/user-data-cloud-config.done
