# Rollout Plan

## Phase 0: Infrastructure Baseline

Outcome:

- production hosts exist
- network and storage model is settled
- internal admin plane is private

Tasks:

- choose mail host with outbound `25`, static IP, and rDNS control
- allocate separate app/db/redis hosts or equivalent isolation
- configure host firewalls
- set up monitoring, logging, backups
- publish platform hostnames:
- `mx1.localhosters.com`
- `mx2.localhosters.com`
- `mail.localhosters.com`
- `webmail.localhosters.com`

Exit criteria:

- mail host reachable on required ports
- backup target tested
- internal services not public

## Phase 1: Mail Backbone

Outcome:

- Mailu runs stably
- TLS and basic mail policies are correct

Tasks:

- deploy Mailu
- configure DKIM, SPF, DMARC defaults
- create postmaster and abuse handling
- verify webmail and API work
- verify inbound and outbound delivery with test domains

Exit criteria:

- test messages delivered to and from multiple providers
- DKIM signing verified
- mail queue and storage observable

## Phase 2: Control Plane Core

Outcome:

- your platform can model tenants, domains, mailboxes, aliases, and jobs

Tasks:

- create Postgres schema
- implement control-plane API
- add BullMQ workers
- build Mailu adapter
- add audit logging

Exit criteria:

- domain and mailbox lifecycle can be driven through internal APIs only

## Phase 3: Customer Onboarding

Outcome:

- non-technical customers can onboard with copy-paste DNS changes

Tasks:

- build domain verification flow
- build DNS record generator
- build propagation checker and diagnostics
- build mailbox template creation
- build customer-facing setup screen

Exit criteria:

- fresh tenant can activate domain and mailbox end to end without operator shell access

## Phase 4: Billing and Lifecycle Enforcement

Outcome:

- billing state drives provisioning state safely

Tasks:

- integrate Stripe subscriptions
- map plan entitlements
- implement grace period rules
- implement suspension and resume jobs
- add invoice and billing status to tenant UI

Exit criteria:

- billing events correctly suspend and resume service in staging

## Phase 5: Pilot Customers

Outcome:

- real tenants expose support and reliability gaps before launch

Tasks:

- onboard 3 to 5 pilot customers
- capture support notes
- measure average onboarding completion time
- fix top failure modes

Exit criteria:

- pilot onboarding success rate above target
- no unresolved sev1/sev2 issues

## Phase 6: General Availability

Outcome:

- product is safe to sell broadly

Tasks:

- finalize legal docs
- finalize pricing and plans
- automate recurring reports
- publish status page
- finalize support SLAs

Exit criteria:

- launch checklist complete
- on-call and incident process active

## Operational Readiness Checklist

- domain verification retries tested
- provider reconciliation job tested
- Stripe webhook replay handling tested
- backup restore tested
- TLS renewal tested
- operator audit trail tested
- customer-facing diagnostics tested
- abuse and suspension flows tested

## Release Strategy

### Internal Alpha

- you onboard your own domains only
- simulate suspension and restore
- verify support tooling

### Pilot

- hand-held onboarding for selected customers
- no self-service plan changes yet

### GA

- self-service onboarding
- documented support workflow
- published pricing
