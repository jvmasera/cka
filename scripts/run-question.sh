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

# Always operate from the repo root, regardless of the directory the user
# was in when invoking this script (e.g. via the global "cka" command from
# inside "sandbox/" or any other folder), so question directories, the
# sandbox cleanup and all other relative paths resolve correctly.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

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
# tmux, automatically open a tmux session with 2 panes split horizontally
# (top/bottom), like before. The difference is that the top pane is now
# itself split vertically (side by side) into: the question's descriptive
# text on the left, and the fixed on-screen timer (show-timer.sh) on the
# right with a smaller width. The bottom pane keeps running this very
# question (the interactive shell). If we're already inside tmux, or tmux
# isn't available, just proceed normally below.
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

  SHOW_QUESTION_CMD="cat $(printf '%q' "$REPO_ROOT/$QUESTION_TEXT"); echo; echo 'Press Ctrl+C to close.'; exec bash"

  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  # Top-left pane: static question text.
  tmux new-session -d -s "$SESSION_NAME" -c "$REPO_ROOT" "$SHOW_QUESTION_CMD"
  TOP_LEFT_PANE="$(tmux display-message -p -t "$SESSION_NAME" '#{pane_id}')"
  # Bottom pane: the actual interactive shell running the question.
  BOTTOM_PANE="$(tmux split-window -v -t "$SESSION_NAME" -c "$REPO_ROOT" -P -F '#{pane_id}' "$SCRIPT_PATH$ARGS_Q; exec bash")"
  # Top-right pane: the fixed on-screen timer, narrower than the question pane.
  TIMER_PANE="$(tmux split-window -h -t "$TOP_LEFT_PANE" -c "$REPO_ROOT" -P -F '#{pane_id}' "$SHOW_TIMER")"
  tmux resize-pane -t "$TOP_LEFT_PANE" -y 12
  tmux resize-pane -t "$TIMER_PANE" -x 30
  # Enable mouse mode and a bigger scrollback buffer so scrolling works
  # inside each pane (e.g. while editing files with vim).
  tmux set-option -t "$SESSION_NAME" -g mouse on
  tmux set-option -t "$SESSION_NAME" -g history-limit 50000
  tmux select-pane -t "$BOTTOM_PANE"
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

  if [[ -d "$REPO_ROOT/sandbox" ]]; then
    echo -e "${CYAN}Cleaning up sandbox folder...${RESET}"
    find "$REPO_ROOT/sandbox" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
  else
    mkdir -p "$REPO_ROOT/sandbox"
  fi

  echo -e "${GREEN}==> Cluster reset complete.${RESET}"
}

LOG_FILE="$REPO_ROOT/scripts/.session_log"
RESULTS_FILE="$REPO_ROOT/scripts/.session_results"
PAUSE_FILE="$REPO_ROOT/scripts/.session_pause"
PAUSED_TOTAL_FILE="$REPO_ROOT/scripts/.session_paused_total"
RESUME_FILE="$REPO_ROOT/scripts/.session_resume"

# Reset the test session log whenever an explicit "new session" is requested,
# i.e. when the user sets NEW_TEST_SESSION=1 before starting the first
# question of a fresh practice run. Otherwise questions accumulate into the
# same session log so finish-test.sh can grade all of them together.
if [[ "${NEW_TEST_SESSION:-0}" == "1" ]]; then
  rm -f "$LOG_FILE"
  rm -f "$RESULTS_FILE"
  rm -f "$REPO_ROOT/scripts/.session_start"
  rm -f "$PAUSE_FILE" "$PAUSED_TOTAL_FILE" "$RESUME_FILE"
fi

# Before wiping the cluster below, cache the verification result of the
# question you were just working on (the last one logged). This way,
# finish-test.sh can later grade it using this cached result instead of
# re-checking the live cluster, which would no longer have those objects
# once a new question resets everything. Cache once per question (skip if
# already cached, e.g. if you re-run the same question again).
touch "$LOG_FILE"
if [[ -s "$LOG_FILE" ]]; then
  PREV_QUESTION="$(tail -n1 "$LOG_FILE")"
  if [[ -n "$PREV_QUESTION" && "$PREV_QUESTION" != "$QUESTION_DIR" && -d "$PREV_QUESTION" ]]; then
    PREV_VERIFY="$REPO_ROOT/$PREV_QUESTION/Verify.bash"
    if [[ -f "$PREV_VERIFY" ]] && ! grep -qxF "@@QUESTION@@$PREV_QUESTION" "$RESULTS_FILE" 2>/dev/null; then
      echo -e "${CYAN}==> Caching verification result for previous question ($PREV_QUESTION) before reset...${RESET}"
      chmod +x "$PREV_VERIFY" 2>/dev/null || true
      PREV_OUTPUT="$(bash "$PREV_VERIFY" 2>&1)"
      {
        echo "@@QUESTION@@$PREV_QUESTION"
        echo "$PREV_OUTPUT"
        echo "@@ENDQUESTION@@"
      } >> "$RESULTS_FILE"
    fi
  fi
fi

# Pause the exam timer while the cluster resets and the question's
# environment is initialized, since this setup time shouldn't count against
# the candidate. Only do this if the timer is already running (i.e. this is
# not the very first question, whose setup happens before the timer starts).
if [[ -f "$TIMER_FILE" ]]; then
  echo -e "${YELLOW}==> Pausing exam timer while the environment initializes (cluster reset + setup)...${RESET}"
  date +%s > "$PAUSE_FILE"
  rm -f "$RESUME_FILE"
fi

reset_cluster

echo -e "${CYAN}==> Running lab setup for ${BOLD}$QUESTION_DIR${RESET}"
"$SETUP"

# Resume the exam timer now that the environment is ready, accumulating the
# time spent paused so it keeps being excluded from the elapsed time shown
# by show-timer.sh / finish-test.sh.
if [[ -f "$PAUSE_FILE" ]]; then
  PAUSE_START="$(cat "$PAUSE_FILE")"
  PAUSE_END="$(date +%s)"
  PAUSE_DURATION=$((PAUSE_END - PAUSE_START))
  [[ "$PAUSE_DURATION" -lt 0 ]] && PAUSE_DURATION=0
  PREV_PAUSED_TOTAL=0
  [[ -f "$PAUSED_TOTAL_FILE" ]] && PREV_PAUSED_TOTAL="$(cat "$PAUSED_TOTAL_FILE")"
  echo $((PREV_PAUSED_TOTAL + PAUSE_DURATION)) > "$PAUSED_TOTAL_FILE"
  rm -f "$PAUSE_FILE"
  date +%s > "$RESUME_FILE"
  echo -e "${GREEN}==> Timer resumed! Environment is ready (paused for ${PAUSE_DURATION}s while initializing).${RESET}"
fi

echo
echo -e "${BOLD}${BLUE}==> Question${RESET}"
cat "$QUESTION_TEXT"

echo
if [[ -f "$SOLUTION" ]]; then
  echo -e "${YELLOW}Hints: see $SOLUTION${RESET}"
fi

# Log this question as attempted in the current test session, so finish-test.sh
# can grade it later. Avoid duplicate entries for the same question. Also
# drop any stale cached verification result for this question (e.g. if you
# are retrying it), so it gets freshly re-verified (live or cached) next time.
touch "$LOG_FILE"
if ! grep -qxF "$QUESTION_DIR" "$LOG_FILE"; then
  echo "$QUESTION_DIR" >> "$LOG_FILE"
fi
if [[ -f "$RESULTS_FILE" ]] && grep -qxF "@@QUESTION@@$QUESTION_DIR" "$RESULTS_FILE"; then
  awk -v q="@@QUESTION@@$QUESTION_DIR" '
    $0 == q { skip=1 }
    skip && $0 == "@@ENDQUESTION@@" { skip=0; next }
    !skip { print }
  ' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
fi

# Start the exam timer on the very first question of a session (real CKA
# exam duration is 2 hours). The timestamp is stored so finish-test.sh can
# compute the elapsed time when the session is graded.
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
if [[ ! -f "$TIMER_FILE" ]]; then
  date +%s > "$TIMER_FILE"
  echo
  echo -e "${BOLD}${GREEN}==> Timer started! You have 2h (CKA exam duration) to finish the session.${RESET}"

  # Try to automatically open a top row with the question text (left) and
  # the fixed on-screen timer (right, narrower), above the current pane,
  # so you don't need to run show-timer.sh manually. If we already run
  # inside a tmux window with 2+ panes, assume this was already set up
  # (e.g. by the auto-launched session above) and skip creating another one.
  SHOW_TIMER="$REPO_ROOT/scripts/show-timer.sh"
  chmod +x "$SHOW_TIMER" 2>/dev/null || true
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    PANE_COUNT="$(tmux list-panes 2>/dev/null | wc -l)"
    if [[ "${PANE_COUNT:-1}" -le 1 ]]; then
      SHOW_QUESTION_CMD="cat $(printf '%q' "$REPO_ROOT/$QUESTION_TEXT"); echo; echo 'Press Ctrl+C to close.'; exec bash"
      TOP_LEFT_PANE="$(tmux split-window -v -b -P -F '#{pane_id}' "$SHOW_QUESTION_CMD" 2>/dev/null)"
      if [[ -n "$TOP_LEFT_PANE" ]]; then
        tmux resize-pane -t "$TOP_LEFT_PANE" -y 12 2>/dev/null
        TIMER_PANE="$(tmux split-window -h -t "$TOP_LEFT_PANE" -P -F '#{pane_id}' "$SHOW_TIMER" 2>/dev/null)"
        tmux resize-pane -t "$TIMER_PANE" -x 30 2>/dev/null
        echo -e "${GREEN}==> Question/timer panes opened automatically (tmux split-window).${RESET}"
      else
        echo -e "${YELLOW}==> Could not auto-open the question/timer panes. Run manually: $SHOW_TIMER${RESET}"
      fi
      tmux set-option -g mouse on 2>/dev/null || true
      tmux set-option -g history-limit 50000 2>/dev/null || true
    fi
  else
    echo -e "${YELLOW}==> To keep the timer fixed on screen, run in another terminal/pane: $SHOW_TIMER${RESET}"
  fi
fi
