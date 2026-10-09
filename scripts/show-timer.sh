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

  # Build a fixed-width progress bar showing how much of the 2h exam time is
  # still remaining, with the remaining time printed inside the bar itself.
  # It starts full (100%) and empties out as time runs out.
  BAR_WIDTH=40
  PERCENT_REMAINING=$((REMAINING * 100 / EXAM_DURATION_SECONDS))
  [[ "$PERCENT_REMAINING" -gt 100 ]] && PERCENT_REMAINING=100
  [[ "$PERCENT_REMAINING" -lt 0 ]] && PERCENT_REMAINING=0
  FILLED=$((PERCENT_REMAINING * BAR_WIDTH / 100))
  EMPTY=$((BAR_WIDTH - FILLED))

  if [[ "$REMAINING" -le 0 ]]; then
    REMAINING_ABS=$((-REMAINING))
    REMAINING_FMT="$(printf '%02d:%02d:%02d' $((REMAINING_ABS / 3600)) $(((REMAINING_ABS % 3600) / 60)) $((REMAINING_ABS % 60)))"
    BAR_COLOR="$RED"
    BAR_LABEL="+$REMAINING_FMT over"
  else
    REMAINING_FMT="$(printf '%02d:%02d:%02d' $((REMAINING / 3600)) $(((REMAINING % 3600) / 60)) $((REMAINING % 60)))"
    if [[ "$REMAINING" -le 600 ]]; then
      BAR_COLOR="$RED"
    elif [[ "$REMAINING" -le 1800 ]]; then
      BAR_COLOR="$YELLOW"
    else
      BAR_COLOR="$GREEN"
    fi
    BAR_LABEL="$REMAINING_FMT left"
  fi

  # Center the "time left" label inside the bar's total width.
  LABEL_LEN=${#BAR_LABEL}
  PAD_TOTAL=$((BAR_WIDTH - LABEL_LEN))
  [[ "$PAD_TOTAL" -lt 0 ]] && PAD_TOTAL=0
  PAD_LEFT=$((PAD_TOTAL / 2))
  PAD_RIGHT=$((PAD_TOTAL - PAD_LEFT))

  BAR_FULL="$(printf '%0.s#' $(seq 1 "$FILLED" 2>/dev/null))"
  BAR_VOID="$(printf '%0.s-' $(seq 1 "$EMPTY" 2>/dev/null))"
  BAR_RAW="${BAR_FULL}${BAR_VOID}"
  # Overlay the centered label on top of the raw bar characters so the bar
  # itself still shows the fill/empty proportion around the text. Only the
  # padding area (outside the label's own range) falls back to the raw bar
  # character; any space that is part of the label itself (e.g. between the
  # time and "left"/"over") is kept as a literal space.
  BAR_DISPLAY=""
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if [[ "$i" -ge "$PAD_LEFT" && "$i" -lt "$((PAD_LEFT + LABEL_LEN))" ]]; then
      BAR_DISPLAY+="${BAR_LABEL:$((i - PAD_LEFT)):1}"
    else
      BAR_DISPLAY+="${BAR_RAW:$i:1}"
    fi
  done

  echo
  echo -e "${BLUE}Elapsed:${RESET}   ${BOLD}$ELAPSED_FMT${RESET}  /  02:00:00 (CKA exam duration)"
  echo -e "${BAR_COLOR}[${BAR_DISPLAY}] ${PERCENT_REMAINING}%${RESET}"
  if [[ "$REMAINING" -le 0 ]]; then
    echo -e "${RED}Overtime:  +$REMAINING_FMT  (over the 2h CKA time limit!)${RESET}"
  else
    echo -e "${BAR_COLOR}Remaining: $REMAINING_FMT  (of the 2h CKA time limit)${RESET}"
  fi

  echo -e "${CYAN}==================================================${RESET}"
  echo "Press Ctrl+C to close this timer window."

  sleep 1
done
