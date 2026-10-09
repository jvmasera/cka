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
PAUSE_FILE="$REPO_ROOT/scripts/.session_pause"
PAUSED_TOTAL_FILE="$REPO_ROOT/scripts/.session_paused_total"
RESUME_FILE="$REPO_ROOT/scripts/.session_resume"
EXAM_DURATION_SECONDS=$((2 * 60 * 60))
# How long the "Timer resumed!" message stays visible after a pause ends.
RESUME_NOTICE_SECONDS=5

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

  # Account for paused time (e.g. while the cluster resets / the question's
  # environment is being set up) so it doesn't count against the exam clock.
  PAUSED_TOTAL=0
  [[ -f "$PAUSED_TOTAL_FILE" ]] && PAUSED_TOTAL="$(cat "$PAUSED_TOTAL_FILE" 2>/dev/null || echo 0)"
  [[ -z "$PAUSED_TOTAL" ]] && PAUSED_TOTAL=0

  IS_PAUSED=0
  if [[ -f "$PAUSE_FILE" ]]; then
    IS_PAUSED=1
    PAUSE_START="$(cat "$PAUSE_FILE")"
    CURRENT_PAUSE_DURATION=$((NOW_TS - PAUSE_START))
    [[ "$CURRENT_PAUSE_DURATION" -lt 0 ]] && CURRENT_PAUSE_DURATION=0
    PAUSED_TOTAL=$((PAUSED_TOTAL + CURRENT_PAUSE_DURATION))
  fi

  ELAPSED=$((NOW_TS - START_TS - PAUSED_TOTAL))
  [[ "$ELAPSED" -lt 0 ]] && ELAPSED=0
  REMAINING=$((EXAM_DURATION_SECONDS - ELAPSED))

  ELAPSED_FMT="$(printf '%02d:%02d:%02d' $((ELAPSED / 3600)) $(((ELAPSED % 3600) / 60)) $((ELAPSED % 60)))"

  # Build a fixed-width progress bar showing how much of the 2h exam time is
  # still remaining (the exact remaining time is shown below on the
  # "Remaining:" line, so the bar itself stays clean).
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
  else
    REMAINING_FMT="$(printf '%02d:%02d:%02d' $((REMAINING / 3600)) $(((REMAINING % 3600) / 60)) $((REMAINING % 60)))"
    if [[ "$REMAINING" -le 600 ]]; then
      BAR_COLOR="$RED"
    elif [[ "$REMAINING" -le 1800 ]]; then
      BAR_COLOR="$YELLOW"
    else
      BAR_COLOR="$GREEN"
    fi
  fi

  BAR_FULL="$(printf '%0.s#' $(seq 1 "$FILLED" 2>/dev/null))"
  BAR_VOID="$(printf '%0.s-' $(seq 1 "$EMPTY" 2>/dev/null))"
  BAR_DISPLAY="${BAR_FULL}${BAR_VOID}"

  echo
  echo -e "${BLUE}Elapsed:${RESET}   ${BOLD}$ELAPSED_FMT${RESET}  /  02:00:00 (CKA exam duration)"
  echo -e "${BAR_COLOR}[${BAR_DISPLAY}] ${PERCENT_REMAINING}%${RESET}"
  if [[ "$REMAINING" -le 0 ]]; then
    echo -e "${RED}Overtime:  +$REMAINING_FMT  (over the 2h CKA time limit!)${RESET}"
  else
    echo -e "${BAR_COLOR}Remaining: $REMAINING_FMT  (of the 2h CKA time limit)${RESET}"
  fi

  # Show the pause/resume status: PAUSED while the environment is being
  # (re)initialized, a short "RESUMED" notice right after it's ready again,
  # or RUNNING otherwise.
  if [[ "$IS_PAUSED" -eq 1 ]]; then
    echo -e "${YELLOW}${BOLD}Status: PAUSED${RESET}${YELLOW} - resetting cluster / initializing question environment...${RESET}"
  else
    RESUME_AGE=999999
    if [[ -f "$RESUME_FILE" ]]; then
      RESUME_TS="$(cat "$RESUME_FILE" 2>/dev/null || echo 0)"
      [[ -n "$RESUME_TS" ]] && RESUME_AGE=$((NOW_TS - RESUME_TS))
    fi
    if [[ "$RESUME_AGE" -ge 0 && "$RESUME_AGE" -le "$RESUME_NOTICE_SECONDS" ]]; then
      echo -e "${GREEN}${BOLD}Status: RESUMED${RESET}${GREEN} - environment ready, timer is running again.${RESET}"
    else
      echo -e "${GREEN}Status: RUNNING${RESET}"
    fi
  fi

  echo -e "${CYAN}==================================================${RESET}"
  echo "Press Ctrl+C to close this timer window."

  sleep 1
done
