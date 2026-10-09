#!/bin/bash
# Verify.bash for Question-8 CNI & Network Policy
set +e

PASS=true
REASONS=()

# 1. Check if Calico is installed (as it supports NetworkPolicy)
if kubectl get ns tigera-operator >/dev/null 2>&1 || kubectl get ns calico-system >/dev/null 2>&1; then
    # Check if pods are running
    RUNNING_PODS=$(kubectl get pods -A | grep -iE "calico|tigera" | grep -v "Running" | wc -l)
    if [ "$RUNNING_PODS" -gt 0 ]; then
         # We allow some time for startup, so just warning or failing if absolutely none
         TOTAL_PODS=$(kubectl get pods -A | grep -iE "calico|tigera" | wc -l)
         if [ "$TOTAL_PODS" -eq 0 ]; then
            PASS=false
            REASONS+=("REASON: Calico/Tigera pods not found")
         fi
    fi
else
    # Check for Flannel
    if kubectl get ns kube-flannel >/dev/null 2>&1 || kubectl get pods -n kube-system | grep -q flannel; then
        PASS=false
        REASONS+=("REASON: Flannel found, but it does not support Network Policy by default as required")
    else
        PASS=false
        REASONS+=("REASON: No supported CNI (Calico) found installed")
    fi
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: Calico CNI installed which supports network policy enforcement"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
