-- ============================================================================
-- CANAAN APP — STUDENT PROGRESS EVALUATIONS (one-time setup)
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. Idempotent (safe to run again).
--
-- DESIGN (no duplication — matches the notification system philosophy):
--   Attendance % and Memory Verse % are NEVER stored here. They are
--   calculated live from the existing source-of-truth tables:
--     attendance_reports (students JSON per date + section)
--     recitation_sub_junior / recitation_junior / recitation_senior
--   This table holds ONLY what cannot be calculated:
--     Admin's Class Participation + Discipline evaluation and the
--     overall 5-star rating. One row per student (UNIQUE student_id).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.student_progress_evaluations (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id                TEXT        NOT NULL UNIQUE,
  section                   TEXT,
  participation_percentage  INTEGER     NOT NULL DEFAULT 0
    CHECK (participation_percentage >= 0 AND participation_percentage <= 100),
  participation_rating      TEXT        NOT NULL DEFAULT 'Good'
    CHECK (participation_rating IN (
      'Excellent', 'Very Good', 'Good', 'Needs Improvement'
    )),
  participation_comment     TEXT        NOT NULL DEFAULT '',
  discipline_percentage     INTEGER     NOT NULL DEFAULT 0
    CHECK (discipline_percentage >= 0 AND discipline_percentage <= 100),
  discipline_rating         TEXT        NOT NULL DEFAULT 'Good'
    CHECK (discipline_rating IN (
      'Excellent', 'Very Good', 'Good', 'Needs Improvement'
    )),
  discipline_comment        TEXT        NOT NULL DEFAULT '',
  overall_star_rating       INTEGER     NOT NULL DEFAULT 0
    CHECK (overall_star_rating >= 0 AND overall_star_rating <= 5),
  evaluated_by              TEXT,
  evaluated_at              TIMESTAMPTZ,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS student_progress_eval_section_idx
  ON public.student_progress_evaluations (section);
CREATE INDEX IF NOT EXISTS student_progress_eval_updated_idx
  ON public.student_progress_evaluations (updated_at DESC);

-- ----------------------------------------------------------------------------
-- Row Level Security (same contract as the notification tables: the app
-- signs in with its own username/password tables via the anon key, so
-- per-user isolation is enforced in the app layer — students only ever
-- query their own student_id; admins write evaluations).
-- ----------------------------------------------------------------------------
ALTER TABLE public.student_progress_evaluations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read progress evals"
  ON public.student_progress_evaluations;
CREATE POLICY "app read progress evals"
  ON public.student_progress_evaluations FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert progress evals"
  ON public.student_progress_evaluations;
CREATE POLICY "app insert progress evals"
  ON public.student_progress_evaluations FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update progress evals"
  ON public.student_progress_evaluations;
CREATE POLICY "app update progress evals"
  ON public.student_progress_evaluations FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete progress evals"
  ON public.student_progress_evaluations;
CREATE POLICY "app delete progress evals"
  ON public.student_progress_evaluations FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- Realtime (progress pages refresh with no reload)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'student_progress_evaluations'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.student_progress_evaluations;
  END IF;
END $$;
