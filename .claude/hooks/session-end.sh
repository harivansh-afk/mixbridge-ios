#!/bin/bash
# SessionEnd Hook - Triggers learning extraction
#
# This hook runs automatically after each Claude Code session.
# It spawns a background process to analyze the session and update learnings.
#

# Read hook input from stdin (JSON with session info)
INPUT=$(cat)

# Extract transcript path using jq (required dependency)
if ! command -v jq &> /dev/null; then
    # jq not available, skip silently
    exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Validate transcript exists
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# Only run retrospective if session was substantial (more than 10 lines)
LINE_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "0")
if [ "$LINE_COUNT" -lt 10 ]; then
    exit 0
fi

# Check if learnings.md exists (system is properly set up)
LEARNINGS_FILE="$PROJECT_DIR/.claude/skills/codebase-agent/learnings.md"
if [ ! -f "$LEARNINGS_FILE" ]; then
    exit 0
fi

# Run retrospective in background using claude -p
# This uses Claude Code's existing authentication
(
    claude -p "Run /retrospective to analyze the session and extract learnings. The session transcript is at: $TRANSCRIPT" \
        --cwd "$PROJECT_DIR" \
        2>/dev/null
) &

# Exit immediately - don't wait for background process
exit 0
