# Security Review — 2026-04-16

**Scope:** Initial audit of the public repository at `github.com/AndreTregear/securemail` (commit `f1ecb77`). The stack is a self-hosted Mailu-based mail platform with a control plane API, SQL schema, worker services, shell provisioning scripts, an MCP server, Docker Compose setup, and OpenAPI definitions.

**Risk framing:** blast radius is high — the project provisions email infrastructure, handles PII, credentials, DNS, and TLS, and is multi-tenant.

**Total findings:** 30 (4 Critical, 9 High, 7 Medium, 10 Low).

---

## Critical

### C1. Session cookies sent over HTTP by default
- **Location:** `.env.example:33`
- **Problem:** `SESSION_COOKIE_SECURE=False`. Mailu admin sessions are sent without the `Secure` flag, so they travel in cleartext on any HTTP leg.
- **Impact:** Admin session theft → full platform takeover (users, domains, billing).
- **Fix:** Default to `True`. Document that HTTP-only deployments are unsupported.

### C2. Hardcoded `andre` principal in schema and docs
- **Location:** `openapi/control-plane.yaml:76`, `docs/data-model.md:284-286`
- **Problem:** `primaryMailboxLocalpart` defaults to `andre`, and the onboarding template hardcodes `andre@domain` as the primary mailbox and alias target.
- **Impact:** Leaks author PII in a public repo; encourages operators to ship platforms with a predictable default admin name, aiding targeted phishing.
- **Fix:** Remove the default. Require the caller to supply a value or use a neutral placeholder.

### C3. Unbounded filter arguments to Mailu CLI via MCP
- **Location:** `mcp-server.js:307-309`
- **Problem:** `mailu_config_export` pushes `args.filters` directly to `flask mailu config-export`. While `execFileSync` blocks shell injection, the Mailu CLI will honor any filter name, including wildcards that can combine with `--secrets` to dump sensitive config.
- **Impact:** Information disclosure and DoS via malformed filters.
- **Fix:** Whitelist known filter tokens before passing them through.

### C4. Raw docker stderr leaked to MCP client
- **Location:** `mcp-server.js:350-359`
- **Problem:** On error, the MCP server returns `error.message` verbatim. `execFileSync` embeds stderr in `error.message`, so any path, env variable, or secret docker prints on failure is forwarded to the caller.
- **Impact:** Credential and internal-path disclosure.
- **Fix:** Return a generic error to the client; log details to stderr for operators.

---

## High

### H1. No auth scheme declared in OpenAPI spec
- **Location:** `openapi/control-plane.yaml`
- **Problem:** No `components.securitySchemes` and no `security:` blocks on any endpoint.
- **Impact:** When the API is implemented, scaffolding will be copied without auth; multi-tenant isolation becomes the first regression.
- **Fix:** Declare `BearerAuth` (or mTLS) in `securitySchemes` and apply a default `security:` list at the spec root.

### H2. Stripe webhook endpoint has no signature contract
- **Location:** `openapi/control-plane.yaml:313-320`
- **Problem:** `/v1/billing/webhooks/stripe` has no `requestBody` schema and no mention of `Stripe-Signature` verification.
- **Impact:** Forged webhook events can flip subscription state (suspend paying tenants, upgrade free ones).
- **Fix:** Require the `Stripe-Signature` header in the spec; implement HMAC verification with the webhook secret before processing.

### H3. Container images pinned by tag, not digest
- **Location:** `docker-compose.yml` (all Mailu services), `.env.example:62`
- **Problem:** Images use `${MAILU_VERSION:-2024.06.49}` and `CERTBOT_IMAGE_TAG=latest`. Tags can be moved; `latest` will silently drift.
- **Impact:** Supply-chain compromise or broken certbot renewals if upstream images change.
- **Fix:** Pin to `@sha256:...` digests or at minimum a specific certbot version tag.

### H4. No row-level security in Postgres
- **Location:** `sql/control-plane.sql`
- **Problem:** Tenant isolation is entirely application-layer. No `ENABLE ROW LEVEL SECURITY` on any table.
- **Impact:** A single forgotten `WHERE tenant_id = ?` leaks every tenant's data.
- **Fix:** Enable RLS on tenant-scoped tables; bind policies to a session variable set by the API.

### H5. Plaintext secrets in `.env`, docs claim SOPS
- **Location:** `.env.example`, `docs/security-ops.md:52`
- **Problem:** Secrets live in `.env` with no rotation story. The security doc asserts "repository uses `sops` or equivalent," but SOPS is not configured.
- **Impact:** Doc/reality mismatch; operators may assume encryption-at-rest they don't have.
- **Fix:** Either implement SOPS (commit `.sops.yaml`, encrypt `.env.example`) or correct the doc and describe the real mechanism (secret manager, Docker secrets, K8s secrets).

### H6. `mailu_logs` service name not whitelisted
- **Location:** `mcp-server.js:223-229`
- **Problem:** Caller-supplied `args.service` is passed to `docker compose logs`. Safe from shell injection, but unconstrained service names let a caller probe the stack topology via errors.
- **Fix:** Whitelist `['redis','front','admin','imap','smtp','oletools','antispam','webmail']`.

### H7. No rate limiting or request-size bounds in OpenAPI
- **Location:** `openapi/control-plane.yaml`
- **Problem:** No `maxItems`/`maxLength` on request schemas; no documented rate limits.
- **Impact:** Trivial DoS via giant payloads or rapid-fire job-enqueue endpoints.
- **Fix:** Bound array/string lengths in schemas; document per-tenant rate limits and enforce them in middleware.

### H8. No CORS or security-header guidance for control-api
- **Location:** `apps/control-api/*`, `openapi/control-plane.yaml`
- **Problem:** Nothing pins down CORS origins or default security headers (CSP, X-Frame-Options, HSTS, nosniff).
- **Impact:** An overly permissive CORS default or missing clickjacking protection ends up in production.
- **Fix:** In `apps/control-api`, allowlist a single origin from env, set security headers globally.

### H9. No TLS on internal backends
- **Location:** `docker-compose.yml`
- **Problem:** Postgres and Redis ride the compose network in plaintext.
- **Impact:** Container compromise → eavesdrop on queries, steal Redis-stored tokens, tamper with jobs.
- **Fix:** Enable TLS on Redis (`--tls-port`) and Postgres (`ssl=on`); require SSL in the control-api connection string.

---

## Medium

### M1. Cloudflare tunnel → localhost via HTTP
- **Location:** `cloudflared-webmail.example.yml:6`
- **Problem:** `service: http://localhost:8080`. Combined with `SESSION_COOKIE_SECURE=False`, session cookies cross the loopback unencrypted.
- **Fix:** Point the tunnel at `https://localhost:8443` (Mailu front TLS) or accept the tunnel as the security boundary explicitly.

### M2. `mailu_domain_add` skips domain validation
- **Location:** `mcp-server.js:235`
- **Problem:** `args.domain` is passed straight to `flask mailu domain`. Mailu may accept malformed names.
- **Fix:** Validate with `^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$` before calling out.

### M3. Shell scripts source `.env` without validating values
- **Location:** `scripts/bootstrap.sh`, `scripts/provision-cert.sh`, `scripts/renew-cert.sh`
- **Problem:** Variables are used unquoted after `source .env`; a malicious `.env` can smuggle shell metacharacters.
- **Fix:** Quote every expansion; validate format of `DOMAIN`, `HOSTNAMES`, `CERTBOT_EMAIL`, etc. post-sourcing.

### M4. `HTTP_BIND_HOST=0.0.0.0` allowed
- **Location:** `docker-compose.yml:16`, `.env.example:10`
- **Problem:** Default is `127.0.0.1` (good), but nothing stops an operator from exposing admin directly.
- **Fix:** Add a bootstrap-time refusal if `HTTP_BIND_HOST != 127.0.0.1`.

### M5. `audit_events` table is not DB-enforced append-only
- **Location:** `sql/control-plane.sql:171-183`
- **Problem:** Append-only is a convention, not a constraint. A compromised admin role can rewrite audit history.
- **Fix:** Create a trigger or revoke UPDATE/DELETE on `audit_events` from the application role.

### M6. Weak validation on generated passwords
- **Location:** `scripts/bootstrap.sh:35-41`
- **Problem:** `openssl rand -base64 24 | tr -d '\n' | tr '/+' '_-'` can produce characters (`=`, quotes) that bite during shell-sourced `.env` parsing.
- **Fix:** Use `openssl rand -hex 24`.

### M7. Docs promise SOPS, backups encryption that aren't wired up
- **Location:** `docs/security-ops.md:52,161-169`
- **Problem:** Same theme as H5 — claims outrun implementation for backups and secret storage.
- **Fix:** Either implement or scope the docs back to the current reality with a roadmap note.

---

## Low

### L1. Hardcoded `andre` in onboarding template text
- **Location:** `docs/data-model.md:284`
- **Fix:** Replace with `{primary_user}@domain` placeholder.

### L2. `MAILU_ROOT` silently falls back to `__dirname`
- **Location:** `mcp-server.js:7`
- **Fix:** Require `MAILU_ROOT`; exit with a clear error if unset.

### L3. Error strings leak absolute paths
- **Location:** `scripts/bootstrap.sh:10,52`
- **Fix:** Use relative paths in user-facing messages.

### L4. `.gitignore` misses common `.env` variants
- **Location:** `.gitignore:1`
- **Fix:** Add `.env.local`, `.env.*.local`, `.env.production`.

### L5. README teaches passing passwords on the command line
- **Location:** `README.md:99-100`
- **Fix:** Recommend interactive `read -s` entry or stdin.

### L6. `provision-cert.sh` doesn't validate `HOSTNAMES` entries
- **Location:** `scripts/provision-cert.sh:33-38`
- **Fix:** Regex-validate each domain after splitting on comma.

### L7. No `healthcheck:` on any compose service
- **Location:** `docker-compose.yml`
- **Fix:** Add HTTP healthchecks on `admin` and `front`, socket checks on `redis`/`imap`/`smtp`.

### L8. Backup key management not documented
- **Location:** `docs/security-ops.md:161-169`
- **Fix:** Document where backup keys live, who rotates, and how restores are tested.

### L9. No lockfile committed
- **Location:** repo root
- **Fix:** Commit `pnpm-lock.yaml` (or `package-lock.json`) so builds are reproducible and auditable.

### L10. OpenAPI example uses the author's first name
- **Location:** `openapi/control-plane.yaml:76`
- **Fix:** Same change as C2.

---

## Triage

**Fix immediately (blocking public use):** C1–C4, H1, H2, H3, H5.

**Before first tenant:** H4, H6–H9, M1, M2, M4, M5.

**Operational hardening:** all Medium/Low items as time permits.
