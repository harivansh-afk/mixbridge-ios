---
description: Analyze the current session and extract learnings to memory
allowed-tools: Read, Edit
---

# Session Retrospective

Analyze this coding session and extract valuable learnings to improve future sessions.

## Your Task

### 1. Review What Happened This Session

Reflect on the session:
- What code was written or modified?
- What problems were solved?
- What approaches were tried (both successful and unsuccessful)?
- Were there any surprises or unexpected behaviors?

### 2. Identify Learnings

Extract insights in these categories:

**Patterns (what worked well)**:
- Successful approaches that should be reused
- Code patterns that solved problems effectively
- Workflows that were efficient

**Failures (what to avoid)**:
- Approaches that didn't work
- Bugs that were encountered and their root causes
- Time wasted on wrong paths
- Assumptions that turned out to be wrong

**Edge Cases**:
- Tricky scenarios discovered
- Non-obvious behavior found
- Boundary conditions that matter

**Technology Insights**:
- Framework/library-specific knowledge gained
- API quirks discovered
- Performance considerations learned

### 3. Update learnings.md

Edit `.claude/skills/codebase-agent/learnings.md` and add new entries under the appropriate sections.

Use this format for each entry:

```markdown
### [Short Descriptive Title]
- **Context**: When does this apply?
- **Learning**: What is the insight?
- **Example**: (optional) Code snippet or concrete example
- **Session**: [Date or brief session description]
```

### 4. Quality Guidelines

Be selective about what to add:
- **Add** genuinely useful, project-specific insights
- **Skip** general programming knowledge (things any developer would know)
- **Skip** one-time fixes that won't recur
- **Avoid** duplicating existing entries
- **Merge** with existing entries if they're related

## Output

Summarize:
1. How many learnings were added (and to which categories)
2. Brief description of the most important insights
3. Any patterns emerging across sessions
