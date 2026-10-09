#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/run-question.sh \"Question-XX Topic\"" >&2
  exit 1
fi

QUESTION_DIR="$*"
if [[ ! -d "$QUESTION_DIR" ]]; then
  echo "Question directory '$QUESTION_DIR' not found" >&2
  exit 1
fi

SETUP="$QUESTION_DIR/LabSetUp.bash"
QUESTION_TEXT="$QUESTION_DIR/Questions.bash"
SOLUTION="$QUESTION_DIR/SolutionNotes.bash"

[[ -f "$SETUP" ]] || { echo "Missing $SETUP" >&2; exit 1; }
[[ -f "$QUESTION_TEXT" ]] || { echo "Missing $QUESTION_TEXT" >&2; exit 1; }

chmod +x "$SETUP"

reset_cluster() {
  echo "==> Resetting cluster to clean state..."
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found, skipping cluster reset."
    return 0
  fi

  # Check if cluster is reachable
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Cluster is not reachable, skipping cluster reset."
    return 0
  fi

  # 1. Namespaces created across different questions
  LAB_NAMESPACES=("mariadb" "echo-sound" "frontend" "backend" "relative" "nginx-static" "argocd" "autoscale" "cert-manager" "priority" "tigera-operator")
  for ns in "${LAB_NAMESPACES[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      echo "Deleting namespace: $ns"
      kubectl delete ns "$ns" --timeout=60s --ignore-not-found || true
    fi
  done

  # 2. Resources commonly created in the default namespace
  echo "Cleaning up resources in default namespace..."
  kubectl delete deploy wordpress web-deployment nginx nginx-static mariadb --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete svc web-service nginx nginx-service mariadb --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete ingress web nginx-ingress --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete secret web-tls --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete pod nginx test-pod --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete pvc mariadb --namespace default --ignore-not-found 2>/dev/null || true

  # 3. Cluster-scoped resources created across questions
  echo "Cleaning up cluster-scoped resources..."
  kubectl delete pv mariadb-pv --ignore-not-found 2>/dev/null || true
  kubectl delete priorityclass user-critical high-priority --ignore-not-found 2>/dev/null || true
  if kubectl api-resources | grep -qi gatewayclass; then
    kubectl delete gatewayclass nginx-class --ignore-not-found 2>/dev/null || true
  fi

  # Remove taints on nodes if applied in Question-10
  kubectl taint nodes --all PERMISSION- 2>/dev/null || true

  # 4. StorageClass reset if modified in Question-14
  if kubectl get sc local-storage >/dev/null 2>&1; then
    kubectl delete sc local-storage --ignore-not-found || true
    if kubectl get sc local-path >/dev/null 2>&1; then
      kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
    fi
  fi

  # 5. Clean up temporary files in root / home
  rm -f ~/mariadb-deploy.yaml ~/pvc.yaml ~/pod.yaml ~/hpa.yaml /root/mariadb-deploy.yaml /root/cri-dockerd.deb 2>/dev/null || true

  echo "==> Cluster reset complete."
}

reset_cluster

echo "==> Running lab setup for $QUESTION_DIR"
"$SETUP"

echo
echo "==> Question"
cat "$QUESTION_TEXT"

echo
if [[ -f "$SOLUTION" ]]; then
  echo "Hints: see $SOLUTION"
fi
