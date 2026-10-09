#!/bin/bash
# Verify.bash for Question-15 Etcd-Fix
set +e

PASS=true
REASONS=()

# 1. Check if kubectl works (API server is up)
if ! kubectl get nodes >/dev/null 2>&1; then
    PASS=false
    REASONS+=("REASON: API server is still down (kubectl get nodes failed)")
fi

# 2. Check kube-apiserver manifest
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
if [ ! -f "$MANIFEST" ]; then
    PASS=false
    REASONS+=("REASON: Manifest $MANIFEST not found")
else
    if ! grep -q "127.0.0.1:2379" "$MANIFEST"; then
        PASS=false
        REASONS+=("REASON: $MANIFEST is still pointing to the wrong etcd endpoint")
    fi
fi

# 3. Check if apiserver pod is running
if ! kubectl get pods -n kube-system | grep -q "kube-apiserver"; then
    PASS=false
    REASONS+=("REASON: kube-apiserver pod not found in kube-system")
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: API server is up and correctly configured to use the local etcd instance"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
