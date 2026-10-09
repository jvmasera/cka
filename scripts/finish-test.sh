#!/bin/bash
# finish-test.sh
# Ends the current practice test session and grades it like the real CKA exam:
# - Computes the score as a percentage of correctly solved questions
# - Compares against the CKA passing score (66%)
# - Shows which questions were correct/incorrect and why
set -uo pipefail

# Colors (disabled automatically when not attached to a terminal).
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'
  CYAN='\033[36m'; YELLOW='\033[33m'; GREEN='\033[32m'; RED='\033[31m'; BLUE='\033[34m'; MAGENTA='\033[35m'
else
  BOLD=''; RESET=''; CYAN=''; YELLOW=''; GREEN=''; RED=''; BLUE=''; MAGENTA=''
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Always operate from the repo root, regardless of the directory the user was
# in when invoking "cka finish" (e.g. from inside "sandbox/" or any other
# folder). Without this, the "-d $QUESTION_DIR" checks below (which use the
# relative paths stored in .session_log) would fail to find any question
# directory, causing every attempted question to be wrongly reported as
# "Not attempted during this session."
cd "$REPO_ROOT"
LOG_FILE="$REPO_ROOT/scripts/.session_log"
TIMER_FILE="$REPO_ROOT/scripts/.session_start"
RESULTS_FILE="$REPO_ROOT/scripts/.session_results"
PAUSE_FILE="$REPO_ROOT/scripts/.session_pause"
PAUSED_TOTAL_FILE="$REPO_ROOT/scripts/.session_paused_total"
RESUME_FILE="$REPO_ROOT/scripts/.session_resume"

# Reads a cached Verify.bash output (captured by run-question.sh right before
# it reset the cluster for the next question) for the given question
# directory, if one exists. Prints nothing (empty string) when there's no
# cached entry for it.
get_cached_output() {
  local question_dir="$1"
  [[ -f "$RESULTS_FILE" ]] || return 0
  awk -v q="@@QUESTION@@$question_dir" '
    $0 == q { found=1; next }
    found && $0 == "@@ENDQUESTION@@" { exit }
    found { print }
  ' "$RESULTS_FILE"
}
PASSING_SCORE=66
TARGET_SCORE_LOW=75
TARGET_SCORE_HIGH=80
EXAM_DURATION_SECONDS=$((2 * 60 * 60))

# CKA exam domains and their official weight on the real exam. Used to break
# down the practice score by domain, so you can see which areas need more
# study (mirrors the current CKA curriculum weights).
declare -A DOMAIN_WEIGHT=(
  ["Troubleshooting"]=30
  ["Cluster Architecture, Installation & Configuration"]=25
  ["Services & Networking"]=20
  ["Workloads & Scheduling"]=15
  ["Storage"]=10
)
# Domain ordering for a stable, weight-descending report.
DOMAIN_ORDER=("Troubleshooting" "Cluster Architecture, Installation & Configuration" "Services & Networking" "Workloads & Scheduling" "Storage")

# Maps each question folder to the CKA domain it exercises.
declare -A QUESTION_DOMAIN=(
  ["Question-1 MariaDB-Persistent volume"]="Storage"
  ["Question-2 ArgoCD"]="Cluster Architecture, Installation & Configuration"
  ["Question-3 Sidecar"]="Workloads & Scheduling"
  ["Question-4 Resource-Allocation"]="Workloads & Scheduling"
  ["Question-5 HPA"]="Workloads & Scheduling"
  ["Question-6 CRDs"]="Cluster Architecture, Installation & Configuration"
  ["Question-7 PriorityClass"]="Workloads & Scheduling"
  ["Question-8 CNI & Network Policy"]="Services & Networking"
  ["Question-9 Cri-Dockerd"]="Cluster Architecture, Installation & Configuration"
  ["Question-10 Taints-Tolerations"]="Workloads & Scheduling"
  ["Question-11 Gateway-API"]="Services & Networking"
  ["Question-12 Ingress"]="Services & Networking"
  ["Question-13 Network-Policy"]="Services & Networking"
  ["Question-14 Storage-Class"]="Storage"
  ["Question-15 Etcd-Fix"]="Troubleshooting"
  ["Question-16 NodePort"]="Services & Networking"
  ["Question-17 TLS-Config"]="Troubleshooting"
)
declare -A DOMAIN_TOTAL=()
declare -A DOMAIN_CORRECT=()

if [[ ! -f "$LOG_FILE" || ! -s "$LOG_FILE" ]]; then
  echo "No questions were attempted in this session (nothing logged in $LOG_FILE)." >&2
  echo "Run questions first with: scripts/run-question.sh <number>" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Warning: kubectl not found, verification may be incomplete." >&2
fi

# Stop the exam timer: compute elapsed time since the first question was run,
# excluding any time spent paused while the cluster reset / the environment
# was being initialized between questions (and any pause still in progress).
if [[ -f "$TIMER_FILE" ]]; then
  START_TS="$(cat "$TIMER_FILE")"
  END_TS="$(date +%s)"

  PAUSED_TOTAL=0
  [[ -f "$PAUSED_TOTAL_FILE" ]] && PAUSED_TOTAL="$(cat "$PAUSED_TOTAL_FILE" 2>/dev/null || echo 0)"
  [[ -z "$PAUSED_TOTAL" ]] && PAUSED_TOTAL=0
  if [[ -f "$PAUSE_FILE" ]]; then
    PAUSE_START="$(cat "$PAUSE_FILE")"
    ONGOING_PAUSE=$((END_TS - PAUSE_START))
    [[ "$ONGOING_PAUSE" -lt 0 ]] && ONGOING_PAUSE=0
    PAUSED_TOTAL=$((PAUSED_TOTAL + ONGOING_PAUSE))
  fi

  ELAPSED=$((END_TS - START_TS - PAUSED_TOTAL))
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

# Build the set of questions actually attempted in this session.
declare -A ATTEMPTED=()
while IFS= read -r QUESTION_DIR; do
  [[ -z "$QUESTION_DIR" ]] && continue
  [[ -d "$QUESTION_DIR" ]] || continue
  ATTEMPTED["$QUESTION_DIR"]=1
done < "$LOG_FILE"

# The CKA real exam always has the same number of questions (currently 17),
# so the score must be computed over ALL questions, not only the ones you
# attempted in this session. Any question not attempted counts as wrong.
ALL_QUESTIONS=()
for QUESTION_DIR in "$REPO_ROOT"/Question-*/; do
  QUESTION_DIR="$(basename "$QUESTION_DIR")"
  ALL_QUESTIONS+=("$QUESTION_DIR")
done

TOTAL=${#ALL_QUESTIONS[@]}
ATTEMPTED_COUNT=${#ATTEMPTED[@]}
CORRECT=0
declare -a CORRECT_LIST=()
declare -a WRONG_LIST=()
declare -a WRONG_REASONS=()
declare -a WRONG_DOMAINS=()

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No valid questions found to grade." >&2
  exit 1
fi

for QUESTION_DIR in "${ALL_QUESTIONS[@]}"; do
  VERIFY="$REPO_ROOT/$QUESTION_DIR/Verify.bash"
  DOMAIN="${QUESTION_DOMAIN[$QUESTION_DIR]:-Unknown}"
  DOMAIN_TOTAL["$DOMAIN"]=$(( ${DOMAIN_TOTAL["$DOMAIN"]:-0} + 1 ))

  if [[ -z "${ATTEMPTED[$QUESTION_DIR]:-}" ]]; then
    WRONG_LIST+=("$QUESTION_DIR")
    WRONG_REASONS+=("  - Not attempted during this session.")
    WRONG_DOMAINS+=("$DOMAIN")
    continue
  fi

  if [[ ! -f "$VERIFY" ]]; then
    WRONG_LIST+=("$QUESTION_DIR")
    WRONG_REASONS+=("No Verify.bash found for this question, could not be auto-graded.")
    WRONG_DOMAINS+=("$DOMAIN")
    continue
  fi

  # Prefer a cached result (captured by run-question.sh right before it reset
  # the cluster for the next question) when available: the cluster may no
  # longer have the objects for this question once a later one reset it. Only
  # fall back to a live check when there's no cache, e.g. the question you're
  # still actively working on (its state is still live in the cluster).
  CACHED_OUTPUT="$(get_cached_output "$QUESTION_DIR")"
  if [[ -n "$CACHED_OUTPUT" ]]; then
    OUTPUT="$CACHED_OUTPUT"
  else
    chmod +x "$VERIFY" 2>/dev/null || true
    OUTPUT="$(bash "$VERIFY" 2>&1)"
  fi
  RESULT_LINE="$(echo "$OUTPUT" | grep -m1 '^RESULT:' || true)"
  REASONS="$(echo "$OUTPUT" | grep '^REASON:' | sed 's/^REASON:[[:space:]]*/  - /')"

  if [[ "$RESULT_LINE" == "RESULT:PASS" ]]; then
    CORRECT=$((CORRECT + 1))
    CORRECT_LIST+=("$QUESTION_DIR")
    DOMAIN_CORRECT["$DOMAIN"]=$(( ${DOMAIN_CORRECT["$DOMAIN"]:-0} + 1 ))
  else
    WRONG_LIST+=("$QUESTION_DIR")
    WRONG_DOMAINS+=("$DOMAIN")
    if [[ -n "$REASONS" ]]; then
      WRONG_REASONS+=("$REASONS")
    else
      WRONG_REASONS+=("  - Verification failed (no detailed reason returned).")
    fi
  fi
done

PERCENT=$(( CORRECT * 100 / TOTAL ))
if [[ "$PERCENT" -ge "$TARGET_SCORE_HIGH" ]]; then
  SCORE_COLOR="$GREEN"
elif [[ "$PERCENT" -ge "$PASSING_SCORE" ]]; then
  SCORE_COLOR="$YELLOW"
else
  SCORE_COLOR="$RED"
fi

echo -e "${CYAN}==================================================${RESET}"
echo -e "${BOLD}${CYAN}                CKA PRACTICE RESULTS${RESET}"
echo -e "${CYAN}==================================================${RESET}"
echo -e "${BLUE}Time elapsed:${RESET}         $ELAPSED_FMT ($TIME_STATUS)"
echo -e "${BLUE}Time limit:${RESET}           02:00:00 (CKA exam duration)"
echo -e "${BLUE}Total exam questions:${RESET} $TOTAL"
echo -e "${BLUE}Questions attempted:${RESET}  $ATTEMPTED_COUNT"
echo -e "${BLUE}Correct answers:${RESET}      ${GREEN}$CORRECT${RESET}"
echo -e "${BLUE}Score:${RESET}                 ${BOLD}${SCORE_COLOR}$PERCENT%${RESET}  ($CORRECT/$TOTAL)"
echo -e "${BLUE}Passing score:${RESET}        $PASSING_SCORE% (official CKA minimum to pass)"
echo -e "${CYAN}--------------------------------------------------${RESET}"
if [[ "$PERCENT" -ge "$PASSING_SCORE" ]]; then
  echo -e "${BOLD}${GREEN}Result: PASSED ✅ (you need at least $PASSING_SCORE% to pass the real CKA)${RESET}"
else
  echo -e "${BOLD}${RED}Result: FAILED ❌ (you need at least $PASSING_SCORE% to pass the real CKA)${RESET}"
fi
if [[ "$PERCENT" -ge "$TARGET_SCORE_HIGH" ]]; then
  echo -e "${GREEN}Practice target: 🎯 Great! You're at/above the ${TARGET_SCORE_LOW}-${TARGET_SCORE_HIGH}%+ practice target (safety margin for exam day).${RESET}"
else
  echo -e "${YELLOW}Practice target: 🎯 Aim for ${TARGET_SCORE_LOW}-${TARGET_SCORE_HIGH}%+ in practice runs for a safety margin on exam day.${RESET}"
fi
echo -e "${CYAN}==================================================${RESET}"
echo

echo -e "${BOLD}${MAGENTA}CKA domain weight breakdown (official exam weights):${RESET}"
for DOMAIN in "${DOMAIN_ORDER[@]}"; do
  D_TOTAL="${DOMAIN_TOTAL[$DOMAIN]:-0}"
  D_CORRECT="${DOMAIN_CORRECT[$DOMAIN]:-0}"
  WEIGHT="${DOMAIN_WEIGHT[$DOMAIN]}"
  if [[ "$D_TOTAL" -gt 0 ]]; then
    D_PERCENT=$(( D_CORRECT * 100 / D_TOTAL ))
    if [[ "$D_PERCENT" -ge "$TARGET_SCORE_HIGH" ]]; then
      D_COLOR="$GREEN"
    elif [[ "$D_PERCENT" -ge "$PASSING_SCORE" ]]; then
      D_COLOR="$YELLOW"
    else
      D_COLOR="$RED"
    fi
    printf "  - ${CYAN}%-52s${RESET} weight: %2d%%  |  attempted: %d/%d  |  score: ${D_COLOR}%d%%${RESET}\n" "$DOMAIN" "$WEIGHT" "$D_CORRECT" "$D_TOTAL" "$D_PERCENT"
  else
    printf "  - ${CYAN}%-52s${RESET} weight: %2d%%  |  ${YELLOW}attempted: 0 (not covered this session)${RESET}\n" "$DOMAIN" "$WEIGHT"
  fi
done
echo

if [[ ${#CORRECT_LIST[@]} -gt 0 ]]; then
  echo -e "${BOLD}${GREEN}✔ Correct questions:${RESET}"
  for q in "${CORRECT_LIST[@]}"; do
    echo -e "  ${GREEN}- $q${RESET}"
  done
  echo
fi

if [[ ${#WRONG_LIST[@]} -gt 0 ]]; then
  echo -e "${BOLD}${RED}✘ Incorrect questions (and why):${RESET}"
  for i in "${!WRONG_LIST[@]}"; do
    echo -e "  ${RED}- ${WRONG_LIST[$i]}${RESET} ${MAGENTA}[${WRONG_DOMAINS[$i]:-Unknown}]${RESET}"
    echo -e "${YELLOW}${WRONG_REASONS[$i]}${RESET}"
  done
  echo
fi

echo -e "${CYAN}Tip:${RESET} run 'scripts/run-question.sh <number>' again to retry a question, then"
echo "'scripts/finish-test.sh' once more to re-grade the session."
echo

# Remove the timer file and cached verification results so a new session
# starts fresh the next time scripts/run-question.sh is run for the first
# question.
rm -f "$TIMER_FILE"
rm -f "$RESULTS_FILE"
rm -f "$PAUSE_FILE" "$PAUSED_TOTAL_FILE" "$RESUME_FILE"
