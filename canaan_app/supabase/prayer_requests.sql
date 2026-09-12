-- ============================================================================
-- CANAAN APP — PRAYER REQUESTS (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- ARCHITECTURE (same pattern as the rest of the app):
--   prayer_requests         → ONE shared community feed. Admin, Teacher and
--                             Student requests all live here (never separate
--                             tables per role).
--   prayer_request_replies  → ONE admin reply per request
--                             (prayer_request_id → prayer_requests.id
--                             ON DELETE CASCADE, so deleting a request can
--                             never leave a broken reply behind).
-- Only display-safe columns exist here: user_id, full_name, role, title,
-- description (+ reply admin_id/admin_name/comment). No emails, phones,
-- usernames or passwords are ever stored in these tables.
--
-- Notifications: submissions + admin replies fan out through the EXISTING
-- `notifications` + `notification_recipients` tables
-- (type='prayer_request' / destination='prayer_requests') — see
-- NotificationService.prayerRequestSubmitted / prayerReplySent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. prayer_requests — the shared feed
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.prayer_requests (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     TEXT NOT NULL DEFAULT '',
  full_name   TEXT NOT NULL DEFAULT '',
  role        TEXT NOT NULL DEFAULT 'student',
  title       TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS user_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS full_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'student';
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.prayer_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ----------------------------------------------------------------------------
-- 2. prayer_request_replies — the single admin reply per request
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.prayer_request_replies (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prayer_request_id BIGINT NOT NULL
    REFERENCES public.prayer_requests (id) ON DELETE CASCADE,
  admin_id          TEXT NOT NULL DEFAULT '',
  admin_name        TEXT NOT NULL DEFAULT '',
  comment           TEXT NOT NULL DEFAULT '',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS prayer_request_id BIGINT;
ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS admin_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS admin_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS comment TEXT NOT NULL DEFAULT '';
ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.prayer_request_replies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- One reply per request: an upsert on prayer_request_id can never
-- create a second reply row for the same request.
CREATE UNIQUE INDEX IF NOT EXISTS prayer_request_replies_unique_request
  ON public.prayer_request_replies (prayer_request_id);

-- ----------------------------------------------------------------------------
-- 3. Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS prayer_requests_created_idx
  ON public.prayer_requests (created_at DESC);
CREATE INDEX IF NOT EXISTS prayer_requests_role_idx
  ON public.prayer_requests (role);
CREATE INDEX IF NOT EXISTS prayer_requests_user_idx
  ON public.prayer_requests (user_id);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security
-- ----------------------------------------------------------------------------
-- The Canaan app signs in with its own username/password tables (it uses
-- the anon key directly, not Supabase Auth / auth.uid()). RLS is enabled
-- and every role used by the app (anon + authenticated) is granted access;
-- the role rules (everyone reads the shared feed; only admins write
-- replies; owners-or-admin delete) are enforced in the app layer
-- (PrayerRequestService + PrayerRequestBoard) at query time, and these
-- tables hold no private account data at all.
ALTER TABLE public.prayer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayer_request_replies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read prayer_requests" ON public.prayer_requests;
CREATE POLICY "app read prayer_requests"
  ON public.prayer_requests FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert prayer_requests" ON public.prayer_requests;
CREATE POLICY "app insert prayer_requests"
  ON public.prayer_requests FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update prayer_requests" ON public.prayer_requests;
CREATE POLICY "app update prayer_requests"
  ON public.prayer_requests FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete prayer_requests" ON public.prayer_requests;
CREATE POLICY "app delete prayer_requests"
  ON public.prayer_requests FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read prayer_request_replies" ON public.prayer_request_replies;
CREATE POLICY "app read prayer_request_replies"
  ON public.prayer_request_replies FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert prayer_request_replies" ON public.prayer_request_replies;
CREATE POLICY "app insert prayer_request_replies"
  ON public.prayer_request_replies FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update prayer_request_replies" ON public.prayer_request_replies;
CREATE POLICY "app update prayer_request_replies"
  ON public.prayer_request_replies FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete prayer_request_replies" ON public.prayer_request_replies;
CREATE POLICY "app delete prayer_request_replies"
  ON public.prayer_request_replies FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 5. Realtime (feed + replies update with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'prayer_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.prayer_requests;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'prayer_request_replies'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.prayer_request_replies;
  END IF;
END $$;
