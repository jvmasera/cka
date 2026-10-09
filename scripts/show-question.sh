#!/usr/bin/env bash
# Keeps the current question's description fixed on screen, automatically
# refreshing whenever a new question is started (run-question.sh overwrites
# scripts/.session_question every time a question is set up), so this pane
# never goes stale while you move between questions in the same tmux session.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUESTION_FILE="$REPO_ROOT/scripts/.session_question"
QUESTION_NAME_FILE="$REPO_ROOT/scripts/.session_question_name"

# Colors (disabled automatically when not attached to a terminal).
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'; BLUE='\033[34m'
else
  BOLD=''; RESET=''; BLUE=''
fi

LAST_HASH=""
LAST_COLS=""
while true; do
  # Re-wrap whenever the pane is resized, even if the question text itself
  # hasn't changed, so lines always fit the current pane width.
  COLS="$(tput cols 2>/dev/null || echo 80)"
  if [[ -f "$QUESTION_FILE" ]]; then
    CUR_HASH="$(md5sum "$QUESTION_FILE" 2>/dev/null | awk '{print $1}')"
    if [[ "$CUR_HASH" != "$LAST_HASH" || "$COLS" != "$LAST_COLS" ]]; then
      clear
      echo -e "${BOLD}${BLUE}==> Question${RESET}"
      # Wrap text at whole words only (never breaking a word in the middle),
      # a couple of columns short of the pane width. This keeps every visual
      # line inside this pane's own wrapping, instead of letting the
      # terminal hard-wrap mid-word right at the pane edge, which is what
      # made mouse selection "leak" into the neighboring (timer) pane when
      # dragging past a line that filled the whole width.
      fold -s -w "$(( COLS > 4 ? COLS - 2 : COLS ))" "$QUESTION_FILE"
      LAST_HASH="$CUR_HASH"
      LAST_COLS="$COLS"
      # Rename this pane's title to the current question, so it's visible
      # directly in the tmux pane border, without needing to scroll up.
      if [[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1 && [[ -f "$QUESTION_NAME_FILE" ]]; then
        tmux select-pane -t "$TMUX_PANE" -T "$(cat "$QUESTION_NAME_FILE")" 2>/dev/null || true
      fi
    fi
  else
    clear
    echo "Waiting for the first question to start..."
    LAST_HASH=""
  fi
  sleep 1
done
