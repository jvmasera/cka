#!/bin/bash
# Verify.bash for Question-4 Resource-Allocation
set +e

DEPLOY_NAME="wordpress"

PASS=true
REASONS=()

# 1. Check Deployment
DEPLOY_STATUS=$(kubectl get deployment $DEPLOY_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Deployment $DEPLOY_NAME not found")
else
    # 2. Check Replicas
    REPLICAS=$(echo "$DEPLOY_STATUS" | jq -r '.spec.replicas')
    if [ "$REPLICAS" -ne 3 ]; then
        PASS=false
        REASONS+=("REASON: Deployment $DEPLOY_NAME has $REPLICAS replicas, expected 3")
    fi

    # 3. Check Resources (Requests and Limits)
    # Check if all containers and initContainers have the SAME resources
    RESOURCES_JSON=$(echo "$DEPLOY_STATUS" | jq -c '.spec.template.spec | (.containers[] , .initContainers[]) | .resources')
    
    FIRST_RESOURCE=$(echo "$RESOURCES_JSON" | head -n 1)
    
    if [ -z "$FIRST_RESOURCE" ] || [ "$FIRST_RESOURCE" == "{}" ]; then
        PASS=false
        REASONS+=("REASON: Resources are not defined for containers")
    else
        # Compare all other resources to the first one
        while read -r res; do
            if [ "$res" != "$FIRST_RESOURCE" ]; then
                PASS=false
                REASONS+=("REASON: Not all containers have the same resource requests and limits")
                break
            fi
        done <<< "$RESOURCES_JSON"
        
        # Check if requests and limits are defined and equal within each container
        REQUESTS_CPU=$(echo "$FIRST_RESOURCE" | jq -r '.requests.cpu')
        LIMITS_CPU=$(echo "$FIRST_RESOURCE" | jq -r '.limits.cpu')
        REQUESTS_MEM=$(echo "$FIRST_RESOURCE" | jq -r '.requests.memory')
        LIMITS_MEM=$(echo "$FIRST_RESOURCE" | jq -r '.limits.memory')
        
        if [ "$REQUESTS_CPU" != "$LIMITS_CPU" ] || [ "$REQUESTS_MEM" != "$LIMITS_MEM" ]; then
            PASS=false
            REASONS+=("REASON: Resource requests and limits are not exactly the same (Requests CPU: $REQUESTS_CPU, Limits CPU: $LIMITS_CPU)")
        fi
        
        if [ "$REQUESTS_CPU" == "null" ] || [ "$REQUESTS_MEM" == "null" ]; then
            PASS=false
            REASONS+=("REASON: Resource requests or limits are missing")
        fi
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: All containers (including init) have identical resource requests and limits, and replicas scaled to 3"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
