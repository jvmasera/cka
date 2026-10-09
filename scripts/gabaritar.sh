#!/usr/bin/env bash
# "cka gabaritar" - automated self-test of the whole repo.
#
# Goes through every "Question-*" directory in order, runs
# run-question.sh <N> (reset cluster + lab setup), applies that question's
# own SolutionNotes.bash (the documented correct solution), and at the end
# runs finish-test.sh. Since every question is solved "by the book" before
# moving to the next one, the final score SHOULD be 100%. If it isn't, that
# means either a Verify.bash has a bug (false FAIL) or the caching mechanism
# that preserves a question's result across cluster resets is leaking /
# overwriting results between questions. Run this after changing any
# Verify.bash, SolutionNotes.bash or the caching logic in run-question.sh /
# finish-test.sh to confirm everything still grades correctly end-to-end.
#
# Usage:
#   scripts/gabaritar.sh              (or: cka gabaritar)             -> solves ALL questions
#   scripts/gabaritar.sh <number>      (or: cka gabaritar <number>)     -> solves and grades ONLY that question
#   scripts/gabaritar.sh <N>-<M>       (or: cka gabaritar 1-2)          -> solves and grades a range of questions
#   scripts/gabaritar.sh <N>,<M>,...   (or: cka gabaritar 1,3,5)        -> solves and grades a comma-separated list

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'
  CYAN='\033[36m'; YELLOW='\033[33m'; GREEN='\033[32m'; RED='\033[31m'; BLUE='\033[34m'
else
  BOLD=''; RESET=''; CYAN=''; YELLOW=''; GREEN=''; RED=''; BLUE=''
fi

RUN_QUESTION="$REPO_ROOT/scripts/run-question.sh"
FINISH_TEST="$REPO_ROOT/scripts/finish-test.sh"
chmod +x "$RUN_QUESTION" "$FINISH_TEST" 2>/dev/null || true

if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${RED}Error: kubectl not found. 'cka gabaritar' needs a real cluster to apply each SolutionNotes.bash and verify the result.${RESET}" >&2
  exit 1
fi

# Collect all question directories, sorted numerically by their "Question-N"
# prefix (so Question-2 runs before Question-10, etc), exactly like
# finish-test.sh does when listing the full exam.
mapfile -t ALL_QUESTION_DIRS < <(find "$REPO_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'Question-*' -printf '%f\n' \
  | sed -E 's/^Question-([0-9]+)/\1\t&/' | sort -n -k1 | cut -f2-)

if [[ ${#ALL_QUESTION_DIRS[@]} -eq 0 ]]; then
  echo -e "${RED}No Question-* directories found.${RESET}" >&2
  exit 1
fi

# If a specific question number, a range ("1-2"), a comma-separated list
# ("1,3,5"), or a full directory name is given as an argument, restrict this
# run to just those questions instead of the whole exam, e.g.
# "cka gabaritar 15" solves and grades only Question-15, and
# "cka gabaritar 1-2" solves and grades Question-1 then Question-2.
SINGLE_ARG="${1:-}"

# Resolve a single token (plain number or full directory name) to its
# matching directory name(s) in ALL_QUESTION_DIRS, appended to QUESTION_DIRS,
# preserving the exam's numeric order and without duplicates.
resolve_token() {
  local token="$1" dir found=0
  for dir in "${ALL_QUESTION_DIRS[@]}"; do
    if [[ "$token" =~ ^[0-9]+$ ]]; then
      if [[ "$dir" =~ ^Question-${token}([[:space:]]|-|$) ]]; then
        found=1
        if [[ ! " ${QUESTION_DIRS[*]:-} " == *" $dir "* ]]; then
          QUESTION_DIRS+=("$dir")
        fi
      fi
    elif [[ "$dir" == "$token" ]]; then
      found=1
      if [[ ! " ${QUESTION_DIRS[*]:-} " == *" $dir "* ]]; then
        QUESTION_DIRS+=("$dir")
      fi
    fi
  done
  [[ $found -eq 1 ]]
}

QUESTION_DIRS=()
if [[ -n "$SINGLE_ARG" ]]; then
  # Split by comma first, so "1-2,5" or "1,3,5" both work; each piece can
  # itself be a plain number, a range "N-M", or a full directory name.
  IFS=',' read -r -a TOKENS <<< "$SINGLE_ARG"
  for token in "${TOKENS[@]}"; do
    token="$(echo "$token" | xargs)"   # trim whitespace
    [[ -z "$token" ]] && continue
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      RANGE_START="${BASH_REMATCH[1]}"
      RANGE_END="${BASH_REMATCH[2]}"
      if [[ "$RANGE_START" -gt "$RANGE_END" ]]; then
        echo -e "${RED}Invalid range '$token': start is greater than end.${RESET}" >&2
        exit 1
      fi
      for ((n = RANGE_START; n <= RANGE_END; n++)); do
        if ! resolve_token "$n"; then
          echo -e "${RED}No question directory found matching '$n' (from range '$token').${RESET}" >&2
          exit 1
        fi
      done
    else
      if ! resolve_token "$token"; then
        echo -e "${RED}No question directory found matching '$token'.${RESET}" >&2
        exit 1
      fi
    fi
  done
else
  QUESTION_DIRS=("${ALL_QUESTION_DIRS[@]}")
fi

if [[ ${#QUESTION_DIRS[@]} -eq ${#ALL_QUESTION_DIRS[@]} ]]; then
  echo -e "${BOLD}${BLUE}==> cka gabaritar: solving all ${#QUESTION_DIRS[@]} questions with their own SolutionNotes.bash, then running finish-test.sh${RESET}"
  echo -e "${YELLOW}This is meant to sanity-check Verify.bash + the session cache; a correct run should score 100%.${RESET}"
elif [[ ${#QUESTION_DIRS[@]} -eq 1 ]]; then
  echo -e "${BOLD}${BLUE}==> cka gabaritar: solving only '${QUESTION_DIRS[0]}' with its own SolutionNotes.bash, then running finish-test.sh${RESET}"
  echo -e "${YELLOW}Note: finish-test.sh always grades over all 17 exam questions, so any question not solved in this run will still count as 'Not attempted'.${RESET}"
else
  echo -e "${BOLD}${BLUE}==> cka gabaritar: solving ${#QUESTION_DIRS[@]} selected questions (${QUESTION_DIRS[*]}) with their own SolutionNotes.bash, then running finish-test.sh${RESET}"
  echo -e "${YELLOW}Note: finish-test.sh always grades over all 17 exam questions, so any question not solved in this run will still count as 'Not attempted'.${RESET}"
fi
echo

# Start a brand new test session, so this run doesn't mix with (or get
# polluted by) any previous practice session's log/cache/timer.
export NEW_TEST_SESSION=1

# Always skip run-question.sh's auto-tmux launch here, even when this script
# is itself run from a real terminal. That auto-launch "exec"s into
# "tmux attach-session", replacing the current process and leaving the
# actual reset/setup/logging to happen asynchronously inside a separate
# detached tmux pane - which races against this very loop immediately
# moving on to apply SolutionNotes.bash before LabSetUp.bash has finished
# (or even started). CKA_NO_TMUX forces run-question.sh to always execute
# everything inline and synchronously instead.
export CKA_NO_TMUX=1

FAILED_TO_APPLY=()

for QUESTION_DIR in "${QUESTION_DIRS[@]}"; do
  echo -e "${CYAN}==================================================${RESET}"
  echo -e "${BOLD}==> Setting up: $QUESTION_DIR${RESET}"
  "$RUN_QUESTION" "$QUESTION_DIR" </dev/null
  unset NEW_TEST_SESSION

  SOLUTION="$REPO_ROOT/$QUESTION_DIR/SolutionNotes.bash"
  if [[ -f "$SOLUTION" ]]; then
    echo -e "${CYAN}==> Applying SolutionNotes.bash for: $QUESTION_DIR${RESET}"
    if ! bash "$SOLUTION"; then
      echo -e "${RED}==> Warning: SolutionNotes.bash for '$QUESTION_DIR' exited with a non-zero status.${RESET}"
      FAILED_TO_APPLY+=("$QUESTION_DIR")
    fi
  else
    echo -e "${YELLOW}==> No SolutionNotes.bash found for '$QUESTION_DIR', skipping.${RESET}"
    FAILED_TO_APPLY+=("$QUESTION_DIR")
  fi
  echo
done

echo -e "${CYAN}==================================================${RESET}"
echo -e "${BOLD}${BLUE}==> All questions solved. Running finish-test.sh...${RESET}"
echo

"$FINISH_TEST"
FINISH_EXIT=$?

if [[ ${#FAILED_TO_APPLY[@]} -gt 0 ]]; then
  echo
  echo -e "${YELLOW}==> Note: SolutionNotes.bash could not be fully applied (or was missing) for: ${FAILED_TO_APPLY[*]}${RESET}"
fi

exit "$FINISH_EXIT"
