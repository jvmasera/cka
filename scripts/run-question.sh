#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/run-question.sh <number|Question-XX Topic>" >&2
  exit 1
fi

INPUT="$*"
QUESTION_DIR=""

if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  FOUND_DIRS=()
  for dir in Question-"$INPUT"*; do
    if [[ -d "$dir" && "$dir" =~ ^Question-${INPUT}([[:space:]]|-|$) ]]; then
      FOUND_DIRS+=("$dir")
    fi
  done

  if [[ ${#FOUND_DIRS[@]} -eq 1 ]]; then
    QUESTION_DIR="${FOUND_DIRS[0]}"
  elif [[ ${#FOUND_DIRS[@]} -gt 1 ]]; then
    echo "Multiple question directories found for '$INPUT': ${FOUND_DIRS[*]}" >&2
    exit 1
  fi
fi

if [[ -z "$QUESTION_DIR" ]]; then
  QUESTION_DIR="$INPUT"
fi

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

  # 5. Clean up temporary files in root / home and sandbox
  rm -f ~/mariadb-deploy.yaml ~/pvc.yaml ~/pod.yaml ~/hpa.yaml /root/mariadb-deploy.yaml /root/cri-dockerd.deb 2>/dev/null || true
  
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -d "$REPO_ROOT/sandbox" ]]; then
    echo "Cleaning up sandbox folder..."
    find "$REPO_ROOT/sandbox" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
  else
    mkdir -p "$REPO_ROOT/sandbox"
  fi

  echo "==> Cluster reset complete."
}

# Reset the test session log whenever an explicit "new session" is requested,
# i.e. when the user sets NEW_TEST_SESSION=1 before starting the first
# question of a fresh practice run. Otherwise questions accumulate into the
# same session log so finish-test.sh can grade all of them together.
if [[ "${NEW_TEST_SESSION:-0}" == "1" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  rm -f "$REPO_ROOT/scripts/.session_log"
  rm -f "$REPO_ROOT/scripts/.session_start"
fi

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

# Log this question as attempted in the current test session, so finish-test.sh
# can grade it later. Avoid duplicate entries for the same question.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$REPO_ROOT/scripts/.session_log"
touch "$LOG_FILE"
if ! grep -qxF "$QUESTION_DIR" "$LOG_FILE"; then
  echo "$QUESTION_DIR" >> "$LOG_FILE"
fi

# Start the exam timer on the very first question of a session (real CKA
# exam duration is 2 hours). The timestamp is stored so finish-test.sh can
# compute the elapsed time when the session is graded.
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
if [[ ! -f "$TIMER_FILE" ]]; then
  date +%s > "$TIMER_FILE"
  echo
  echo "==> Timer started! You have 2h (CKA exam duration) to finish the session."

  # Try to automatically open the fixed on-screen timer in a new tmux pane,
  # so you don't need to run show-timer.sh manually. Only works when already
  # inside a tmux session; otherwise just hint the manual command.
  SHOW_TIMER="$REPO_ROOT/scripts/show-timer.sh"
  chmod +x "$SHOW_TIMER" 2>/dev/null || true
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux split-window -h "$SHOW_TIMER" 2>/dev/null \
      && echo "==> Timer window opened automatically (tmux split-window)." \
      || echo "==> Could not auto-open the timer window. Run manually: $SHOW_TIMER"
  else
    echo "==> To keep the timer fixed on screen, run in another terminal/pane: $SHOW_TIMER"
  fi
fi
