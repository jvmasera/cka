#!/bin/bash
# finish-test.sh
# Ends the current practice test session and grades it like the real CKA exam:
# - Computes the score as a percentage of correctly solved questions
# - Compares against the CKA passing score (66%)
# - Shows which questions were correct/incorrect and why
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$REPO_ROOT/scripts/.session_log"
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
PASSING_SCORE=66
EXAM_DURATION_SECONDS=$((2 * 60 * 60))

if [[ ! -f "$LOG_FILE" || ! -s "$LOG_FILE" ]]; then
  echo "No questions were attempted in this session (nothing logged in $LOG_FILE)." >&2
  echo "Run questions first with: scripts/run-question.sh <number>" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Warning: kubectl not found, verification may be incomplete." >&2
fi

# Stop the exam timer: compute elapsed time since the first question was run.
if [[ -f "$TIMER_FILE" ]]; then
  START_TS="$(cat "$TIMER_FILE")"
  END_TS="$(date +%s)"
  ELAPSED=$((END_TS - START_TS))
  [[ "$ELAPSED" -lt 0 ]] && ELAPSED=0
else
  ELAPSED=0
fi
ELAPSED_H=$((ELAPSED / 3600))
ELAPSED_M=$(((ELAPSED % 3600) / 60))
ELAPSED_S=$((ELAPSED % 60))
ELAPSED_FMT="$(printf '%02d:%02d:%02d' "$ELAPSED_H" "$ELAPSED_M" "$ELAPSED_S")"
if [[ "$ELAPSED" -gt "$EXAM_DURATION_SECONDS" ]]; then
  TIME_STATUS="OVER the 2h CKA time limit"
else
  TIME_STATUS="within the 2h CKA time limit"
fi

TOTAL=0
CORRECT=0
declare -a CORRECT_LIST=()
declare -a WRONG_LIST=()
declare -a WRONG_REASONS=()

while IFS= read -r QUESTION_DIR; do
  [[ -z "$QUESTION_DIR" ]] && continue
  [[ -d "$QUESTION_DIR" ]] || continue

  TOTAL=$((TOTAL + 1))
  VERIFY="$REPO_ROOT/$QUESTION_DIR/Verify.bash"

  if [[ ! -f "$VERIFY" ]]; then
    WRONG_LIST+=("$QUESTION_DIR")
    WRONG_REASONS+=("No Verify.bash found for this question, could not be auto-graded.")
    continue
  fi

  chmod +x "$VERIFY" 2>/dev/null || true
  OUTPUT="$(bash "$VERIFY" 2>&1)"
  RESULT_LINE="$(echo "$OUTPUT" | grep -m1 '^RESULT:' || true)"
  REASONS="$(echo "$OUTPUT" | grep '^REASON:' | sed 's/^REASON:[[:space:]]*/  - /')"

  if [[ "$RESULT_LINE" == "RESULT:PASS" ]]; then
    CORRECT=$((CORRECT + 1))
    CORRECT_LIST+=("$QUESTION_DIR")
  else
    WRONG_LIST+=("$QUESTION_DIR")
    if [[ -n "$REASONS" ]]; then
      WRONG_REASONS+=("$REASONS")
    else
      WRONG_REASONS+=("  - Verification failed (no detailed reason returned).")
    fi
  fi
done < "$LOG_FILE"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No valid questions found to grade." >&2
  exit 1
fi

PERCENT=$(( CORRECT * 100 / TOTAL ))

echo "=================================================="
echo "                CKA PRACTICE RESULTS"
echo "=================================================="
echo "Time elapsed:         $ELAPSED_FMT ($TIME_STATUS)"
echo "Time limit:           02:00:00 (CKA exam duration)"
echo "Questions attempted: $TOTAL"
echo "Correct answers:     $CORRECT"
echo "Score:                $PERCENT%"
echo "Passing score:        $PASSING_SCORE%"
echo "--------------------------------------------------"
if [[ "$PERCENT" -ge "$PASSING_SCORE" ]]; then
  echo "Result: PASSED ✅ (you need at least $PASSING_SCORE% to pass the real CKA)"
else
  echo "Result: FAILED ❌ (you need at least $PASSING_SCORE% to pass the real CKA)"
fi
echo "=================================================="
echo

if [[ ${#CORRECT_LIST[@]} -gt 0 ]]; then
  echo "✔ Correct questions:"
  for q in "${CORRECT_LIST[@]}"; do
    echo "  - $q"
  done
  echo
fi

if [[ ${#WRONG_LIST[@]} -gt 0 ]]; then
  echo "✘ Incorrect questions (and why):"
  for i in "${!WRONG_LIST[@]}"; do
    echo "  - ${WRONG_LIST[$i]}"
    echo "${WRONG_REASONS[$i]}"
  done
  echo
fi

echo "Tip: run 'scripts/run-question.sh <number>' again to retry a question, then"
echo "'scripts/finish-test.sh' once more to re-grade the session."
echo

# Remove the timer file so a new session starts fresh the next time
# scripts/run-question.sh is run for the first question.
rm -f "$TIMER_FILE"
