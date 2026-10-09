#!/usr/bin/env bash
# Keeps the current question's description fixed on screen, automatically
# refreshing whenever a new question is started (run-question.sh overwrites
# scripts/.session_question every time a question is set up), so this pane
# never goes stale while you move between questions in the same tmux session.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUESTION_FILE="$REPO_ROOT/scripts/.session_question"

# Colors (disabled automatically when not attached to a terminal).
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'; BLUE='\033[34m'
else
  BOLD=''; RESET=''; BLUE=''
fi

LAST_HASH=""
while true; do
  if [[ -f "$QUESTION_FILE" ]]; then
    CUR_HASH="$(md5sum "$QUESTION_FILE" 2>/dev/null | awk '{print $1}')"
    if [[ "$CUR_HASH" != "$LAST_HASH" ]]; then
      clear
      echo -e "${BOLD}${BLUE}==> Question${RESET}"
      cat "$QUESTION_FILE"
      LAST_HASH="$CUR_HASH"
    fi
  else
    clear
    echo "Waiting for the first question to start..."
    LAST_HASH=""
  fi
  sleep 1
done
