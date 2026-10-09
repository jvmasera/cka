#!/bin/bash
set -e

# Step 1: Backup current kube-apiserver manifest
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak

# Step 2: Simulate migration issue — change etcd IP to an incorrect IP
sudo sed -i 's/127.0.0.1:2379/127.0.0.99:2379/g' /etc/kubernetes/manifests/kube-apiserver.yaml

# Step 3: Show kube-apiserver pod status/logs
echo "Checking kube-apiserver container..."
KAPISERVER_ID=$(sudo crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -n 1)
if [ -n "$KAPISERVER_ID" ]; then
    sudo crictl logs "$KAPISERVER_ID" | tail -n 10 || true
else
    echo "kube-apiserver pod not found yet"
fi

# Step 4: Verify that kubectl fails as API server is down
kubectl get nodes || echo "As expected, API server is down due to misconfigured etcd IP."
