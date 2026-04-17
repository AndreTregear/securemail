# Security and Operations

## Security Posture

The platform should be secure by default, but honest about what it does and does not protect.

### v1 Security Guarantees

- TLS for all customer-facing protocols
- encrypted disks on mail and database hosts
- encrypted backups before offsite upload
- password hashing through the mail engine
- private admin surfaces
- per-request audit logging in the control plane
- DKIM, SPF, DMARC support on every active domain

### v1 Non-Guarantees

- end-to-end encrypted mailbox contents
- zero-knowledge mailbox storage
- customer-managed key material

## Identity and Access

### Customer Auth

- superapp auth only
- no direct Mailu admin credentials for customers
- no shell or panel access

### Internal Auth

- admin apps behind Cloudflare Access or equivalent identity-aware proxy
- production admin actions require authenticated operator identity
- sensitive actions require role checks:
- `support`
- `ops`
- `billing_admin`
- `security_admin`

### Authorization Rules

- tenant users can only read or mutate their tenant resources
- internal support can read diagnostics but cannot read mailbox content
- only ops roles can trigger provider-level mutations outside normal flows

## Secrets Management

Current state:

- `.env` and `secrets/` are git-ignored; `.env.example` contains only
  placeholder values with `replace-with-*` markers.
- `scripts/bootstrap.sh` generates strong values for `SECRET_KEY`,
  `API_TOKEN`, and `INITIAL_ADMIN_PW` at setup time and writes them into
  the operator's `.env` file.
- Runtime containers read credentials from that `.env` file via the
  Compose `env_file:` directive.

Required before production:

- move long-lived secrets (Stripe API key, Cloudflare DNS token, admin
  credentials) out of `.env` and into a secret manager (Docker Secrets,
  HashiCorp Vault, or cloud-provider-native) mounted per-container.
- define a rotation schedule and runbook for every long-lived secret.
- never log secrets or include them in audit event payloads.
- encrypted backups — the encryption key lives in the same secret manager
  as runtime secrets and follows the same rotation cadence. Document who
  holds the recovery key and how restores are rehearsed.

The repository does not yet use `sops`. If encrypted-at-rest artifacts
are committed in the future, decide between `sops` (KMS-backed) and
`git-crypt` (symmetric) and land the `.sops.yaml` / `.gitattributes`
config in the same commit so the posture is enforced, not documentary.

## Network Security

Public ingress:

- `443` for superapp
- mail ports on Mailu front only

Private only:

- Postgres
- Redis
- worker dashboards
- Mailu admin/API
- monitoring backends

Host firewall rules:

- deny all by default
- explicit allow-list per role and port

### Backend Transport Encryption

The control-plane stack is not yet committed to `docker-compose.yml`.
When Postgres and Redis are added, they MUST ship with TLS enabled on
the wire, not plaintext over the Docker bridge network:

- Postgres: start with `ssl=on`, mount a server cert/key, and require
  `sslmode=require` (or stricter) in the control-api connection string.
- Redis: use `--tls-port` with a server cert/key; the queue/cache
  clients must connect via `rediss://`.
- Reject `sslmode=disable` and plain `redis://` in non-development
  configuration; the `bootstrap.sh` check should fail if either is
  observed.

Rationale: a single compromised container on the internal network must
not be able to eavesdrop on control-plane queries, steal session state
from Redis, or tamper with enqueued jobs.

### Control Plane Web Controls (apps/control-api)

The API must ship with the following middleware active by default.
These requirements are load-bearing for H8 in
`docs/security-review-2026-04-16.md`:

- **CORS**: allow-list of one or more explicit origins read from
  configuration. Reject `*`. `credentials: true` only when the origin
  is on the allow-list.
- **Security headers** on every response:
  - `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY` (admin surfaces are never framed)
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Content-Security-Policy` set per-surface; the JSON API uses
    `default-src 'none'; frame-ancestors 'none'`.
- **Request limits**: hard-limit body size to 1 MiB at the gateway
  (matches the OpenAPI contract). Reject oversized requests with 413
  before they reach handlers.
- **Rate limiting**: per-tenant (authenticated) and per-IP
  (unauthenticated, e.g. the Stripe webhook) buckets. 100 rps
  sustained / 300 burst per tenant, enforced at the gateway.
- **Auth**: Bearer JWT verification on every endpoint unless the
  OpenAPI spec overrides `security` (currently only the Stripe
  webhook, which validates `Stripe-Signature` instead).
- **Cookies**: none, if possible — the control plane is a pure JSON
  API. If cookies are introduced (session proxy, CSRF double-submit,
  etc.), they MUST set `Secure`, `HttpOnly`, and
  `SameSite=Strict`/`Lax` depending on the flow.

## Host Selection Rules

Do not use a provider that blocks or rate-limits outbound `25` in a way that breaks normal mail delivery.

Minimum requirements:

- static IPv4
- reverse DNS control
- abuse/contact response path
- enough disk IOPS for mail storage
- reliable snapshots or backup tooling

Preferred launch shape:

- dedicated or reserved host for mail
- separate host for app and workers

## Deliverability Controls

- PTR/rDNS matches primary mail transport host
- DKIM enabled for every domain
- SPF published for every domain
- DMARC published for every domain
- `postmaster@` and `abuse@` handled
- outbound rate limits per tenant
- domain warm-up process for new senders
- blocklist monitoring

## Abuse Controls

- per-tenant mailbox count quota
- per-tenant outbound rate limit
- per-mailbox authentication failure counters
- automated suspension on abuse signals
- manual review queue for compromised accounts

## Logging and Auditing

Application logs:

- structured JSON
- request ID on every mutation
- actor ID on every write

Audit events:

- domain created
- verification issued
- domain verified
- domain activated
- mailbox created
- alias created
- password changed
- billing suspension/resume
- support override

Do not log mailbox passwords or reset secrets.

## Monitoring

Metrics:

- mail queue size
- SMTP reject counts
- IMAP auth failures
- disk usage
- backup success age
- TLS certificate expiry
- job queue lag
- domain verification failure rate

Alerts:

- queue backlog exceeds threshold
- backup older than 24h
- cert expiry under 14d
- disk usage over 80%
- mail delivery failures spike
- Postgres replication or health failure

## Backups

Backup scope:

- Postgres
- Mailu mail storage
- Mailu configuration and DKIM material
- audit logs if externalized

Rules:

- encrypted before upload
- at least daily full backup cadence or equivalent snapshot strategy
- retention policy by tier
- monthly restore drill in staging

## Incident Response

Severity levels:

- `sev1`: platform-wide mail outage or data loss risk
- `sev2`: single-tenant outage, provisioning stuck, partial delivery issue
- `sev3`: diagnostics mismatch, delayed onboarding, non-critical bug

Required runbooks:

- mail queue jam
- certificate expiry recovery
- DKIM key rotation
- DNS misconfiguration support
- billing-driven accidental suspension rollback
- compromised mailbox response

## Compliance and Policy

Minimum customer-facing policy set before launch:

- terms of service
- privacy policy
- acceptable use policy
- retention and deletion policy
- DPA if required for your customers

## Launch Gates

- restore drill successful
- sev1 runbook tested
- admin plane private
- blocklist monitoring active
- billing suspend/resume tested
- domain verification retry logic tested
