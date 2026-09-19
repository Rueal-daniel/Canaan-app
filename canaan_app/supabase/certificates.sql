-- ============================================================================
-- CANAAN APP — STUDENT ACHIEVEMENT CERTIFICATES (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- PURPOSE:
--   Stores Admin-issued achievement certificates for students ranked
--   1st / 2nd / 3rd on the live Leaderboards (Attendance / Memory Verse).
--
-- ARCHITECTURE:
--   certificates → ONE row per issued certificate. The leaderboard itself
--   is NEVER stored — it is always calculated live; only the certificate
--   snapshot (name, section, category, position, percentage, date) is kept
--   so a published certificate stays historically accurate even if the
--   leaderboard later changes. Student rows are REUSED, never duplicated.
--
-- VISIBILITY RULE (enforced in CertificateService at query time):
--   status='draft'     → Admin only. Students/teachers never query drafts.
--   status='published' → the ONE student (by student_id) + teachers of the
--                        section. Publishing fans out a notification.
--
-- SECURITY MODEL (matches the rest of the Canaan app):
--   The app signs in with its own username/password tables (it uses the
--   anon key directly, not Supabase Auth / auth.uid()). RLS is therefore
--   enabled with permissive app-level policies (same as all other Canaan
--   tables); authorization is enforced in the APP LAYER:
--     • only Admin screens ever INSERT/UPDATE/DELETE certificate rows;
--     • students query ONLY status='published' rows with their own
--       VERIFIED active student_id (a forged id returns nothing);
--     • teachers query ONLY status='published' rows of their OWN
--       server-resolved section.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. certificates
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.certificates (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_id       TEXT NOT NULL DEFAULT '',
  student_name     TEXT NOT NULL DEFAULT '',
  section          TEXT NOT NULL DEFAULT '',
  category         TEXT NOT NULL DEFAULT '',
  position         INTEGER NOT NULL DEFAULT 0,
  percentage       DOUBLE PRECISION NOT NULL DEFAULT 0,
  certificate_date TEXT NOT NULL DEFAULT '',
  status           TEXT NOT NULL DEFAULT 'draft',
  generated_by     TEXT,
  published_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS student_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS student_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT '';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT '';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS percentage DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS certificate_date TEXT NOT NULL DEFAULT '';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft';
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS generated_by TEXT;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- One published-or-draft certificate per student + category + position
-- (prevents accidental double-issuing of the same achievement).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'certificates_student_category_position_unique'
  ) THEN
    ALTER TABLE public.certificates
      ADD CONSTRAINT certificates_student_category_position_unique
      UNIQUE (student_id, category, position);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Indexes (fast "my certificates" + teacher section + admin list)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS certificates_student_idx
  ON public.certificates (student_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS certificates_section_idx
  ON public.certificates (section, status, created_at DESC);
CREATE INDEX IF NOT EXISTS certificates_status_idx
  ON public.certificates (status, created_at DESC);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security (permissive app-key policies — see header note;
--    authorization is enforced in CertificateService at query time)
-- ----------------------------------------------------------------------------
ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read certificates" ON public.certificates;
CREATE POLICY "app read certificates"
  ON public.certificates FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert certificates" ON public.certificates;
CREATE POLICY "app insert certificates"
  ON public.certificates FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update certificates" ON public.certificates;
CREATE POLICY "app update certificates"
  ON public.certificates FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete certificates" ON public.certificates;
CREATE POLICY "app delete certificates"
  ON public.certificates FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 4. Realtime (student/teacher lists update on publish with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'certificates'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.certificates;
  END IF;
END $$;
