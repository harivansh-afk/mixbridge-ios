---
description: Implement iOS/SwiftUI features from eval specs with automatic verification
argument-hint: <eval-name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task
---

# /implement Command

Implement iOS features from eval specs. Spawns verifier agent for checking - never tests own work.

## Usage

```
/implement <eval-name>
```

## Flow

```
Read eval spec -> Check SwiftUI guide -> Implement -> Spawn verifier -> Fix if needed -> Done
```

## Process

### 1. Load Eval Spec

Read `.claude/evals/<name>.yaml` and extract `building_spec`:
- description
- requirements
- constraints
- files

If no eval exists:
```
No eval spec found for "<name>".
Create one first with: /eval <name>
```

### 2. Check SwiftUI Guide

Read `.claude/axiom-skills-guide.md` for:
- Project-specific iOS patterns
- Architecture preferences
- SwiftUI conventions

If missing, use standard SwiftUI best practices.

### 3. Implement

Build the feature following the spec. iOS/SwiftUI guidelines:
- `@State`, `@Binding`, `@ObservedObject` appropriately
- `async/await` over completion handlers
- `@MainActor` for UI updates
- Small, composable Views
- Proper error handling

### 4. Spawn Verifier (MANDATORY)

**NEVER verify own work.** Always spawn eval-verifier agent:

```python
verifier_result = spawn_agent("eval-verifier", {
    "spec": f".claude/evals/{name}.yaml"
})
```

The verifier:
- Runs all checks from `verification_spec`
- Collects evidence
- Reports pass/fail

### 5. Handle Results

**Pass:** Report success and files changed.

**Fail:** Read failure feedback, fix specific issues, re-spawn verifier.

Max 5 iterations.

## Orchestration Logic

```python
max_iterations = 5
iteration = 0

# Read spec
spec = read_yaml(f".claude/evals/{name}.yaml")
guide = read_file(".claude/axiom-skills-guide.md")  # optional

# Implement
implement(spec.building_spec, guide)

while iteration < max_iterations:
    # ALWAYS spawn verifier - never test own work
    verifier_result = spawn_agent("eval-verifier", {
        "spec": f".claude/evals/{name}.yaml"
    })

    if verifier_result.all_passed:
        return success(verifier_result)

    # Fix failures
    fix_issues(verifier_result.failures)
    iteration += 1

return failure("Max iterations reached")
```

## Output

```
/implement auth
---

[Loading eval spec: .claude/evals/auth.yaml]

Building Spec:
  - Login view with email/password
  - Async authentication service
  - Error handling with alerts

[Checking .claude/axiom-skills-guide.md...]

[Implementing...]

Files Created:
  + Sources/Features/Auth/LoginView.swift
  + Sources/Features/Auth/AuthViewModel.swift
  + Sources/Services/AuthService.swift

Files Modified:
  ~ Sources/App/ContentView.swift

[Spawning eval-verifier...]

Verification:
  ✅ file-exists: LoginView.swift
  ✅ file-contains: @MainActor
  ✅ ui-login: Form renders correctly
     📸 Evidence: 2 screenshots

---
Implementation complete: 3/3 checks passed
```

## Critical Rules

1. **NEVER test own work** - always spawn eval-verifier
2. **NEVER skip verification** - even if "confident"
3. **NEVER claim pass without verifier confirmation**
4. **Read the spec** - don't assume requirements
5. **Minimal fixes** - on retry, fix only what failed

