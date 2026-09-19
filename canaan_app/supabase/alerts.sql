-- ============================================================================
-- CANAAN APP — ALERTS (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- PURPOSE:
--   Admin-published important alerts/instructions for Teachers/Students
--   with a STRICT 24-hour lifetime (published_at → expires_at = +24h).
--   Separate from the Notice Board (normal announcements).
--
-- ARCHITECTURE:
--   alerts            → ONE row per alert (title, message, type, audience,
--                       section, status, expiry). Drafts stay Admin-only.
--   alert_recipients  → per-user read state ONLY (alert_id, user_id, role,
--                       section, is_read, read_at). NEVER duplicates the
--                       alert message. One row per (alert, user).
--   Student/teacher rows are REUSED — no duplicate user tables.
--
-- EXPIRY (strict, §33–§41):
--   expires_at is ALWAYS published_at + 24 hours, set by the app at
--   publish time. Teacher/student queries only return rows with
--   expires_at > now(). Expired rows stay for Admin audit (marked
--   "Expired") but are never delivered as active alerts. Re-publishing
--   means creating a NEW alert (new 24h countdown) — never extended.
--
-- SECURITY MODEL (matches the rest of the Canaan app):
--   The app signs in with its own username/password tables (it uses the
--   anon key directly, not Supabase Auth / auth.uid()). RLS is therefore
--   enabled with permissive app-level policies (same as all other Canaan
--   tables); authorization is enforced in the APP LAYER at query time by
--   AlertService:
--     • only Admin screens ever INSERT/UPDATE/DELETE alert rows;
--     • teachers/students query ONLY status='published' AND
--       expires_at > now() AND their OWN (role, section) targeting —
--       built as server-side query filters, never fetch-all-then-hide;
--     • users can only write their OWN read state
--       (alert_recipients rows keyed by their verified user id).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. alerts
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.alerts (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title        TEXT NOT NULL DEFAULT '',
  message      TEXT NOT NULL DEFAULT '',
  alert_type   TEXT NOT NULL DEFAULT 'general',
  send_to      TEXT NOT NULL DEFAULT 'both',
  section      TEXT NOT NULL DEFAULT 'all',
  status       TEXT NOT NULL DEFAULT 'draft',
  created_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  expires_at   TIMESTAMPTZ
);

ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS message TEXT NOT NULL DEFAULT '';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS alert_type TEXT NOT NULL DEFAULT 'general';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS send_to TEXT NOT NULL DEFAULT 'both';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT 'all';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft';
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS created_by TEXT;
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 2. alert_recipients (read state only — never the message)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.alert_recipients (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_id   BIGINT NOT NULL REFERENCES public.alerts (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL DEFAULT '',
  role       TEXT NOT NULL DEFAULT '',
  section    TEXT NOT NULL DEFAULT '',
  is_read    BOOLEAN NOT NULL DEFAULT false,
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS alert_id BIGINT;
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS user_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT '';
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT '';
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;
ALTER TABLE public.alert_recipients ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- One read-state row per (alert, user).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'alert_recipients_alert_user_unique'
  ) THEN
    ALTER TABLE public.alert_recipients
      ADD CONSTRAINT alert_recipients_alert_user_unique
      UNIQUE (alert_id, user_id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Indexes (fast active-alert + read-state lookups)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS alerts_status_idx
  ON public.alerts (status, expires_at DESC);
CREATE INDEX IF NOT EXISTS alerts_audience_idx
  ON public.alerts (send_to, section, status, published_at DESC);
CREATE INDEX IF NOT EXISTS alert_recipients_user_idx
  ON public.alert_recipients (user_id, is_read);
CREATE INDEX IF NOT EXISTS alert_recipients_alert_idx
  ON public.alert_recipients (alert_id);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (permissive app-key policies — see header note;
--    authorization is enforced in AlertService at query time)
-- ----------------------------------------------------------------------------
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_recipients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read alerts" ON public.alerts;
CREATE POLICY "app read alerts"
  ON public.alerts FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert alerts" ON public.alerts;
CREATE POLICY "app insert alerts"
  ON public.alerts FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update alerts" ON public.alerts;
CREATE POLICY "app update alerts"
  ON public.alerts FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete alerts" ON public.alerts;
CREATE POLICY "app delete alerts"
  ON public.alerts FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read alert_recipients" ON public.alert_recipients;
CREATE POLICY "app read alert_recipients"
  ON public.alert_recipients FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert alert_recipients" ON public.alert_recipients;
CREATE POLICY "app insert alert_recipients"
  ON public.alert_recipients FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update alert_recipients" ON public.alert_recipients;
CREATE POLICY "app update alert_recipients"
  ON public.alert_recipients FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete alert_recipients" ON public.alert_recipients;
CREATE POLICY "app delete alert_recipients"
  ON public.alert_recipients FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 5. Realtime (INSERT / UPDATE / DELETE stream to dashboards live)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'alert_recipients'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.alert_recipients;
  END IF;
END $$;
