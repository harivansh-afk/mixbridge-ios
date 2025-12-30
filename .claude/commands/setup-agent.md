---
description: Analyze codebase and set up the learning agent (run once after install)
allowed-tools: Read, Grep, Glob, Edit
---

# Initial Codebase Assessment

You are setting up the continual learning agent for this codebase. This is a one-time setup that analyzes the project and configures the agent.

## Your Task

### 1. Analyze the Codebase Structure

Explore the project to understand:
- **Directory structure**: What are the key directories and their purposes?
- **Tech stack**: What languages, frameworks, and libraries are used?
- **Configuration files**: Find package.json, tsconfig.json, pyproject.toml, Cargo.toml, etc.
- **Build tools**: How is the project built and tested?
- **Entry points**: Where does the application start?

### 2. Discover Conventions

Look for patterns in the existing code:
- **Code style**: Indentation, naming conventions, file organization
- **Architectural patterns**: MVC, component-based, microservices, etc.
- **Testing patterns**: How are tests structured? What testing frameworks?
- **Documentation patterns**: How is code documented?

### 3. Update the Skill File

Edit `.claude/skills/codebase-agent/SKILL.md` and replace the `## Codebase Context` section with your findings:

```markdown
## Codebase Context

### Architecture
[Brief overview of the architecture]

### Tech Stack
- **Language(s)**: [e.g., TypeScript, Python]
- **Framework(s)**: [e.g., React, FastAPI]
- **Key Libraries**: [important dependencies]

### Key Directories
- `src/` - [purpose]
- `tests/` - [purpose]
- [etc.]

### Build & Test Commands
- Build: `[command]`
- Test: `[command]`
- Lint: `[command]`

### Conventions
- [Convention 1]
- [Convention 2]
```

### 4. Initialize Learnings

Edit `.claude/skills/codebase-agent/learnings.md` and add any initial observations:
- Obvious patterns you notice in the code
- Potential edge cases visible in the structure
- Tech stack insights that would be helpful to remember

## Output

After completing the assessment:
1. Summarize what you learned about the codebase
2. Confirm the skill file has been updated
3. Note any initial learnings added

The agent is now ready for coding. Future sessions will automatically accumulate more learnings!
