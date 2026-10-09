#!/bin/bash
# Verify.bash for Question-2 ArgoCD
set +e

NS="argocd"
HELM_FILE="/root/argo-helm.yaml"

PASS=true
REASONS=()

# 1. Check Namespace
if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
    PASS=false
    REASONS+=("REASON: Namespace $NS not found")
fi

# 2. Check Helm manifest file
if [ ! -f "$HELM_FILE" ]; then
    PASS=false
    REASONS+=("REASON: File $HELM_FILE not found")
else
    # 3. Check if CRDs are NOT in the manifest
    if grep -q "kind: CustomResourceDefinition" "$HELM_FILE"; then
        PASS=false
        REASONS+=("REASON: CRDs found in $HELM_FILE, but they should not be included")
    fi
    
    # 4. Check if it's actually an ArgoCD manifest (basic check)
    if ! grep -q "app.kubernetes.io/name: argocd" "$HELM_FILE"; then
        PASS=false
        REASONS+=("REASON: $HELM_FILE does not appear to contain ArgoCD resources")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Namespace $NS exists and ArgoCD manifest created without CRDs"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
