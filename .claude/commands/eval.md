---
description: Eval commands - list, show, build, verify
argument-hint: list | show <name> | build <name> | verify <name>
allowed-tools: Read, Bash, Task
---

# /eval Command

## Commands

### /eval list

List all evals:
```
Available evals:
  auth         Email/password authentication
  checkout     E-commerce checkout flow
```

### /eval show <name>

Display the full eval spec.

### /eval build <name>

**The main command.** Orchestrates build → verify → fix loop.

```
/eval build auth
```

Flow:
1. Spawn **eval-builder** with building_spec
2. Builder implements, returns
3. Spawn **eval-verifier** with verification_spec
4. Verifier checks, returns pass/fail
5. If fail → spawn builder with failure context → goto 3
6. If pass → done

Output:
```
🔨 Building: auth
═══════════════════════════════════════

[Builder] Implementing...
  + src/auth/password.ts
  + src/auth/jwt.ts
  + src/routes/auth.ts

[Verifier] Checking...
  ✅ command: npm test (exit 0)
  ✅ file-contains: bcrypt
  ❌ api-login: Wrong status code
     Expected: 401 on bad password
     Actual: 500

[Builder] Fixing api-login...
  ~ src/routes/auth.ts

[Verifier] Re-checking...
  ✅ command: npm test (exit 0)
  ✅ file-contains: bcrypt
  ✅ api-login: Correct responses
     📄 Test: tests/generated/test_auth_api_login.py

═══════════════════════════════════════
📊 Build complete: 3/3 checks passed
   Iterations: 2
   Tests generated: 1
```

### /eval verify <name>

Just verify, don't build. For checking existing code.

```
/eval verify auth
```

Spawns verifier only. Reports pass/fail with evidence.

### /eval verify

Run all evals:
```
/eval verify
```

### /eval evidence <name>

Show collected evidence:
```
Evidence: auth
  - api-login-001.png
  - ui-login-001.png
  - evidence.json
```

### /eval tests

List generated tests:
```
Generated tests:
  tests/generated/test_auth_api_login.py
  tests/generated/test_auth_ui_login.py
```

### /eval clean

Remove evidence and generated tests.

## Orchestration Logic

For `/eval build`:

```python
max_iterations = 5
iteration = 0

# Initial build
builder_result = spawn_agent("eval-builder", {
    "spec": f".claude/evals/{name}.yaml",
    "task": "implement"
})

while iteration < max_iterations:
    # Verify
    verifier_result = spawn_agent("eval-verifier", {
        "spec": f".claude/evals/{name}.yaml"
    })
    
    if verifier_result.all_passed:
        return success(verifier_result)
    
    # Fix failures
    builder_result = spawn_agent("eval-builder", {
        "spec": f".claude/evals/{name}.yaml",
        "task": "fix",
        "failures": verifier_result.failures
    })
    
    iteration += 1

return failure("Max iterations reached")
```

## Context Flow

```
Main Claude
    │
    ├─→ Builder (context: building_spec only)
    │   └─→ Returns: files created
    │
    ├─→ Verifier (context: verification_spec only)
    │   └─→ Returns: pass/fail + evidence
    │
    └─→ Builder (context: building_spec + failure only)
        └─→ Returns: files fixed
```

Each agent gets minimal, focused context. No bloat.
