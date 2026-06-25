# Security Universals

> **Purpose:** Five rules every code-reviewer applies before tech-specific checks.
> **Used By:** code-reviewer (primary), code-simplifier, code-documenter
> **Confidence Required:** 0.95
> **Last Updated:** auto-installed by `install-closers.sh`

## Overview

Cross-tech security baseline that the code-reviewer enforces regardless of language.
A leaked secret is a BLOCKER in Python, TypeScript, SQL, or shell. SQL injection is
a BLOCKER whether the SQL is hand-built strings or `f"SELECT * FROM users WHERE id = {id}"`.
Auth bypass is a BLOCKER whether the framework is FastAPI, Express, or a custom router.

These five rules apply first, before any tech-specific lint or convention. The tech KB
adds language-specific patterns (e.g. SQLAlchemy parameter binding, React XSS escaping),
but the universals are non-negotiable.

## The five universals

### 1. No secrets in code

Hardcoded credentials are a BLOCKER. No exceptions.

**Includes:** API keys, OAuth tokens, JWT signing keys, DB passwords, AWS access keys,
private keys, webhook secrets, encryption keys, session secrets.

**Detection:**
- Long random-looking strings (≥ 16 chars, mixed alphanumeric).
- Variables named `*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_DSN`.
- Strings matching common provider prefixes (`sk_`, `pk_`, `AKIA`, `ghp_`, `gho_`, `xoxb-`, `xoxp-`).
- `.env` files committed to the repo.

**Correct approach:** Read from env vars (`os.environ`, `process.env`) loaded via
`.env` (never committed) or a secrets manager (Infisical, AWS Secrets Manager, Vault).
Cite `.env.example` as the contract.

**If a secret leaked in git history:** It's compromised. Rotate immediately. Cleaning
git history doesn't un-leak it.

### 2. No untrusted input concatenated into queries or commands

User-controlled strings interpolated into SQL, shell, LDAP, XPath, or any other parser
is injection. BLOCKER.

**Forms:**
- SQL: `f"SELECT * FROM t WHERE id = {user_id}"` — even if `user_id` "looks like an int".
- Shell: `subprocess.run(f"ls {path}", shell=True)`, `exec("rm -rf " + dir)`.
- NoSQL: `db.users.find({"$where": user_query})`.
- LDAP / XPath / XML: same shape, same risk.
- Template engines with autoescape disabled and user input.

**Correct approach:** Parameter binding (`?` / `$1` / `:name`), argv-style subprocess
(`subprocess.run([cmd, arg1, arg2])`), validated allowlists. The tech KB names the right
binding API for that stack.

### 3. Auth check on every privileged path — never opt-in

Every endpoint, mutation, RPC, or admin path must verify caller identity AND authorization.
Forgetting the check is a BLOCKER. Opt-in auth ("we'll add it later") is a BLOCKER.

**Detection:**
- Routes / handlers without an auth decorator or middleware.
- Mutations that read user ID from request body instead of session.
- "Internal" endpoints that aren't network-isolated.
- Admin paths gated only by URL obscurity.

**Correct approach:** Auth is middleware/decorator-driven so a new endpoint is authed by
default. Authorization (what the authed user can do) is checked at the resource layer,
not the route layer. Tests cover the "unauthenticated caller gets 401" case explicitly.

### 4. Validate input at the boundary, trust it within

Input from the network, the filesystem, env vars, or any external source is untrusted
until validated. Validation happens once, at the boundary; downstream code trusts the
typed value.

**Detection:**
- Pydantic / Zod / DTO models bypassed via `dict(request.json)`.
- File paths from user input passed to `open()` without normalization (path traversal).
- URLs from user input fetched without scheme/host allowlist (SSRF).
- Integers parsed without range checks where range matters (memory, time, money).
- File uploads without size, type, and content-type validation.

**Correct approach:** Schema validation at the edge (Pydantic, Zod, JSON Schema). Once
past the boundary, the type system carries the guarantee. Re-validation downstream is
a smell — it usually means the boundary leaks.

### 5. Errors must not leak secrets, internals, or PII

Stack traces, error messages, and logs are an information disclosure surface. Leaking
DB schema, file paths, env vars, or user data is a BLOCKER for anything user-facing.

**Detection:**
- Raw `Exception` rendered to the user.
- 500 pages including stack traces in production.
- Logs that dump request bodies including passwords or tokens.
- Error messages that confirm vs deny a username ("invalid password" vs "no such user").
- PII (email, phone, full name) in unstructured logs without redaction.

**Correct approach:** Surface a generic error to the user, log the full context server-side
with redaction. Authentication errors are always the same message regardless of which
half failed. Logs go through a redactor that masks tokens and PII.

## Severity rubric

| Finding | Severity | Notes |
|---------|----------|-------|
| Hardcoded production secret | BLOCKER | Plus rotation required |
| Hardcoded test/example secret in test file | NIT | If clearly fake and isolated to tests |
| SQL injection in user-facing path | BLOCKER | No exceptions |
| SQL injection in internal/admin path | BLOCKER | "Internal" is not a defense |
| Missing auth on mutation endpoint | BLOCKER | |
| Missing input validation at boundary | IMPORTANT | BLOCKER if it enables injection / traversal / SSRF |
| Stack trace leak in production response | IMPORTANT | BLOCKER if it reveals secrets |
| PII in unredacted logs | IMPORTANT | BLOCKER under GDPR / HIPAA / similar regime |

## When this applies

- Every diff the reviewer touches. Always. First read, before tech-specific checks.
- Every simplification — a "simplification" that drops a validation step is a vulnerability.

## When this does NOT apply

- Pure documentation changes.
- Generated files where the generator is the actual surface to review.
- Test fixtures with clearly fake secrets (but flag if a fake secret looks real enough to be reused).

## Related

- [comments](comments.md) — security boundaries deserve a `# validated upstream` comment
- [dead-code](dead-code.md) — dead auth code is a risk, not a cleanup target
