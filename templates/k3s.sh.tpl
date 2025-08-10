#!/bin/bash
set -euo pipefail

# variables
HOST=$(hostname -s)
K3S_PORT=6443
K3S_TOKEN="${k3s_token}"
K3S_JOIN_IP="${k3s_join_ip}"

echo "Hostname: $${HOST}"
echo "K3S Join IP: $${K3S_JOIN_IP}"
echo "Token: [REDACTED]"

# function to wait until control-1 API is reachable before joining
wait_for_primary() {
  echo "Waiting for control-1 K3s API at $${K3S_JOIN_IP}:$${K3S_PORT}..."
  until nc -vz "$${K3S_JOIN_IP}" "$${K3S_PORT}"; do
    echo "control-1 not reachable yet, retrying in 5s..."
    sleep 5
  done
  echo "control-1 reachable at $${K3S_JOIN_IP}:$${K3S_PORT}"
}

# function to install primary control node
install_primary_control() {
  echo "Bootstrapping K3s control-plane (leader)..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-taint CriticalAddonsOnly=true:NoExecute" K3S_TOKEN="$${K3S_TOKEN}" sh -s - --write-kubeconfig-mode=644 --cluster-init

  echo "K3s primary node setup complete."
}

# function to install additional control plane nodes
install_additional_control() {
  wait_for_primary

  echo "Joining additional to control-1..."
  #curl -sfL https://get.k3s.io | K3S_URL="https://$${K3S_JOIN_IP}:$${K3S_PORT}" K3S_TOKEN="$$K3S_TOKEN" sh -s - server
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-taint CriticalAddonsOnly=true:NoExecute" K3S_TOKEN="$${K3S_TOKEN}" sh -s - --write-kubeconfig-mode=644 --server=https://$${K3S_JOIN_IP}:$${K3S_PORT}

  echo "additional control setup complete."
}

# function to install agent nodes
install_agent() {
  wait_for_primary

  echo "Joining as agent node..."
  curl -sfL https://get.k3s.io | K3S_URL="https://$${K3S_JOIN_IP}:$${K3S_PORT}" K3S_TOKEN="$${K3S_TOKEN}" sh -

  echo "Agent node setup complete."
}

# call functions based on host
case "$${HOST}" in
  control-1)
    install_primary_control
    ;;
  control-*)
    install_additional_control
    ;;
  agent-*)
    install_agent
    ;;
  *)
    echo "Unknown hostname pattern: $${HOST}"
    exit 1
    ;;
esac