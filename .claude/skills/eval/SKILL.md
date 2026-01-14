---
name: eval
description: Generate evaluation specs with building and verification criteria. Use when setting up features, defining acceptance criteria, or before implementing anything significant. Triggers on "create evals", "set up verification", "define acceptance criteria", or "build [feature]".
allowed-tools: Read, Grep, Glob, Write, Edit
---

# Eval Skill

Generate specs that define **what to build** and **how to verify it**.

## Output

I create `.claude/evals/<name>.yaml` with two sections:

1. **building_spec** — What the builder agent implements
2. **verification_spec** — What the verifier agent checks

## Format

```yaml
name: feature-name
description: One-line summary

building_spec:
  description: What to build
  requirements:
    - Requirement 1
    - Requirement 2
  constraints:
    - Constraint 1
  files:
    - suggested/file/paths.ts

test_output:
  framework: pytest | vitest | jest
  path: tests/generated/

verification_spec:
  # Deterministic checks
  - type: command
    run: "npm test"
    expect: exit_code 0
    
  # Agent checks
  - type: agent
    name: check-name
    prompt: |
      What to verify
    evidence:
      - screenshot: name
      - url: contains "pattern"
    generate_test: true
```

## Workflow

### User Request

```
Create evals for user authentication
```

### My Questions

Before generating, I ask:
1. What auth method? (email/password, OAuth, magic link?)
2. UI, API, or both?
3. Specific security requirements?

### My Output

`.claude/evals/auth.yaml`:

```yaml
name: auth
description: Email/password authentication with UI and API

building_spec:
  description: |
    User authentication system with email/password.
    Secure password storage, JWT tokens, login/signup flows.
  requirements:
    - Password hashing with bcrypt (cost factor 12+)
    - JWT tokens with 24h expiry
    - POST /api/auth/login endpoint
    - POST /api/auth/signup endpoint
    - Login page at /login
    - Signup page at /signup
    - Protected route middleware
  constraints:
    - No plaintext passwords anywhere
    - Tokens must be httpOnly cookies or secure headers
  files:
    - src/auth/password.ts
    - src/auth/jwt.ts
    - src/auth/middleware.ts
    - src/routes/auth.ts
    - src/pages/login.tsx
    - src/pages/signup.tsx

test_output:
  framework: pytest
  path: tests/generated/

verification_spec:
  # --- Deterministic ---
  - type: command
    run: "npm test -- --grep auth"
    expect: exit_code 0
    
  - type: file-contains
    path: src/auth/password.ts
    pattern: "bcrypt"
    
  - type: file-not-contains
    path: src/
    pattern: "password.*=.*plaintext"

  # --- Agent: API ---
  - type: agent
    name: api-login
    prompt: |
      Test login API:
      1. POST /api/auth/signup with new user
      2. Verify 201 response
      3. POST /api/auth/login with same creds
      4. Verify 200 with JWT token
      5. POST /api/auth/login with wrong password
      6. Verify 401 with helpful message
    evidence:
      - response: status 201
      - response: status 200
      - response: has "token"
      - response: status 401
    generate_test: true

  # --- Agent: UI ---
  - type: agent
    name: ui-login
    prompt: |
      Test login UI:
      1. Go to /login
      2. Verify form has email + password fields
      3. Submit with valid credentials
      4. Verify redirect to /dashboard
      5. Verify welcome message visible
    evidence:
      - screenshot: login-page
      - screenshot: after-login
      - url: contains "/dashboard"
      - element: '[data-testid="welcome"]'
    generate_test: true

  # --- Agent: Security ---
  - type: agent
    name: password-security
    prompt: |
      Verify password security:
      1. Read src/auth/password.ts
      2. Confirm bcrypt with cost >= 12
      3. Confirm no password logging
      4. Check signup doesn't echo password
    evidence:
      - text: "bcrypt"
      - text: "cost" or "rounds"
    generate_test: false  # Code review, not repeatable test
```

## Check Types

### Deterministic

```yaml
- type: command
  run: "shell command"
  expect: exit_code 0

- type: command
  run: "curl localhost:3000/health"
  expect:
    contains: '"ok"'

- type: file-exists
  path: src/file.ts

- type: file-contains
  path: src/file.ts
  pattern: "regex pattern"

- type: file-not-contains
  path: src/file.ts
  pattern: "bad pattern"
```

### Agent

```yaml
- type: agent
  name: descriptive-name  # Used for evidence/test naming
  prompt: |
    Step-by-step verification
  evidence:
    - screenshot: step-name
    - url: contains "pattern"
    - element: "css-selector"
    - text: "expected text"
    - response: status 200
    - response: has "field"
  generate_test: true | false
```

## Best Practices

### Building Spec

- **Be specific** — "bcrypt with cost 12" not "secure passwords"
- **List files** — helps builder know where to put code
- **State constraints** — what NOT to do matters

### Verification Spec

- **Deterministic first** — fast, reliable checks
- **Agent for semantics** — UI flows, code quality, error messages
- **Evidence always** — no claim without proof
- **generate_test for repeatables** — UI flows yes, code review no

### Naming

- `name: feature-name` — lowercase, hyphens
- `name: api-login` — for agent checks, descriptive

## What Happens Next

After I create the spec:

```
/eval build auth
```

1. Builder agent reads `building_spec`, implements
2. Verifier agent reads `verification_spec`, checks
3. If fail → builder gets feedback → fixes → verifier re-checks
4. Loop until pass
5. Agent checks become tests in `tests/generated/`
