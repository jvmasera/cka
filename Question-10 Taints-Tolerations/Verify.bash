#!/bin/bash
# Verify.bash for Question-10 Taints-Tolerations
set +e

NODE="node01"
POD_NAME="nginx"

PASS=true
REASONS=()

# 1. Check Node Taint
NODE_STATUS=$(kubectl get node $NODE -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Node $NODE not found")
else
    TAINT=$(echo "$NODE_STATUS" | jq '.spec.taints[] | select(.key=="PERMISSION" and .value=="granted" and .effect=="NoSchedule")')
    if [ -z "$TAINT" ]; then
        PASS=false
        REASONS+=("REASON: Taint PERMISSION=granted:NoSchedule not found on node $NODE")
    fi
fi

# 2. Check Pod and Toleration
POD_STATUS=$(kubectl get pod $POD_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Pod $POD_NAME not found")
else
    TOLERATION=$(echo "$POD_STATUS" | jq '.spec.tolerations[] | select(.key=="PERMISSION" and .operator=="Equal" and .value=="granted" and .effect=="NoSchedule")')
    if [ -z "$TOLERATION" ]; then
        PASS=false
        REASONS+=("REASON: Pod $POD_NAME does not have the correct toleration")
    fi
    
    # 3. Check if scheduled on node01
    ASSIGNED_NODE=$(echo "$POD_STATUS" | jq -r '.spec.nodeName')
    if [ "$ASSIGNED_NODE" != "$NODE" ]; then
        PASS=false
        REASONS+=("REASON: Pod $POD_NAME is scheduled on $ASSIGNED_NODE, expected $NODE")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Node $NODE correctly tainted and pod $POD_NAME scheduled with proper toleration"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
