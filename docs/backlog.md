# Initial Backlog

## Milestone 1: Foundation

### ML-001 Platform repo bootstrap

- create `apps/control-api`, `workers/provisioner`, `workers/dns-verifier`, `packages/db`, `packages/mailu-adapter`
- configure TypeScript project references
- add lint, test, and migration tooling

### ML-002 Postgres schema implementation

- implement tables from `sql/control-plane.sql`
- add migrations
- add seed for plan catalog

### ML-003 Redis and BullMQ setup

- configure shared queue package
- define queue names and retry policies
- add dead-letter queue handling

### ML-004 Audit event middleware

- generate request IDs
- capture actor metadata
- persist audit events for writes

## Milestone 2: Mailu Adapter

### ML-010 Mailu adapter interface

- define provider contract
- implement Mailu-backed adapter
- normalize provider errors into platform error codes

### ML-011 Domain lifecycle adapter methods

- create domain
- delete domain
- suspend/resume domain
- fetch DNS export

### ML-012 Mailbox lifecycle adapter methods

- create mailbox
- delete mailbox
- set password
- create/delete alias

### ML-013 Reconciliation worker

- poll Mailu state
- report drift
- emit audit and diagnostics events

## Milestone 3: Domain Onboarding

### ML-020 Domain create endpoint

- create draft domain
- generate verification TXT
- enqueue DNS verification

### ML-021 Verification and DNS diagnostics

- resolve TXT, MX, SPF, DKIM, DMARC
- store per-record check results
- generate human-readable failure messages

### ML-022 Domain activation flow

- move from verified to dns_pending to active
- block activation on missing required records

### ML-023 Onboarding UI

- domain entry
- DNS instructions
- progress states
- retry checks

## Milestone 4: Mailbox Management

### ML-030 Mailbox create endpoint

- create primary mailbox
- enforce plan quotas
- emit provisioning job

### ML-031 Alias template automation

- create `info@domain` and `contact@domain` aliases
- allow tenant override

### ML-032 Password rotation flow

- privileged reset action
- audit event
- support flow

### ML-033 Mail client settings endpoint

- expose IMAP/SMTP/webmail settings
- expose autoconfig hints

## Milestone 5: Billing

### ML-040 Stripe customer and subscription sync

- create customer on signup
- map plan codes
- persist subscription states

### ML-041 Billing webhook handler

- handle checkout, invoice payment, failure, cancellation
- idempotent webhook processing

### ML-042 Suspension policy engine

- grace period
- soft suspend
- hard suspend
- resume on payment

## Milestone 6: Security and Ops

### ML-050 Internal admin auth

- protect admin routes behind internal auth
- role-based access checks

### ML-051 Backup automation

- nightly encrypted backups
- restore verification workflow

### ML-052 Monitoring and alerts

- queue lag
- cert expiry
- backup freshness
- mail queue thresholds

### ML-053 Abuse controls

- rate limits
- suspicious login counters
- tenant suspension hooks

## Six-Week Execution Plan

### Week 1

- ML-001
- ML-002
- ML-003

### Week 2

- ML-004
- ML-010
- ML-011

### Week 3

- ML-012
- ML-013
- ML-020

### Week 4

- ML-021
- ML-022
- ML-030

### Week 5

- ML-031
- ML-032
- ML-033
- ML-040

### Week 6

- ML-041
- ML-042
- ML-050
- ML-051
- ML-052

## Launch-Critical Deferred Work

These can be deferred until after pilot unless a customer need forces them earlier:

- reseller-branded SMTP hostnames
- delegated domain admins
- mailbox import/migration
- full nameserver hosting
- advanced reporting
- outbound domain warm-up automation
