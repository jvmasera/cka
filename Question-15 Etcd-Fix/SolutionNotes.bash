# Check apiserver logs, fix etcd endpoint
journalctl -u kube-apiserver | tail
sudo sed -n '1,200p' /etc/kubernetes/manifests/kube-apiserver.yaml
# Ensure flag uses correct etcd IP and port
# --etcd-servers=https://127.0.0.1:2379
# Fix the wrong etcd IP back to the correct one (127.0.0.1), kubelet will
# automatically restart the static pod after the manifest is saved.
sudo sed -i -E 's/(--etcd-servers=https:\/\/)[0-9.]+(:2379)/\1127.0.0.1\2/' /etc/kubernetes/manifests/kube-apiserver.yaml

# Wait for the kube-apiserver static pod to come back up
echo "Waiting for API server to come back up..."
until kubectl get nodes >/dev/null 2>&1; do sleep 5; done

# If scheduler also broken, verify its flags
kubectl -n kube-system get pods | grep kube-scheduler
