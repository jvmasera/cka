#!/bin/bash
set -euo pipefail

# Colors (disabled automatically when not attached to a terminal).
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'
  CYAN='\033[36m'; YELLOW='\033[33m'; GREEN='\033[32m'; RED='\033[31m'; BLUE='\033[34m'
else
  BOLD=''; RESET=''; CYAN=''; YELLOW=''; GREEN=''; RED=''; BLUE=''
fi

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: scripts/run-question.sh <number|Question-XX Topic>${RESET}" >&2
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
  echo -e "${RED}Question directory '$QUESTION_DIR' not found${RESET}" >&2
  exit 1
fi

SETUP="$QUESTION_DIR/LabSetUp.bash"
QUESTION_TEXT="$QUESTION_DIR/Questions.bash"
SOLUTION="$QUESTION_DIR/SolutionNotes.bash"

[[ -f "$SETUP" ]] || { echo "Missing $SETUP" >&2; exit 1; }
[[ -f "$QUESTION_TEXT" ]] || { echo "Missing $QUESTION_TEXT" >&2; exit 1; }

chmod +x "$SETUP"

# When starting a brand new test session (timer not running yet) outside of
# tmux, automatically open a tmux session with 2 panes split horizontally:
# the top one running the fixed on-screen timer (show-timer.sh) and the
# bottom one running this very question (so the whole exam experience -
# timer + question - is ready in a single tmux session). If we're already
# inside tmux, or tmux isn't available, just proceed normally below.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
if [[ -z "${TMUX:-}" && ! -f "$TIMER_FILE" ]] && command -v tmux >/dev/null 2>&1; then
  SESSION_NAME="cka-exam"
  SCRIPT_PATH="$REPO_ROOT/scripts/run-question.sh"
  SHOW_TIMER="$REPO_ROOT/scripts/show-timer.sh"
  chmod +x "$SCRIPT_PATH" "$SHOW_TIMER" 2>/dev/null || true

  ARGS_Q=""
  for a in "$@"; do
    ARGS_Q+=" $(printf '%q' "$a")"
  done

  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  tmux new-session -d -s "$SESSION_NAME" -c "$REPO_ROOT" "$SHOW_TIMER"
  tmux split-window -v -t "$SESSION_NAME" -c "$REPO_ROOT" "$SCRIPT_PATH$ARGS_Q; exec bash"
  # Keep the timer pane small (it only needs a few lines) and give the
  # question pane the rest of the screen.
  tmux resize-pane -t "$SESSION_NAME:0.0" -y 3
  # Enable mouse mode and a bigger scrollback buffer so scrolling works
  # inside each pane (e.g. while editing files with vim).
  tmux set-option -t "$SESSION_NAME" -g mouse on
  tmux set-option -t "$SESSION_NAME" -g history-limit 50000
  tmux select-pane -t "$SESSION_NAME:0.1"
  exec tmux attach-session -t "$SESSION_NAME"
fi

reset_cluster() {
  echo -e "${CYAN}==> Resetting cluster to clean state...${RESET}"
  if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${YELLOW}kubectl not found, skipping cluster reset.${RESET}"
    return 0
  fi

  # Check if cluster is reachable
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${YELLOW}Cluster is not reachable, skipping cluster reset.${RESET}"
    return 0
  fi

  # 1. Namespaces created across different questions
  LAB_NAMESPACES=("mariadb" "echo-sound" "frontend" "backend" "relative" "nginx-static" "argocd" "autoscale" "cert-manager" "priority" "tigera-operator")
  for ns in "${LAB_NAMESPACES[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      echo -e "${YELLOW}Deleting namespace: $ns${RESET}"
      kubectl delete ns "$ns" --timeout=60s --ignore-not-found || true
    fi
  done

  # 2. Resources commonly created in the default namespace
  echo -e "${CYAN}Cleaning up resources in default namespace...${RESET}"
  kubectl delete deploy wordpress web-deployment nginx nginx-static mariadb --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete svc web-service nginx nginx-service mariadb --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete ingress web nginx-ingress --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete secret web-tls --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete pod nginx test-pod --namespace default --ignore-not-found 2>/dev/null || true
  kubectl delete pvc mariadb --namespace default --ignore-not-found 2>/dev/null || true

  # 3. Cluster-scoped resources created across questions
  echo -e "${CYAN}Cleaning up cluster-scoped resources...${RESET}"
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
    echo -e "${CYAN}Cleaning up sandbox folder...${RESET}"
    find "$REPO_ROOT/sandbox" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
  else
    mkdir -p "$REPO_ROOT/sandbox"
  fi

  echo -e "${GREEN}==> Cluster reset complete.${RESET}"
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

echo -e "${CYAN}==> Running lab setup for ${BOLD}$QUESTION_DIR${RESET}"
"$SETUP"

echo
echo -e "${BOLD}${BLUE}==> Question${RESET}"
cat "$QUESTION_TEXT"

echo
if [[ -f "$SOLUTION" ]]; then
  echo -e "${YELLOW}Hints: see $SOLUTION${RESET}"
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
  echo -e "${BOLD}${GREEN}==> Timer started! You have 2h (CKA exam duration) to finish the session.${RESET}"

  # Try to automatically open the fixed on-screen timer in a new tmux pane,
  # so you don't need to run show-timer.sh manually. If we already run inside
  # a tmux window with 2+ panes, assume the timer pane was already set up
  # (e.g. by the auto-launched session above) and skip creating another one.
  SHOW_TIMER="$REPO_ROOT/scripts/show-timer.sh"
  chmod +x "$SHOW_TIMER" 2>/dev/null || true
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    PANE_COUNT="$(tmux list-panes 2>/dev/null | wc -l)"
    if [[ "${PANE_COUNT:-1}" -le 1 ]]; then
      tmux split-window -v -b "$SHOW_TIMER" 2>/dev/null \
        && tmux resize-pane -U -y 3 2>/dev/null \
        && echo -e "${GREEN}==> Timer pane opened automatically (tmux split-window).${RESET}" \
        || echo -e "${YELLOW}==> Could not auto-open the timer pane. Run manually: $SHOW_TIMER${RESET}"
      tmux set-option -g mouse on 2>/dev/null || true
      tmux set-option -g history-limit 50000 2>/dev/null || true
    fi
  else
    echo -e "${YELLOW}==> To keep the timer fixed on screen, run in another terminal/pane: $SHOW_TIMER${RESET}"
  fi
fi
