#!/bin/bash
# Displays the exam timer fixed on screen, updating every second, so you can
# keep it visible in a separate terminal/pane while you work on the questions
# in another one.
#
# Usage: ./scripts/show-timer.sh
#
# Tip: open a second terminal (or split your terminal with tmux/screen,
# e.g. `tmux split-window -h ./scripts/show-timer.sh`) and run this script
# there. It automatically waits for the timer to start (i.e. for you to run
# scripts/run-question.sh for the first time) and keeps refreshing until
# scripts/finish-test.sh ends the session (removing the timer file).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
EXAM_DURATION_SECONDS=$((2 * 60 * 60))

# Colors (disabled automatically when not attached to a terminal).
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'
  CYAN='\033[36m'; YELLOW='\033[33m'; GREEN='\033[32m'; RED='\033[31m'; BLUE='\033[34m'
else
  BOLD=''; RESET=''; CYAN=''; YELLOW=''; GREEN=''; RED=''; BLUE=''
fi

while true; do
  clear
  echo -e "${CYAN}==================================================${RESET}"
  echo -e "${BOLD}${CYAN}                 CKA EXAM TIMER${RESET}"
  echo -e "${CYAN}==================================================${RESET}"

  if [[ ! -f "$TIMER_FILE" ]]; then
    echo
    echo -e "${YELLOW}Waiting for the session to start...${RESET}"
    echo "Run 'scripts/run-question.sh <number>' to start the timer."
    sleep 1
    continue
  fi

  START_TS="$(cat "$TIMER_FILE")"
  NOW_TS="$(date +%s)"
  ELAPSED=$((NOW_TS - START_TS))
  [[ "$ELAPSED" -lt 0 ]] && ELAPSED=0
  REMAINING=$((EXAM_DURATION_SECONDS - ELAPSED))

  ELAPSED_FMT="$(printf '%02d:%02d:%02d' $((ELAPSED / 3600)) $(((ELAPSED % 3600) / 60)) $((ELAPSED % 60)))"

  if [[ "$REMAINING" -le 0 ]]; then
    REMAINING_ABS=$((-REMAINING))
    REMAINING_FMT="$(printf '%02d:%02d:%02d' $((REMAINING_ABS / 3600)) $(((REMAINING_ABS % 3600) / 60)) $((REMAINING_ABS % 60)))"
    echo
    echo -e "${BLUE}Elapsed:${RESET}   ${BOLD}$ELAPSED_FMT${RESET}"
    echo -e "${RED}Overtime:  +$REMAINING_FMT  (over the 2h CKA time limit!)${RESET}"
  else
    REMAINING_FMT="$(printf '%02d:%02d:%02d' $((REMAINING / 3600)) $(((REMAINING % 3600) / 60)) $((REMAINING % 60)))"
    echo
    echo -e "${BLUE}Elapsed:${RESET}   ${BOLD}$ELAPSED_FMT${RESET}"
    if [[ "$REMAINING" -le 600 ]]; then
      echo -e "${RED}Remaining: $REMAINING_FMT  (of the 2h CKA time limit)${RESET}"
    elif [[ "$REMAINING" -le 1800 ]]; then
      echo -e "${YELLOW}Remaining: $REMAINING_FMT  (of the 2h CKA time limit)${RESET}"
    else
      echo -e "${GREEN}Remaining: $REMAINING_FMT  (of the 2h CKA time limit)${RESET}"
    fi
  fi

  echo -e "${CYAN}==================================================${RESET}"
  echo "Press Ctrl+C to close this timer window."

  sleep 1
done
