#!/bin/bash
set -e

# Ralph single-file test generator
# Usage: ./ralph-test-file.sh <iterations> <source_file_path>
# Example: ./ralph-test-file.sh 3 mixbridge/Services/QueueManager.swift

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <iterations> <source_file_path>"
  echo "Example: $0 3 mixbridge/Services/QueueManager.swift"
  exit 1
fi

ITERATIONS=$1
SOURCE_FILE=$2
FILENAME=$(basename "$SOURCE_FILE" .swift)
DIR=$(dirname "$SOURCE_FILE" | sed 's|mixbridge/||')

# jq filters
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

PROMPT="You are writing unit tests for $SOURCE_FILE in the mixbridge-ios project.

TASK: Write comprehensive unit tests for ${FILENAME}.swift

1. First, read and understand the source file: $SOURCE_FILE
2. Identify all public methods and properties that need testing
3. Create test file at: mixbridgeTests/${DIR}/${FILENAME}Tests.swift

Test requirements:
- Test all public methods
- Cover happy path, error cases, and edge cases
- Use mocks for external dependencies
- Follow naming: test_methodName_condition_expectedResult
- Ensure tests are isolated and can run independently
- Add setup/teardown if needed

When the test file is complete and compiles, end with: <promise>COMPLETE</promise>"

for ((i=1; i<=$ITERATIONS; i++)); do
  echo "=== Iteration $i of $ITERATIONS for $FILENAME ==="
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  claude \
    --verbose \
    --print \
    --output-format stream-json \
    "$PROMPT" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "Tests complete for $FILENAME after $i iterations."
    exit 0
  fi
done

echo "Completed $ITERATIONS iterations for $FILENAME."
