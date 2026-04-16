# Control Plane Architecture

## Objective

Build a production-grade, multi-tenant email platform for non-technical customers where:

- customers use their own domain
- customers do not provide DNS API credentials
- customers manually add a small DNS record set once
- your superapp is the only customer-facing UI and API
- the mail engine is self-hosted
- internal admin surfaces are not public

The first production backbone is `Mailu`, wrapped by a platform control plane you own.

## Product Definition

The product is not "sell raw mailbox hosting." The product is:

- guided domain onboarding
- shared mail infrastructure
- mailbox and alias lifecycle management
- billing and suspension
- DNS verification and diagnostics
- one clean customer experience inside the superapp

The recommended launch offer is:

- 1 primary mailbox per tenant by default
- aliases such as `info@domain` and `contact@domain`
- IMAP/SMTP/webmail
- optional higher tiers for more inboxes and storage

## Guiding Constraints

- No customer Cloudflare token or DNS provider token in v1
- No customer access to Mailu admin in v1
- No Cloudflare Tunnel for SMTP or IMAP
- Shared platform hostnames for transport in v1
- Manual DNS onboarding with automated verification
- Per-tenant auditability from day one

## System Topology

```text
Customer Browser
    |
    v
Superapp Web / API
    |
    +------------------------------+
    |                              |
    v                              v
Control Plane API              Billing Worker
    |                              |
    v                              v
Postgres <-----> Redis/BullMQ <----+-----> Stripe
    |
    +--------------------+
    |                    |
    v                    v
Provisioner Worker   DNS Verifier Worker
    |                    |
    v                    v
Mailu Adapter         Recursive DNS Checks
    |
    v
Mailu Admin/API/CLI
    |
    v
SMTP / IMAP / Webmail
```

## Trust Boundaries

### Customer Plane

- customer dashboard
- onboarding wizard
- mailbox settings
- billing pages

Customers only interact with your superapp.

### Control Plane

- tenant records
- domain states
- mailbox and alias metadata
- audit trail
- provisioning jobs

This plane owns lifecycle and orchestration.

### Mail Plane

- Mailu services
- SMTP, IMAP, submission
- DKIM keys
- per-domain mail delivery state

This plane stores and processes email.

### Ops Plane

- internal dashboards
- Mailu admin access
- worker dashboards
- logs, metrics, backup consoles

This plane stays private behind Cloudflare Access or equivalent.

## Component Responsibilities

### 1. Superapp Web

Responsibilities:

- onboarding UX
- DNS instructions
- mailbox and alias management
- billing UX
- support-visible diagnostics

Do not let the web app talk to Mailu directly.

### 2. Control Plane API

Recommended stack:

- Node 22
- TypeScript
- Express
- Postgres
- Redis + BullMQ

Responsibilities:

- validate requests
- persist desired state
- enqueue idempotent provisioning jobs
- return current resource state
- expose internal admin APIs later

### 3. Provisioner Worker

Responsibilities:

- create domains in Mailu
- create mailboxes and aliases
- rotate passwords
- suspend/reactivate tenants
- reconcile drift between Postgres and Mailu

This worker is the only service that should hold Mailu administrative credentials.

### 4. DNS Verifier Worker

Responsibilities:

- check TXT verification records
- verify MX/SPF/DKIM/DMARC propagation
- verify optional autoconfig/autodiscover records
- update diagnostic status with clear user-facing messages

### 5. Billing Worker

Responsibilities:

- sync Stripe subscription state
- enforce trial expiry and delinquency rules
- trigger grace period, suspend, and resume flows

### 6. Mailu

Responsibilities:

- actual mail transport and storage
- mailbox authentication
- IMAP/SMTP service
- webmail
- DKIM and mail-specific configuration export

Mailu is a mail engine, not the customer product surface.

## Domain and Mail Flow

### Customer DNS Flow

1. Customer enters `customer.com`
2. Platform generates a verification TXT record
3. Customer adds the TXT record
4. Platform verifies ownership
5. Platform generates final DNS records:
- MX
- SPF
- DKIM
- DMARC
- optional autoconfig
6. Customer adds final records
7. Platform verifies propagation
8. Platform activates the domain

### Transport Hostnames

Use shared infrastructure hostnames in v1:

- `mx1.localhosters.com`
- `mx2.localhosters.com`
- `mail.localhosters.com`
- `webmail.localhosters.com`

Customers point to those.

Do not create per-tenant SMTP/IMAP hostnames in v1.

## Tenant Isolation Model

Isolation in v1 is logical, not per-customer infrastructure.

Isolation controls:

- tenant-scoped resources in Postgres
- domain ownership verification before provisioning
- strict tenant authorization in control plane
- per-tenant quotas and rate limits
- audit log entries for every mutation
- internal admin actions require actor attribution

Do not promise physical isolation in v1.

## Security Model

### In Scope for "Encrypted Secure Mail"

- TLS for IMAP/SMTP/web
- encrypted disks/volumes
- encrypted backups
- hashed credentials
- internal admin behind identity-aware access
- signed outbound mail via DKIM
- domain policy via SPF/DMARC

### Not In Scope for v1

- end-to-end encrypted mailbox contents
- customer-managed encryption keys
- zero-access webmail architecture

## Deployment Shape

### Recommended Production Layout

- `mail-1`: Mailu on dedicated or highly trusted compute
- `app-1`: superapp API + workers
- `db-1`: Postgres primary
- `redis-1`: queue and caching
- `backup target`: encrypted object storage

Small launch variant:

- app + worker + redis + postgres on one host
- Mailu on separate host

Do not colocate everything on one node if you expect real tenants.

## Network Policy

Public:

- `25`, `465`, `587`, `143`, `993`, `4190` to Mailu front
- `443` to public superapp

Private only:

- Mailu admin/API
- Postgres
- Redis
- worker dashboards
- metrics

Cloudflare Tunnel is appropriate only for the private HTTP admin plane.

## Storage Model

- Postgres for control state
- Mailu-managed mail storage on fast disk
- encrypted object storage for backups
- append-only audit events in Postgres

## Recommended Repo Layout

```text
apps/
  superapp-web/
  control-api/
workers/
  provisioner/
  dns-verifier/
  billing-sync/
packages/
  db/
  authz/
  mailu-adapter/
  dns-checks/
  billing/
  audit/
infra/
  mailu/
  postgres/
  redis/
docs/
  control-plane-architecture.md
  data-model.md
  security-ops.md
  rollout-plan.md
  backlog.md
openapi/
  control-plane.yaml
sql/
  control-plane.sql
```

## Service Contracts

The control plane owns desired state.

Mailu is an implementation detail behind this interface:

- `createDomain`
- `deleteDomain`
- `createMailbox`
- `deleteMailbox`
- `setMailboxPassword`
- `createAlias`
- `deleteAlias`
- `getDomainDnsRecords`
- `suspendDomain`
- `resumeDomain`

This prevents vendor lock-in to one mail engine.

## Non-Negotiable v1 Acceptance Criteria

- customer can onboard a domain without giving DNS credentials
- domain ownership is verified before mailbox creation
- one primary mailbox plus aliases can be provisioned end to end
- billing status can suspend and resume service
- every mutation is audit logged
- backups are tested with restore drills
- support can diagnose DNS failures from the dashboard

## Explicit v1 Non-Goals

- full DNS hosting for customer domains
- delegated customer admins inside Mailu
- per-tenant branded webmail domains
- E2EE mailbox UX
- HA clustered mail from day one
- mailbox migration from third-party providers
