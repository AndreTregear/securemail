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
