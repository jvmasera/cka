# Check apiserver logs, fix etcd endpoint
journalctl -u kube-apiserver | tail
sudo sed -n '1,200p' /etc/kubernetes/manifests/kube-apiserver.yaml
# Ensure flag uses correct etcd IP and port
# --etcd-servers=https://127.0.0.1:2379
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml   # correct IP (e.g., change wrong IP to 127.0.0.1), save and wait for static pod restart

# If scheduler also broken, verify its flags
kubectl -n kube-system get pods | grep kube-scheduler
sudo vi /etc/kubernetes/manifests/kube-scheduler.yaml   # kubeconfig path, API server endpoint, cert refs
