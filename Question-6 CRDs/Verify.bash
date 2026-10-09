#!/bin/bash
# Verify.bash for Question-6 CRDs
set +e

RESOURCES_FILE="/root/resources.yaml"
SUBJECT_FILE="/root/subject.yaml"

PASS=true
REASONS=()

# 1. Check resources.yaml
if [ ! -f "$RESOURCES_FILE" ]; then
    PASS=false
    REASONS+=("REASON: File $RESOURCES_FILE not found")
else
    if ! grep -q "cert-manager.io" "$RESOURCES_FILE"; then
        PASS=false
        REASONS+=("REASON: File $RESOURCES_FILE does not contain cert-manager CRDs")
    fi
fi

# 2. Check subject.yaml
if [ ! -f "$SUBJECT_FILE" ]; then
    PASS=false
    REASONS+=("REASON: File $SUBJECT_FILE not found")
else
    if ! grep -q "FIELDS" "$SUBJECT_FILE" || ! grep -q "subject" "$SUBJECT_FILE"; then
        PASS=false
        REASONS+=("REASON: File $SUBJECT_FILE does not contain documentation for certificate.spec.subject")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: CRDs list and field documentation correctly extracted to /root"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
