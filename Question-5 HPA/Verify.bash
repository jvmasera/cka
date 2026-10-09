#!/bin/bash
# Verify.bash for Question-5 HPA
set +e

NS="autoscale"
HPA_NAME="apache-server"
TARGET_NAME="apache-deployment"

PASS=true
REASONS=()

# 1. Check HPA
HPA_STATUS=$(kubectl get hpa $HPA_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: HPA $HPA_NAME not found in namespace $NS")
else
    # 2. Check Target
    TARGET=$(echo "$HPA_STATUS" | jq -r '.spec.scaleTargetRef.name')
    if [ "$TARGET" != "$TARGET_NAME" ]; then
        PASS=false
        REASONS+=("REASON: HPA targets $TARGET, expected $TARGET_NAME")
    fi
    
    # 3. Check Min/Max Replicas
    MIN=$(echo "$HPA_STATUS" | jq -r '.spec.minReplicas')
    MAX=$(echo "$HPA_STATUS" | jq -r '.spec.maxReplicas')
    if [ "$MIN" -ne 1 ]; then
        PASS=false
        REASONS+=("REASON: HPA minReplicas is $MIN, expected 1")
    fi
    if [ "$MAX" -ne 4 ]; then
        PASS=false
        REASONS+=("REASON: HPA maxReplicas is $MAX, expected 4")
    fi
    
    # 4. Check Metrics
    CPU_TARGET=$(echo "$HPA_STATUS" | jq -r '.spec.metrics[] | select(.resource.name=="cpu") | .resource.target.averageUtilization')
    if [ "$CPU_TARGET" -ne 50 ]; then
        PASS=false
        REASONS+=("REASON: HPA CPU target utilization is $CPU_TARGET, expected 50")
    fi
    
    # 5. Check Behavior (Stabilization Window)
    STAB=$(echo "$HPA_STATUS" | jq -r '.spec.behavior.scaleDown.stabilizationWindowSeconds')
    if [ "$STAB" -ne 30 ]; then
        PASS=false
        REASONS+=("REASON: HPA scaleDown stabilization window is $STAB, expected 30")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: HPA $HPA_NAME correctly configured with target, min/max replicas, and stabilization window"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
