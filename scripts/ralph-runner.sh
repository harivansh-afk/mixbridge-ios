#!/bin/bash
set -e

# Ralph Runner - Orchestrates test generation in tmux sessions
# Usage: ./ralph-runner.sh [mode]
# Modes: sequential, parallel, interactive

MODE=${1:-interactive}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default iterations per module
ITERATIONS=5

case $MODE in
  sequential)
    # Run all modules one after another in current terminal
    echo "=== Sequential Mode ==="
    echo "Running all modules with $ITERATIONS iterations each"
    echo ""

    for module in setup services models viewmodels utils auth sync db; do
      echo ">>> Starting module: $module"
      "$SCRIPT_DIR/ralph-tests.sh" "$ITERATIONS" "$module"
      echo ">>> Completed: $module"
      echo ""
    done
    ;;

  parallel)
    # Run independent modules in parallel tmux panes
    echo "=== Parallel Mode ==="
    echo "Launching modules in tmux session 'ralph'"

    # Kill existing session if present
    tmux kill-session -t ralph 2>/dev/null || true

    # Create new session with setup first (must complete before others)
    tmux new-session -d -s ralph -n setup \
      "cd $PROJECT_ROOT && $SCRIPT_DIR/ralph-tests.sh $ITERATIONS setup; echo 'Setup done. Press enter to close.'; read"

    echo "Started: setup (window 0)"
    echo "Waiting for setup to complete before launching parallel modules..."
    echo ""
    echo "Run 'tmux attach -t ralph' to monitor"
    echo "Once setup completes, run: ./ralph-runner.sh parallel-modules"
    ;;

  parallel-modules)
    # Launch remaining modules in parallel (run after setup completes)
    echo "=== Launching parallel modules ==="

    # Check if ralph session exists
    if ! tmux has-session -t ralph 2>/dev/null; then
      echo "Error: tmux session 'ralph' not found. Run './ralph-runner.sh parallel' first"
      exit 1
    fi

    # Create windows for each independent module
    for module in services models viewmodels utils auth sync db; do
      tmux new-window -t ralph -n "$module" \
        "cd $PROJECT_ROOT && $SCRIPT_DIR/ralph-tests.sh $ITERATIONS $module; echo '$module done. Press enter.'; read"
      echo "Started: $module"
    done

    echo ""
    echo "All modules launched. Attach with: tmux attach -t ralph"
    echo "Switch windows with: Ctrl+B then number (0-7)"
    ;;

  interactive)
    echo "=== Interactive Mode ==="
    echo ""
    echo "Choose how to run ralph tests:"
    echo ""
    echo "  1) Single module    - Run one module now"
    echo "  2) Sequential       - Run all modules one by one"
    echo "  3) Parallel (tmux)  - Run modules in parallel tmux windows"
    echo "  4) Priority files   - Run tests for priority files only"
    echo "  5) Custom file      - Generate tests for a specific file"
    echo ""
    read -p "Select [1-5]: " choice

    case $choice in
      1)
        echo ""
        echo "Available modules: setup, services, models, viewmodels, utils, auth, sync, db"
        read -p "Module name: " module
        read -p "Iterations (default 5): " iters
        iters=${iters:-5}
        "$SCRIPT_DIR/ralph-tests.sh" "$iters" "$module"
        ;;
      2)
        read -p "Iterations per module (default 5): " iters
        iters=${iters:-5}
        ITERATIONS=$iters $0 sequential
        ;;
      3)
        $0 parallel
        ;;
      4)
        read -p "Iterations per file (default 3): " iters
        iters=${iters:-3}
        "$SCRIPT_DIR/ralph-test-batch.sh" "$iters" --list "$SCRIPT_DIR/test-priority-files.txt"
        ;;
      5)
        read -p "File path (e.g., mixbridge/Services/QueueManager.swift): " filepath
        read -p "Iterations (default 3): " iters
        iters=${iters:-3}
        "$SCRIPT_DIR/ralph-test-file.sh" "$iters" "$filepath"
        ;;
      *)
        echo "Invalid choice"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage: $0 [sequential|parallel|parallel-modules|interactive]"
    exit 1
    ;;
esac
