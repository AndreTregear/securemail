CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tenant_status') THEN
    CREATE TYPE tenant_status AS ENUM ('trialing', 'active', 'past_due', 'suspended', 'cancelled');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'domain_status') THEN
    CREATE TYPE domain_status AS ENUM ('draft', 'verification_pending', 'verified', 'dns_pending', 'active', 'suspended', 'failed', 'deleted');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mailbox_status') THEN
    CREATE TYPE mailbox_status AS ENUM ('pending', 'active', 'suspended', 'password_reset_required', 'deleted');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
    CREATE TYPE job_status AS ENUM ('queued', 'running', 'succeeded', 'failed', 'retrying', 'cancelled');
  END IF;
END$$;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug CITEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  status tenant_status NOT NULL DEFAULT 'trialing',
  owner_email CITEXT NOT NULL,
  billing_customer_id TEXT,
  plan_code TEXT NOT NULL,
  grace_period_ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  domain_name CITEXT NOT NULL UNIQUE,
  status domain_status NOT NULL DEFAULT 'draft',
  provider TEXT NOT NULL DEFAULT 'mailu',
  provider_domain_ref TEXT,
  primary_mail_host TEXT NOT NULL,
  mx_mode TEXT NOT NULL DEFAULT 'shared',
  verification_method TEXT NOT NULL DEFAULT 'txt',
  verified_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  last_dns_check_at TIMESTAMPTZ,
  last_dns_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_domains_tenant_id ON domains (tenant_id);
CREATE INDEX IF NOT EXISTS idx_domains_status ON domains (status);

CREATE TABLE IF NOT EXISTS domain_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES domains(id) ON DELETE CASCADE,
  verification_type TEXT NOT NULL DEFAULT 'txt',
  token_name TEXT NOT NULL,
  token_value TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  verified_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_domain_verifications_domain_id ON domain_verifications (domain_id);

CREATE TABLE IF NOT EXISTS domain_dns_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES domains(id) ON DELETE CASCADE,
  record_type TEXT NOT NULL,
  host TEXT NOT NULL,
  value TEXT NOT NULL,
  priority INTEGER,
  ttl INTEGER NOT NULL DEFAULT 300,
  required BOOLEAN NOT NULL DEFAULT TRUE,
  check_status TEXT NOT NULL DEFAULT 'pending',
  last_seen_value TEXT,
  last_checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_domain_dns_records_domain_id ON domain_dns_records (domain_id);

CREATE TABLE IF NOT EXISTS mailboxes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  domain_id UUID NOT NULL REFERENCES domains(id) ON DELETE CASCADE,
  email CITEXT NOT NULL UNIQUE,
  localpart CITEXT NOT NULL,
  status mailbox_status NOT NULL DEFAULT 'pending',
  role TEXT NOT NULL DEFAULT 'user',
  storage_quota_mb INTEGER NOT NULL DEFAULT 2048,
  provider_mailbox_ref TEXT,
  password_rotated_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mailboxes_tenant_id ON mailboxes (tenant_id);
CREATE INDEX IF NOT EXISTS idx_mailboxes_domain_id ON mailboxes (domain_id);

CREATE TABLE IF NOT EXISTS aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  domain_id UUID NOT NULL REFERENCES domains(id) ON DELETE CASCADE,
  source_email CITEXT NOT NULL,
  destination_email CITEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  provider_alias_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (source_email, destination_email)
);

CREATE INDEX IF NOT EXISTS idx_aliases_tenant_id ON aliases (tenant_id);
CREATE INDEX IF NOT EXISTS idx_aliases_domain_id ON aliases (domain_id);

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'stripe',
  provider_customer_id TEXT,
  provider_subscription_id TEXT,
  plan_code TEXT NOT NULL,
  status TEXT NOT NULL,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant_id ON subscriptions (tenant_id);

CREATE TABLE IF NOT EXISTS provisioning_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  job_type TEXT NOT NULL,
  status job_status NOT NULL DEFAULT 'queued',
  idempotency_key TEXT NOT NULL UNIQUE,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 10,
  scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  error_code TEXT,
  error_message TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  result JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_provisioning_jobs_tenant_id ON provisioning_jobs (tenant_id);
CREATE INDEX IF NOT EXISTS idx_provisioning_jobs_status ON provisioning_jobs (status);

CREATE TABLE IF NOT EXISTS audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  actor_type TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  request_id TEXT,
  ip_address INET,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_events_tenant_id ON audit_events (tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_event_type ON audit_events (event_type);

CREATE TABLE IF NOT EXISTS support_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  domain_id UUID REFERENCES domains(id) ON DELETE SET NULL,
  author_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_notes_tenant_id ON support_notes (tenant_id);

DROP TRIGGER IF EXISTS set_updated_at_tenants ON tenants;
CREATE TRIGGER set_updated_at_tenants BEFORE UPDATE ON tenants
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_domains ON domains;
CREATE TRIGGER set_updated_at_domains BEFORE UPDATE ON domains
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_domain_dns_records ON domain_dns_records;
CREATE TRIGGER set_updated_at_domain_dns_records BEFORE UPDATE ON domain_dns_records
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_mailboxes ON mailboxes;
CREATE TRIGGER set_updated_at_mailboxes BEFORE UPDATE ON mailboxes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_aliases ON aliases;
CREATE TRIGGER set_updated_at_aliases BEFORE UPDATE ON aliases
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_subscriptions ON subscriptions;
CREATE TRIGGER set_updated_at_subscriptions BEFORE UPDATE ON subscriptions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_provisioning_jobs ON provisioning_jobs;
CREATE TRIGGER set_updated_at_provisioning_jobs BEFORE UPDATE ON provisioning_jobs
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- audit_events is append-only. Revoke UPDATE/DELETE on the application role
-- so a compromised app identity cannot rewrite history. Administrative
-- superuser access is expected to be out-of-band and separately audited.
CREATE OR REPLACE FUNCTION prevent_audit_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS audit_events_no_update ON audit_events;
CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON audit_events
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

DROP TRIGGER IF EXISTS audit_events_no_delete ON audit_events;
CREATE TRIGGER audit_events_no_delete BEFORE DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

-- Row-Level Security.
--
-- The API connects as role `app_tenant` and MUST execute the following at the
-- start of every tenant-scoped transaction:
--   SET LOCAL app.current_tenant_id = '<tenant uuid>';
-- Internal workers and background jobs connect as `app_worker`, which bypasses
-- RLS because they legitimately need cross-tenant reach (job scheduling,
-- provider reconciliation, billing sweeps). `app_worker` must never be used
-- to serve an authenticated HTTP request.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_tenant') THEN
    CREATE ROLE app_tenant NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_worker') THEN
    CREATE ROLE app_worker NOLOGIN BYPASSRLS;
  END IF;
END$$;

CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID AS $$
BEGIN
  RETURN NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

ALTER TABLE tenants              ENABLE ROW LEVEL SECURITY;
ALTER TABLE domains              ENABLE ROW LEVEL SECURITY;
ALTER TABLE domain_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE domain_dns_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE mailboxes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE aliases              ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE provisioning_jobs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_notes        ENABLE ROW LEVEL SECURITY;

-- `tenants` is keyed by id, not tenant_id; policy matches id against the
-- session variable directly.
DROP POLICY IF EXISTS tenants_isolation ON tenants;
CREATE POLICY tenants_isolation ON tenants
  USING (id = current_tenant_id())
  WITH CHECK (id = current_tenant_id());

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'domains', 'mailboxes', 'aliases', 'subscriptions',
    'provisioning_jobs', 'audit_events', 'support_notes'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_tenant_isolation ON %I', tbl, tbl);
    EXECUTE format(
      'CREATE POLICY %I_tenant_isolation ON %I '
      'USING (tenant_id IS NOT DISTINCT FROM current_tenant_id()) '
      'WITH CHECK (tenant_id IS NOT DISTINCT FROM current_tenant_id())',
      tbl, tbl
    );
  END LOOP;
END$$;

-- domain_verifications and domain_dns_records are keyed by domain_id; reach
-- back to the parent domain's tenant.
DROP POLICY IF EXISTS domain_verifications_tenant_isolation ON domain_verifications;
CREATE POLICY domain_verifications_tenant_isolation ON domain_verifications
  USING (EXISTS (SELECT 1 FROM domains d WHERE d.id = domain_verifications.domain_id AND d.tenant_id = current_tenant_id()))
  WITH CHECK (EXISTS (SELECT 1 FROM domains d WHERE d.id = domain_verifications.domain_id AND d.tenant_id = current_tenant_id()));

DROP POLICY IF EXISTS domain_dns_records_tenant_isolation ON domain_dns_records;
CREATE POLICY domain_dns_records_tenant_isolation ON domain_dns_records
  USING (EXISTS (SELECT 1 FROM domains d WHERE d.id = domain_dns_records.domain_id AND d.tenant_id = current_tenant_id()))
  WITH CHECK (EXISTS (SELECT 1 FROM domains d WHERE d.id = domain_dns_records.domain_id AND d.tenant_id = current_tenant_id()));

-- Grants: app_tenant must not be able to mutate audit_events (the trigger
-- blocks UPDATE/DELETE, but INSERT is permitted — the API inserts audit rows
-- for its own tenant).
GRANT SELECT, INSERT, UPDATE, DELETE ON
  tenants, domains, domain_verifications, domain_dns_records,
  mailboxes, aliases, subscriptions, provisioning_jobs, support_notes
TO app_tenant;
GRANT SELECT, INSERT ON audit_events TO app_tenant;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  tenants, domains, domain_verifications, domain_dns_records,
  mailboxes, aliases, subscriptions, provisioning_jobs, support_notes, audit_events
TO app_worker;
