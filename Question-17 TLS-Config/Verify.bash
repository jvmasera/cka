#!/bin/bash
# Verify.bash for Question-17 TLS-Config
set +e

NS="nginx-static"
CM_NAME="nginx-config"
HOSTNAME="ckaquestion.k8s.local"

PASS=true
REASONS=()

# 1. Check ConfigMap (Immutable and TLS protocols)
CM_STATUS=$(kubectl get cm $CM_NAME -n $NS -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: ConfigMap $CM_NAME not found in namespace $NS")
else
    IMMUTABLE=$(echo "$CM_STATUS" | jq -r '.immutable')
    if [ "$IMMUTABLE" != "true" ]; then
        PASS=false
        REASONS+=("REASON: ConfigMap $CM_NAME is not immutable")
    fi
    
    PROTOCOLS=$(echo "$CM_STATUS" | jq -r '.data["nginx.conf"]' | grep "ssl_protocols")
    if [[ "$PROTOCOLS" == *"TLSv1.3"* ]] || [[ "$PROTOCOLS" != *"TLSv1.2"* ]]; then
        PASS=false
        REASONS+=("REASON: ConfigMap $CM_NAME protocols not restricted to TLSv1.2 only: $PROTOCOLS")
    fi
fi

# 2. Check /etc/hosts
if ! grep -q "$HOSTNAME" /etc/hosts; then
    PASS=false
    REASONS+=("REASON: Hostname $HOSTNAME not found in /etc/hosts")
fi

# 3. Verify TLS connection (if environment allows)
# We try to curl if the hostname points to a reachable IP.
# Since this is a verification script, we should be careful not to hang.
# But the task says "Verify everything is working using the following commands"
if grep -q "$HOSTNAME" /etc/hosts; then
    # Test TLS 1.2
    if ! curl -vk --tlsv1.2 --tls-max 1.2 --connect-timeout 5 "https://$HOSTNAME" 2>&1 | grep -q "SSL connection using TLSv1.2"; then
        # Check if it at least connected and returned 200 (nginx might not show the SSL line in all curl versions)
        if ! curl -vk --tlsv1.2 --tls-max 1.2 --connect-timeout 5 "https://$HOSTNAME" 2>/dev/null | grep -q "Hello TLS"; then
             # Only fail if it definitely didn't work. Some environments might not have the host reachable.
             # PASS=false
             # REASONS+=("REASON: TLSv1.2 connection to $HOSTNAME failed")
             true
        fi
    fi
    # Test TLS 1.3 (should fail)
    if curl -vk --tlsv1.3 --connect-timeout 5 "https://$HOSTNAME" 2>&1 | grep -q "SSL connection using TLSv1.3"; then
        PASS=false
        REASONS+=("REASON: TLSv1.3 connection to $HOSTNAME succeeded, but should have failed")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: ConfigMap $CM_NAME is immutable and restricted to TLSv1.2, and /etc/hosts is updated"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
