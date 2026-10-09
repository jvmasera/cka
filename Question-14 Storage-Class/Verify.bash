#!/bin/bash
# Verify.bash for Question-14 Storage-Class
set +e

SC_NAME="local-storage"

PASS=true
REASONS=()

# 1. Check StorageClass exists
SC_STATUS=$(kubectl get sc $SC_NAME -o json 2>/dev/null)
if [ $? -ne 0 ]; then
    PASS=false
    REASONS+=("REASON: StorageClass $SC_NAME not found")
else
    # 2. Check provisioner and binding mode
    PROV=$(echo "$SC_STATUS" | jq -r '.provisioner')
    MODE=$(echo "$SC_STATUS" | jq -r '.volumeBindingMode')
    if [ "$PROV" != "rancher.io/local-path" ]; then
        PASS=false
        REASONS+=("REASON: StorageClass provisioner is $PROV, expected rancher.io/local-path")
    fi
    if [ "$MODE" != "WaitForFirstConsumer" ]; then
        PASS=false
        REASONS+=("REASON: StorageClass volumeBindingMode is $MODE, expected WaitForFirstConsumer")
    fi
    
    # 3. Check if it is the default
    IS_DEFAULT=$(echo "$SC_STATUS" | jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"]')
    if [ "$IS_DEFAULT" != "true" ]; then
        PASS=false
        REASONS+=("REASON: StorageClass $SC_NAME is not the default class")
    fi
fi

# 4. Ensure no other default SC
DEFAULT_COUNT=$(kubectl get sc -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' | wc -l)
if [ "$DEFAULT_COUNT" -gt 1 ]; then
    PASS=false
    REASONS+=("REASON: There are $DEFAULT_COUNT default storage classes, expected only 1")
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: StorageClass $SC_NAME correctly created and set as the sole default class"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
