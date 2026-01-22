#!/bin/bash
set -e

# Ralph Test Generator (Docker Sandbox version) for mixbridge-ios
# Usage: ./ralph-tests-docker.sh <iterations> [module]
# Modules: setup, services, viewmodels, models, utils, auth, sync, db, all

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [module]"
  echo "Modules: setup, services, viewmodels, models, utils, auth, sync, db, all"
  exit 1
fi

ITERATIONS=$1
MODULE=${2:-all}
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# jq filter to extract streaming text from assistant messages
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'

# jq filter to extract final result
final_result='select(.type == "result").result // empty'

run_ralph_docker() {
  local prompt="$1"
  local max_iterations="$2"

  for ((i=1; i<=$max_iterations; i++)); do
    echo "=== Iteration $i of $max_iterations ==="
    tmpfile=$(mktemp)
    trap "rm -f $tmpfile" EXIT

    docker sandbox run --credentials host claude \
      --verbose \
      --print \
      --output-format stream-json \
      "$prompt" \
    | grep --line-buffered '^{' \
    | tee "$tmpfile" \
    | jq --unbuffered -rj "$stream_text"

    result=$(jq -r "$final_result" "$tmpfile")

    if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
      echo "Ralph complete after $i iterations."
      return 0
    fi
  done
  echo "Completed $max_iterations iterations."
}

# Source the prompts from the main script
source "$(dirname "$0")/ralph-test-prompts.sh"

# Execute based on module
case $MODULE in
  setup)
    echo "=== Setting up test infrastructure ==="
    run_ralph_docker "$SETUP_PROMPT" "$ITERATIONS"
    ;;
  services)
    echo "=== Writing service tests ==="
    run_ralph_docker "$SERVICES_PROMPT" "$ITERATIONS"
    ;;
  viewmodels)
    echo "=== Writing ViewModel tests ==="
    run_ralph_docker "$VIEWMODELS_PROMPT" "$ITERATIONS"
    ;;
  models)
    echo "=== Writing model tests ==="
    run_ralph_docker "$MODELS_PROMPT" "$ITERATIONS"
    ;;
  utils)
    echo "=== Writing utility tests ==="
    run_ralph_docker "$UTILS_PROMPT" "$ITERATIONS"
    ;;
  auth)
    echo "=== Writing auth tests ==="
    run_ralph_docker "$AUTH_PROMPT" "$ITERATIONS"
    ;;
  sync)
    echo "=== Writing sync tests ==="
    run_ralph_docker "$SYNC_PROMPT" "$ITERATIONS"
    ;;
  db)
    echo "=== Writing database tests ==="
    run_ralph_docker "$DB_PROMPT" "$ITERATIONS"
    ;;
  all)
    echo "=== Running all test generation modules ==="
    for mod in setup services viewmodels models utils auth sync db; do
      echo ""
      echo "=== Module: $mod ==="
      $0 "$ITERATIONS" "$mod"
    done
    echo ""
    echo "=== All test modules complete ==="
    ;;
  *)
    echo "Unknown module: $MODULE"
    echo "Available: setup, services, viewmodels, models, utils, auth, sync, db, all"
    exit 1
    ;;
esac
