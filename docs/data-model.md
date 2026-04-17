# Data Model

## Design Principles

- tenant-first ownership for all customer-visible resources
- immutable audit trail for changes
- desired state and observed state tracked separately where useful
- provider-specific IDs stored as external references, not primary keys

## State Machines

### Tenant

- `trialing`
- `active`
- `past_due`
- `suspended`
- `cancelled`

### Domain

- `draft`
- `verification_pending`
- `verified`
- `dns_pending`
- `active`
- `suspended`
- `failed`
- `deleted`

### Mailbox

- `pending`
- `active`
- `suspended`
- `password_reset_required`
- `deleted`

### Provisioning Job

- `queued`
- `running`
- `succeeded`
- `failed`
- `retrying`
- `cancelled`

## Core Tables

### tenants

Purpose:

- top-level customer account

Fields:

- `id`
- `slug`
- `display_name`
- `status`
- `owner_email`
- `billing_customer_id`
- `plan_code`
- `grace_period_ends_at`
- `created_at`
- `updated_at`

### domains

Purpose:

- one mail-enabled domain owned by a tenant

Fields:

- `id`
- `tenant_id`
- `domain_name`
- `status`
- `provider`
- `provider_domain_ref`
- `primary_mail_host`
- `mx_mode`
- `verification_method`
- `verified_at`
- `activated_at`
- `last_dns_check_at`
- `last_dns_error`
- `created_at`
- `updated_at`

Constraints:

- unique `domain_name`
- one tenant owns a domain globally

### domain_verifications

Purpose:

- track ownership verification challenges

Fields:

- `id`
- `domain_id`
- `verification_type`
- `token_name`
- `token_value`
- `status`
- `attempt_count`
- `verified_at`
- `expires_at`
- `created_at`

### domain_dns_records

Purpose:

- canonical desired DNS set your system asks the customer to publish

Fields:

- `id`
- `domain_id`
- `record_type`
- `host`
- `value`
- `priority`
- `ttl`
- `required`
- `check_status`
- `last_seen_value`
- `last_checked_at`
- `created_at`
- `updated_at`

### mailboxes

Purpose:

- actual inboxes

Fields:

- `id`
- `tenant_id`
- `domain_id`
- `email`
- `localpart`
- `status`
- `role`
- `storage_quota_mb`
- `provider_mailbox_ref`
- `password_rotated_at`
- `last_login_at`
- `created_at`
- `updated_at`

Roles:

- `primary`
- `user`
- `service`

### aliases

Purpose:

- alias addresses and forwarding targets

Fields:

- `id`
- `tenant_id`
- `domain_id`
- `source_email`
- `destination_email`
- `status`
- `provider_alias_ref`
- `created_at`
- `updated_at`

Constraints:

- unique pair of `source_email` and `destination_email`

### subscriptions

Purpose:

- current and historical billing state

Fields:

- `id`
- `tenant_id`
- `provider`
- `provider_customer_id`
- `provider_subscription_id`
- `plan_code`
- `status`
- `current_period_start`
- `current_period_end`
- `cancel_at_period_end`
- `created_at`
- `updated_at`

### provisioning_jobs

Purpose:

- durable orchestration state and retries

Fields:

- `id`
- `tenant_id`
- `resource_type`
- `resource_id`
- `job_type`
- `status`
- `idempotency_key`
- `attempts`
- `max_attempts`
- `scheduled_at`
- `started_at`
- `finished_at`
- `error_code`
- `error_message`
- `payload`
- `result`
- `created_at`
- `updated_at`

### audit_events

Purpose:

- append-only mutation and access log

Fields:

- `id`
- `tenant_id`
- `actor_type`
- `actor_id`
- `event_type`
- `resource_type`
- `resource_id`
- `request_id`
- `ip_address`
- `metadata`
- `created_at`

### support_notes

Purpose:

- operator-visible notes for manual onboarding support

Fields:

- `id`
- `tenant_id`
- `domain_id`
- `author_id`
- `body`
- `created_at`

## Key Invariants

- a domain must be verified before activation
- a mailbox cannot exist without an active or dns-pending domain
- alias destinations must refer to a valid mailbox or approved external target
- subscription suspension must propagate to tenant and mailbox availability
- provider mutations must be driven through idempotent jobs

## Default Resource Template

For first-run onboarding:

- create one mailbox: `<primaryLocalpart>@domain` (supplied by the caller at domain creation)
- create one alias: `info@domain -> <primaryLocalpart>@domain`
- create one alias: `contact@domain -> <primaryLocalpart>@domain`

This should be represented as a reusable template at the application layer, not hard-coded into SQL.

## Drift Reconciliation

Observed state should be re-polled periodically:

- missing domain in Mailu
- missing mailbox in Mailu
- alias drift
- DNS drift
- billing drift

Reconciliation writes findings to:

- `provisioning_jobs.result`
- `domains.last_dns_error`
- `audit_events`

## Retention

- audit events: never delete without archival policy
- provisioning job payloads: retain for at least 180 days
- support notes: retain for account lifetime
- deleted mailbox/domain rows: soft delete first, hard delete by retention job later
