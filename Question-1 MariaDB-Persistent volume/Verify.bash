#!/bin/bash
# Verify.bash for Question-1 MariaDB-Persistent volume
set +e

NS="mariadb"
PVC_NAME="mariadb"
PV_NAME="mariadb-pv"
DEPLOY_NAME="mariadb"

PASS=true
REASONS=()

# 1. Check PVC
PVC_STATUS=$(kubectl get pvc $PVC_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: PVC $PVC_NAME not found in namespace $NS")
else
    ACCESS_MODES=$(echo "$PVC_STATUS" | jq -r '.spec.accessModes[0]')
    STORAGE=$(echo "$PVC_STATUS" | jq -r '.spec.resources.requests.storage')
    PHASE=$(echo "$PVC_STATUS" | jq -r '.status.phase')

    if [ "$ACCESS_MODES" != "ReadWriteOnce" ]; then
        PASS=false
        REASONS+=("REASON: PVC $PVC_NAME access mode is $ACCESS_MODES, expected ReadWriteOnce")
    fi
    if [ "$STORAGE" != "250Mi" ]; then
        PASS=false
        REASONS+=("REASON: PVC $PVC_NAME storage is $STORAGE, expected 250Mi")
    fi
    if [ "$PHASE" != "Bound" ]; then
        PASS=false
        REASONS+=("REASON: PVC $PVC_NAME is in phase $PHASE, expected Bound")
    fi
fi

# 2. Check PV binding
PV_STATUS=$(kubectl get pv $PV_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: PV $PV_NAME not found")
else
    BOUND_PVC=$(echo "$PV_STATUS" | jq -r '.spec.claimRef.name')
    BOUND_NS=$(echo "$PV_STATUS" | jq -r '.spec.claimRef.namespace')
    if [ "$BOUND_PVC" != "$PVC_NAME" ] || [ "$BOUND_NS" != "$NS" ]; then
        PASS=false
        REASONS+=("REASON: PV $PV_NAME is not bound to $NS/$PVC_NAME")
    fi
fi

# 3. Check Deployment
DEPLOY_STATUS=$(kubectl get deployment $DEPLOY_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Deployment $DEPLOY_NAME not found in namespace $NS")
else
    AVAILABLE=$(echo "$DEPLOY_STATUS" | jq -r '.status.availableReplicas')
    if [ "$AVAILABLE" == "null" ] || [ "$AVAILABLE" -lt 1 ]; then
        PASS=false
        REASONS+=("REASON: Deployment $DEPLOY_NAME has no available replicas")
    fi
    
    CLAIM_NAME=$(echo "$DEPLOY_STATUS" | jq -r '.spec.template.spec.volumes[] | select(.name=="mariadb-storage") | .persistentVolumeClaim.claimName')
    if [ "$CLAIM_NAME" != "$PVC_NAME" ]; then
        PASS=false
        REASONS+=("REASON: Deployment $DEPLOY_NAME does not use PVC $PVC_NAME")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: PVC created correctly and bound to PV, MariaDB deployment is running with persistent storage"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
