#!/bin/bash
# Verify.bash for Question-16 NodePort
set +e

NS="relative"
DEPLOY_NAME="nodeport-deployment"
SVC_NAME="nodeport-service"

PASS=true
REASONS=()

# 1. Check Deployment Container Port
DEPLOY_STATUS=$(kubectl get deployment $DEPLOY_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Deployment $DEPLOY_NAME not found in namespace $NS")
else
    PORT_SPEC=$(echo "$DEPLOY_STATUS" | jq '.spec.template.spec.containers[0].ports[] | select(.containerPort==80 and .protocol=="TCP")')
    if [ -z "$PORT_SPEC" ]; then
        PASS=false
        REASONS+=("REASON: Deployment container port 80/TCP not correctly configured")
    fi
fi

# 2. Check Service
SVC_STATUS=$(kubectl get svc $SVC_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Service $SVC_NAME not found in namespace $NS")
else
    TYPE=$(echo "$SVC_STATUS" | jq -r '.spec.type')
    PORT=$(echo "$SVC_STATUS" | jq -r '.spec.ports[0].port')
    TPORT=$(echo "$SVC_STATUS" | jq -r '.spec.ports[0].targetPort')
    NPORT=$(echo "$SVC_STATUS" | jq -r '.spec.ports[0].nodePort')
    
    if [ "$TYPE" != "NodePort" ]; then
        PASS=false
        REASONS+=("REASON: Service type is $TYPE, expected NodePort")
    fi
    if [ "$PORT" -ne 80 ]; then
        PASS=false
        REASONS+=("REASON: Service port is $PORT, expected 80")
    fi
    if [ "$TPORT" -ne 80 ]; then
        PASS=false
        REASONS+=("REASON: Service targetPort is $TPORT, expected 80")
    fi
    if [ "$NPORT" -ne 30080 ]; then
        PASS=false
        REASONS+=("REASON: Service nodePort is $NPORT, expected 30080")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Deployment correctly updated and NodePort service created on port 30080"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
