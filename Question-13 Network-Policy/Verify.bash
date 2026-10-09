#!/bin/bash
# Verify.bash for Question-13 Network-Policy
set +e

NS="backend"
POLICY_NAME="policy-z"

PASS=true
REASONS=()

# 1. Check if the policy exists
POLICY_STATUS=$(kubectl get networkpolicy $POLICY_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: NetworkPolicy $POLICY_NAME not found in namespace $NS")
else
    # 2. Check podSelector
    SELECTOR=$(echo "$POLICY_STATUS" | jq -r '.spec.podSelector.matchLabels.app')
    if [ "$SELECTOR" != "backend" ]; then
        PASS=false
        REASONS+=("REASON: Policy targets app=$SELECTOR, expected backend")
    fi
    
    # 3. Check ingress rules
    # Policy-z allows from namespace labeled name=frontend AND/OR pods labeled app=frontend
    # Actually policy-z in LabSetUp.bash had two elements in 'from' array:
    # 1. namespaceSelector: {matchLabels: {name: frontend}}
    # 2. podSelector: {matchLabels: {app: frontend}}
    
    F1_NS=$(echo "$POLICY_STATUS" | jq -r '.spec.ingress[0].from[0].namespaceSelector.matchLabels.name')
    F2_POD=$(echo "$POLICY_STATUS" | jq -r '.spec.ingress[0].from[1].podSelector.matchLabels.app')
    
    if [ "$F1_NS" != "frontend" ] || [ "$F2_POD" != "frontend" ]; then
        PASS=false
        REASONS+=("REASON: Ingress rules do not match policy-z (least permissive requirements)")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Least permissive NetworkPolicy (policy-z) correctly applied to backend namespace"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
