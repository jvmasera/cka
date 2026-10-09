#!/bin/bash
# Verify.bash for Question-9 Cri-Dockerd
set +e

PASS=true
REASONS=()

# 1. Check Service
if ! systemctl is-active --quiet cri-docker.service; then
    PASS=false
    REASONS+=("REASON: cri-docker.service is not active")
fi

# 2. Check Sysctl values
declare -A EXPECTED_SYSCTL=(
    ["net.bridge.bridge-nf-call-iptables"]="1"
    ["net.ipv6.conf.all.forwarding"]="1"
    ["net.ipv4.ip_forward"]="1"
    ["net.netfilter.nf_conntrack_max"]="131072"
)

for key in "${!EXPECTED_SYSCTL[@]}"; do
    VAL=$(sysctl -n "$key" 2>/dev/null)
    if [ "$VAL" != "${EXPECTED_SYSCTL[$key]}" ]; then
        PASS=false
        REASONS+=("REASON: sysctl $key is $VAL, expected ${EXPECTED_SYSCTL[$key]}")
    fi
done

# 3. Check persistent config
if [ ! -f /etc/sysctl.d/kube.conf ]; then
    PASS=false
    REASONS+=("REASON: File /etc/sysctl.d/kube.conf not found")
else
    for key in "${!EXPECTED_SYSCTL[@]}"; do
        if ! grep -q "$key=${EXPECTED_SYSCTL[$key]}" /etc/sysctl.d/kube.conf; then
            PASS=false
            REASONS+=("REASON: $key is not correctly set in /etc/sysctl.d/kube.conf")
        fi
    done
fi

if [ "$PASS" = true ]; then
    echo "RESULT:PASS"
    echo "REASON: cri-dockerd service is active and sysctl parameters are correctly configured"
else
    echo "RESULT:FAIL"
    for reason in "${REASONS[@]}"; do
        echo "$reason"
    done
fi
exit 0
