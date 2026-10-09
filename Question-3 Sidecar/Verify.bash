#!/bin/bash
# Verify.bash for Question-3 Sidecar
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
    # 2. Check for 2 containers
    CONTAINER_COUNT=$(echo "$DEPLOY_STATUS" | jq '.spec.template.spec.containers | length')
    if [ "$CONTAINER_COUNT" -lt 2 ]; then
        PASS=false
        REASONS+=("REASON: Deployment $DEPLOY_NAME has only $CONTAINER_COUNT container(s), expected at least 2")
    fi

    # 3. Check for sidecar container
    SIDECAR=$(echo "$DEPLOY_STATUS" | jq '.spec.template.spec.containers[] | select(.name=="sidecar")')
    if [ -z "$SIDECAR" ]; then
        PASS=false
        REASONS+=("REASON: Sidecar container named 'sidecar' not found")
    else
        IMAGE=$(echo "$SIDECAR" | jq -r '.image')
        COMMAND=$(echo "$SIDECAR" | jq -r '.command | join(" ")')
        if [ "$IMAGE" != "busybox:stable" ]; then
            PASS=false
            REASONS+=("REASON: Sidecar image is $IMAGE, expected busybox:stable")
        fi
        if [[ "$COMMAND" != *"/bin/sh -c tail -f /var/log/wordpress.log"* ]]; then
            PASS=false
            REASONS+=("REASON: Sidecar command is incorrect: $COMMAND")
        fi
        
        # Check volume mount
        MOUNT=$(echo "$SIDECAR" | jq -r '.volumeMounts[] | select(.mountPath=="/var/log") | .name')
        if [ -z "$MOUNT" ]; then
            PASS=false
            REASONS+=("REASON: Sidecar does not mount /var/log")
        fi
    fi

    # 4. Check shared volume
    VOLUMES=$(echo "$DEPLOY_STATUS" | jq -r '.spec.template.spec.volumes[] | select(.emptyDir != null) | .name')
    if [ -z "$VOLUMES" ]; then
        PASS=false
        REASONS+=("REASON: Shared emptyDir volume not found in deployment")
    fi
    
    # Check if main container also mounts it
    MAIN_MOUNT=$(echo "$DEPLOY_STATUS" | jq -r '.spec.template.spec.containers[] | select(.name!="sidecar") | .volumeMounts[] | select(.mountPath=="/var/log") | .name')
    if [ -z "$MAIN_MOUNT" ]; then
        PASS=false
        REASONS+=("REASON: Main container does not mount /var/log")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Sidecar container correctly added with shared volume to wordpress deployment"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
