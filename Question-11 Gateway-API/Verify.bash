#!/bin/bash
# Verify.bash for Question-11 Gateway-API
set +e

GW_NAME="web-gateway"
ROUTE_NAME="web-route"
HOSTNAME="gateway.web.k8s.local"

PASS=true
REASONS=()

# 1. Check Gateway
GW_STATUS=$(kubectl get gateway $GW_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: Gateway $GW_NAME not found")
else
    CLASS=$(echo "$GW_STATUS" | jq -r '.spec.gatewayClassName')
    if [ "$CLASS" != "nginx-class" ]; then
        PASS=false
        REASONS+=("REASON: Gateway $GW_NAME uses class $CLASS, expected nginx-class")
    fi
    
    # Check Listener
    LISTENER=$(echo "$GW_STATUS" | jq '.spec.listeners[] | select(.name=="https" and .protocol=="HTTPS" and .port==443)')
    if [ -z "$LISTENER" ]; then
        PASS=false
        REASONS+=("REASON: HTTPS listener on port 443 not found in Gateway")
    else
        LH=$(echo "$LISTENER" | jq -r '.hostname')
        if [ "$LH" != "$HOSTNAME" ]; then
            PASS=false
            REASONS+=("REASON: Gateway hostname is $LH, expected $HOSTNAME")
        fi
        SECRET=$(echo "$LISTENER" | jq -r '.tls.certificateRefs[0].name')
        if [ "$SECRET" != "web-tls" ]; then
            PASS=false
            REASONS+=("REASON: Gateway TLS secret is $SECRET, expected web-tls")
        fi
    fi
fi

# 2. Check HTTPRoute
ROUTE_STATUS=$(kubectl get httproute $ROUTE_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: HTTPRoute $ROUTE_NAME not found")
else
    RH=$(echo "$ROUTE_STATUS" | jq -r '.spec.hostnames[0]')
    if [ "$RH" != "$HOSTNAME" ]; then
        PASS=false
        REASONS+=("REASON: HTTPRoute hostname is $RH, expected $HOSTNAME")
    fi
    
    PARENT=$(echo "$ROUTE_STATUS" | jq -r '.spec.parentRefs[0].name')
    if [ "$PARENT" != "$GW_NAME" ]; then
        PASS=false
        REASONS+=("REASON: HTTPRoute parentRef is $PARENT, expected $GW_NAME")
    fi
    
    BACKEND=$(echo "$ROUTE_STATUS" | jq -r '.spec.rules[0].backendRefs[0].name')
    if [ "$BACKEND" != "web-service" ]; then
        PASS=false
        REASONS+=("REASON: HTTPRoute backendRef is $BACKEND, expected web-service")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Gateway API resources (Gateway and HTTPRoute) correctly configured for TLS and routing"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
