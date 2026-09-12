-- ============================================================================
-- CANAAN APP — STUDENT UPDATES (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- ARCHITECTURE:
--   student_updates → ONE row per weekly Admin update for ONE student.
--     The three written observations (what the student did / learned /
--     behaviour) are combined into the single `behaviour_detail` column —
--     no separate columns per textarea. Saturday rating (1–5) and the
--     Admin-given percentage (0–100) belong ONLY to the update and never
--     touch the existing Progress/Attendance calculations.
--   Teacher name + update date are NOT stored: the teacher is resolved
--     live from the student's section, and the date is `created_at`.
--
-- Notifications: a new update fans out through the EXISTING
-- `notifications` + `notification_recipients` tables
-- (type='student_update', destination='my_update') to the ONE specific
-- student only — see NotificationService.studentUpdateSent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. student_updates
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_updates (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_id       TEXT NOT NULL DEFAULT '',
  student_name     TEXT NOT NULL DEFAULT '',
  section          TEXT NOT NULL DEFAULT '',
  behaviour_detail TEXT NOT NULL DEFAULT '',
  saturday_rating  INTEGER NOT NULL DEFAULT 0,
  total_percentage INTEGER NOT NULL DEFAULT 0,
  additional_notes TEXT NOT NULL DEFAULT '',
  created_by       TEXT NOT NULL DEFAULT '',
  created_by_id    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS student_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS student_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS behaviour_detail TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS saturday_rating INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS total_percentage INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS additional_notes TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS created_by TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS created_by_id TEXT;
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.student_updates ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ----------------------------------------------------------------------------
-- 2. Indexes (fast "my updates" + admin history queries)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS student_updates_student_idx
  ON public.student_updates (student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS student_updates_section_idx
  ON public.student_updates (section, created_at DESC);
CREATE INDEX IF NOT EXISTS student_updates_created_idx
  ON public.student_updates (created_at DESC);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- ----------------------------------------------------------------------------
-- The Canaan app signs in with its own username/password tables (it uses
-- the anon key directly, not Supabase Auth / auth.uid()). RLS is enabled
-- and every role used by the app (anon + authenticated) is granted access;
-- the rules (admins manage everything; students read ONLY their own
-- student_id rows and never write) are enforced in the app layer
-- (StudentUpdateService + pages) at query time.
ALTER TABLE public.student_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read student_updates" ON public.student_updates;
CREATE POLICY "app read student_updates"
  ON public.student_updates FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert student_updates" ON public.student_updates;
CREATE POLICY "app insert student_updates"
  ON public.student_updates FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update student_updates" ON public.student_updates;
CREATE POLICY "app update student_updates"
  ON public.student_updates FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete student_updates" ON public.student_updates;
CREATE POLICY "app delete student_updates"
  ON public.student_updates FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 4. Realtime (student sees the new update with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'student_updates'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.student_updates;
  END IF;
END $$;
