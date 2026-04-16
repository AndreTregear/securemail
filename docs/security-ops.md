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

- Mailu admin credentials stored in environment or secret manager, never in code
- Stripe secrets in secret manager
- backup keys encrypted and rotated
- repository uses `sops` or equivalent for static encrypted secrets
- no plaintext secrets in logs or audit event payloads

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
