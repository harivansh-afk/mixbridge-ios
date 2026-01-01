#!/bin/bash
# SessionEnd Hook - Triggers learning extraction
#
# This hook runs automatically after each Claude Code session.
# It spawns a background process to analyze the session and update learnings.
#

LOG_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/session-end.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Read hook input from stdin (JSON with session info)
INPUT=$(cat)

log "Hook triggered with input: $INPUT"

# Extract transcript path using jq (required dependency)
if ! command -v jq &> /dev/null; then
    log "ERROR: jq not available"
    exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

log "Transcript: $TRANSCRIPT"
log "Session ID: $SESSION_ID"
log "Project dir: $PROJECT_DIR"

# Validate transcript exists
if [ -z "$TRANSCRIPT" ]; then
    log "ERROR: No transcript path in input"
    exit 0
fi

if [ ! -f "$TRANSCRIPT" ]; then
    log "ERROR: Transcript file does not exist: $TRANSCRIPT"
    exit 0
fi

# Only run retrospective if session was substantial (more than 10 lines)
LINE_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "0")
log "Transcript line count: $LINE_COUNT"
if [ "$LINE_COUNT" -lt 10 ]; then
    log "Session too short, skipping retrospective"
    exit 0
fi

# Check if learnings.md exists (system is properly set up)
LEARNINGS_FILE="$PROJECT_DIR/.claude/skills/codebase-agent/learnings.md"
if [ ! -f "$LEARNINGS_FILE" ]; then
    log "ERROR: learnings.md not found at $LEARNINGS_FILE"
    exit 0
fi

log "Starting retrospective analysis in background..."

# Run retrospective in background using the /retrospective slash command
# Pass transcript path as argument so the command knows where to read the session
# Use nohup to ensure the process survives after hook exits
(
    cd "$PROJECT_DIR" && nohup claude --dangerously-skip-permissions \
        -p "/retrospective

The session transcript is at: $TRANSCRIPT
Read it to understand what happened in this session." \
        >> "$LOG_FILE" 2>&1 &
) &

log "Background process spawned"

# Exit immediately - don't wait for background process
exit 0
