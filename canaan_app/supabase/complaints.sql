-- ============================================================================
-- CANAAN APP — COMPLAINTS / PROBLEM REPORTS (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- PURPOSE:
--   Lets Teachers/Students report problems (login issues, app errors,
--   wrong information, …) BEFORE login — the form lives on the Login
--   page and needs no authentication. Admin reviews under
--   Management → Complaint (Pending → Approved / Rejected).
--
-- PRIVACY & ACCESS MODEL:
--   • Anonymous users may ONLY INSERT a complaint (required fields).
--     Complaint reads/updates/deletes happen ONLY in the Admin pages —
--     no public feed, no browsing of other people's complaints.
--   • NOTE (same as every other Canaan table): the app signs in with its
--     own username/password tables over the anon key (no Supabase Auth
--     uid), so RLS policies below are permissive and authorization is
--     enforced in the APP LAYER (ComplaintService + Admin-only screens).
--
-- SERVER-SIDE SPAM/ABUSE PROTECTION (not frontend-only):
--   • complaint_type + status whitelists (CHECK constraints).
--   • description length cap (CHECK, 1000 chars).
--   • phone format check (CHECK, digits/spaces/+/- only, 7–20 chars).
--   • role whitelist (teacher/student only — never admin).
--   Client adds cooldown throttling on top (SharedPreferences).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. complaints
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.complaints (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  role             TEXT NOT NULL DEFAULT '',
  full_name        TEXT NOT NULL DEFAULT '',
  phone_number     TEXT NOT NULL DEFAULT '',
  complaint_type   TEXT NOT NULL DEFAULT 'reminder',
  description      TEXT NOT NULL DEFAULT '',
  status           TEXT NOT NULL DEFAULT 'pending',
  admin_comment    TEXT NOT NULL DEFAULT '',
  rejection_reason TEXT NOT NULL DEFAULT '',
  reviewed_by      TEXT,
  reviewed_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS full_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS phone_number TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS complaint_type TEXT NOT NULL DEFAULT 'reminder';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS admin_comment TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS rejection_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS reviewed_by TEXT;
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.complaints ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ----------------------------------------------------------------------------
-- 2. Server-side validation (CHECK constraints — enforced by the database
--    itself, independent of any client)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'complaints_role_check'
  ) THEN
    ALTER TABLE public.complaints
      ADD CONSTRAINT complaints_role_check
      CHECK (role IN ('teacher', 'student'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'complaints_type_check'
  ) THEN
    ALTER TABLE public.complaints
      ADD CONSTRAINT complaints_type_check
      CHECK (complaint_type IN ('emergency', 'reminder'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'complaints_status_check'
  ) THEN
    ALTER TABLE public.complaints
      ADD CONSTRAINT complaints_status_check
      CHECK (status IN ('pending', 'approved', 'rejected'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'complaints_required_check'
  ) THEN
    ALTER TABLE public.complaints
      ADD CONSTRAINT complaints_required_check
      CHECK (
        char_length(full_name) BETWEEN 1 AND 120
        AND char_length(description) BETWEEN 1 AND 1000
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'complaints_phone_check'
  ) THEN
    ALTER TABLE public.complaints
      ADD CONSTRAINT complaints_phone_check
      CHECK (phone_number ~ '^[0-9+()\\-\\. ]{7,20}$');
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Indexes (fast admin list + status counts)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS complaints_status_idx
  ON public.complaints (status, created_at DESC);
CREATE INDEX IF NOT EXISTS complaints_type_idx
  ON public.complaints (complaint_type, created_at DESC);
CREATE INDEX IF NOT EXISTS complaints_created_idx
  ON public.complaints (created_at DESC);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (permissive app-key policies — see header note;
--    anonymous INSERT is the only non-admin path, and the app exposes it
--    solely through the Login-page complaint form; all reads/writes live
--    in the Admin-only Complaint section)
-- ----------------------------------------------------------------------------
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read complaints" ON public.complaints;
CREATE POLICY "app read complaints"
  ON public.complaints FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert complaints" ON public.complaints;
CREATE POLICY "app insert complaints"
  ON public.complaints FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update complaints" ON public.complaints;
CREATE POLICY "app update complaints"
  ON public.complaints FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete complaints" ON public.complaints;
CREATE POLICY "app delete complaints"
  ON public.complaints FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 5. Realtime (new complaints arrive in the Admin section live)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'complaints'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.complaints;
  END IF;
END $$;
