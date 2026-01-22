#!/bin/bash
set -e

# Ralph batch test generator - processes multiple files sequentially
# Usage: ./ralph-test-batch.sh <iterations_per_file> <file1> [file2] [file3] ...
# Or:    ./ralph-test-batch.sh <iterations> --list files.txt

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> <file1> [file2] ..."
  echo "       $0 <iterations> --list files.txt"
  echo ""
  echo "Example: $0 3 mixbridge/Services/QueueManager.swift mixbridge/Models/Track.swift"
  exit 1
fi

ITERATIONS=$1
shift

SCRIPT_DIR="$(dirname "$0")"
FILES=()

if [ "$1" == "--list" ]; then
  if [ -z "$2" ] || [ ! -f "$2" ]; then
    echo "Error: File list not provided or doesn't exist"
    exit 1
  fi
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != \#* ]] && FILES+=("$line")
  done < "$2"
else
  FILES=("$@")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No files specified"
  exit 1
fi

echo "=== Ralph Batch Test Generation ==="
echo "Files to process: ${#FILES[@]}"
echo "Iterations per file: $ITERATIONS"
echo ""

COMPLETED=0
FAILED=0

for file in "${FILES[@]}"; do
  echo "----------------------------------------"
  echo "Processing: $file"
  echo "----------------------------------------"

  if "$SCRIPT_DIR/ralph-test-file.sh" "$ITERATIONS" "$file"; then
    ((COMPLETED++))
  else
    ((FAILED++))
    echo "Warning: Failed to complete tests for $file"
  fi

  echo ""
done

echo "========================================"
echo "Batch complete"
echo "Completed: $COMPLETED"
echo "Failed: $FAILED"
echo "========================================"
