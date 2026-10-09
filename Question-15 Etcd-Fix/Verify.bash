#!/bin/bash
# Verify.bash for Question-15 Etcd-Fix
set +e

PASS=true
REASONS=()

# 2. Check kube-apiserver manifest. Only the --etcd-servers flag matters here
# (the question is specifically about the wrong etcd IP used by that flag);
# other flags in the manifest may legitimately reference 127.0.0.1 on other
# ports (healthz, etc.), so we must not grep for the IP:port anywhere in the
# whole file, only on the etcd-servers line itself.
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
if [ ! -f "$MANIFEST" ]; then
    PASS=false
    REASONS+=("REASON: Manifest $MANIFEST not found")
else
    ETCD_LINE=$(grep -- "--etcd-servers=" "$MANIFEST")
    if [ -z "$ETCD_LINE" ]; then
        PASS=false
        REASONS+=("REASON: --etcd-servers flag not found in $MANIFEST")
    elif ! echo "$ETCD_LINE" | grep -q "127.0.0.1:2379"; then
        PASS=false
        REASONS+=("REASON: $MANIFEST --etcd-servers is still pointing to the wrong etcd IP ($ETCD_LINE)")
    fi
fi

# 1. Check if kubectl works (API server is up). The static pod can take a
# few seconds to restart after the manifest is fixed, so retry for a bit
# before reporting failure, to avoid a false FAIL right after the edit.
API_UP=false
for i in $(seq 1 12); do
    if kubectl get nodes >/dev/null 2>&1; then
        API_UP=true
        break
    fi
    sleep 5
done
if [ "$API_UP" != true ]; then
    PASS=false
    REASONS+=("REASON: API server is still down (kubectl get nodes failed)")
fi

# 3. Check if apiserver pod is running
if ! kubectl get pods -n kube-system 2>/dev/null | grep -q "kube-apiserver"; then
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
