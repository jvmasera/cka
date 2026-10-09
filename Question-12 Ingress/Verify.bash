#!/bin/bash
# Verify.bash for Question-12 Ingress
set +e

NS="echo-sound"
SVC_NAME="echo-service"
ING_NAME="echo"

PASS=true
REASONS=()

# 1. Check Service
SVC_STATUS=$(kubectl get svc $SVC_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Service $SVC_NAME not found in namespace $NS")
else
    TYPE=$(echo "$SVC_STATUS" | jq -r '.spec.type')
    PORT=$(echo "$SVC_STATUS" | jq -r '.spec.ports[0].port')
    if [ "$TYPE" != "NodePort" ]; then
        PASS=false
        REASONS+=("REASON: Service type is $TYPE, expected NodePort")
    fi
    if [ "$PORT" -ne 8080 ]; then
        PASS=false
        REASONS+=("REASON: Service port is $PORT, expected 8080")
    fi
fi

# 2. Check Ingress
ING_STATUS=$(kubectl get ingress $ING_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Ingress $ING_NAME not found in namespace $NS")
else
    HOST=$(echo "$ING_STATUS" | jq -r '.spec.rules[0].host')
    ING_PATH=$(echo "$ING_STATUS" | jq -r '.spec.rules[0].http.paths[0].path')
    BACKEND_SVC=$(echo "$ING_STATUS" | jq -r '.spec.rules[0].http.paths[0].backend.service.name')
    BACKEND_PORT=$(echo "$ING_STATUS" | jq -r '.spec.rules[0].http.paths[0].backend.service.port.number')
    
    if [ "$HOST" != "example.org" ]; then
        PASS=false
        REASONS+=("REASON: Ingress host is $HOST, expected example.org")
    fi
    if [ "$ING_PATH" != "/echo" ]; then
        PASS=false
        REASONS+=("REASON: Ingress path is $ING_PATH, expected /echo")
    fi
    if [ "$BACKEND_SVC" != "$SVC_NAME" ]; then
        PASS=false
        REASONS+=("REASON: Ingress backend service is $BACKEND_SVC, expected $SVC_NAME")
    fi
    if [ "$BACKEND_PORT" -ne 8080 ]; then
        PASS=false
        REASONS+=("REASON: Ingress backend port is $BACKEND_PORT, expected 8080")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Service $SVC_NAME and Ingress $ING_NAME correctly configured in namespace $NS"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
