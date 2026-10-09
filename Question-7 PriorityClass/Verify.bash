#!/bin/bash
# Verify.bash for Question-7 PriorityClass
set +e

PC_NAME="high-priority"
NS="priority"
DEPLOY_NAME="busybox-logger"

PASS=true
REASONS=()

# 1. Check PriorityClass
PC_STATUS=$(kubectl get pc $PC_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: PriorityClass $PC_NAME not found")
else
    # 2. Check Value (should be max user pc - 1)
    VALUE=$(echo "$PC_STATUS" | jq -r '.value')
    # Find max other user PC
    MAX_OTHER=$(kubectl get pc -o json | jq -r '.items[] | select(.metadata.name != "'$PC_NAME'" and (.metadata.name | startswith("system-") | not)) | .value' | sort -rn | head -n 1)
    
    EXPECTED=$((MAX_OTHER - 1))
    if [ "$VALUE" -ne "$EXPECTED" ]; then
        PASS=false
        REASONS+=("REASON: PriorityClass $PC_NAME value is $VALUE, expected $EXPECTED (one less than $MAX_OTHER)")
    fi
fi

# 3. Check Deployment
DEPLOY_STATUS=$(kubectl get deployment $DEPLOY_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Deployment $DEPLOY_NAME not found in namespace $NS")
else
    PC_IN_DEPLOY=$(echo "$DEPLOY_STATUS" | jq -r '.spec.template.spec.priorityClassName')
    if [ "$PC_IN_DEPLOY" != "$PC_NAME" ]; then
        PASS=false
        REASONS+=("REASON: Deployment $DEPLOY_NAME uses priority class $PC_IN_DEPLOY, expected $PC_NAME")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: PriorityClass $PC_NAME created with correct value and applied to deployment"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
