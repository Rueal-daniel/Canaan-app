-- ============================================================================
-- CANAAN APP — LINKED STUDENTS (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- PURPOSE:
--   Lets an Admin link several student accounts into one family group so
--   the family can switch between linked student dashboards without
--   logging out. Students NEVER create links themselves.
--
-- ARCHITECTURE:
--   student_link_groups  → ONE row per family/group (admin-owned).
--   student_link_members → ONE row per (group, student) membership.
--   The existing `students` rows are REUSED — never duplicated.
--
-- SECURITY MODEL (matches the rest of the Canaan app):
--   The app signs in with its own username/password tables (it uses the
--   anon key directly, not Supabase Auth / auth.uid()). RLS is therefore
--   enabled with permissive app-level policies (same as student_updates,
--   notifications, etc.), and authorization is enforced in the APP LAYER
--   at query time by LinkedStudentService:
--     • only Admin screens ever INSERT/UPDATE/DELETE link rows;
--     • a student can switch to target T ONLY when the server confirms
--       the logged-in student and T share a group AND T still exists
--       AND T is not suspended;
--     • every student data page queries by the VERIFIED active student id.
--   A student can never guess another id, edit an id manually, or read
--   an unlinked student's attendance / progress / leave / updates.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. student_link_groups
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_link_groups (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  group_name  TEXT NOT NULL DEFAULT '',
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.student_link_groups ADD COLUMN IF NOT EXISTS group_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_link_groups ADD COLUMN IF NOT EXISTS created_by TEXT;
ALTER TABLE public.student_link_groups ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.student_link_groups ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ----------------------------------------------------------------------------
-- 2. student_link_members
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_link_members (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  group_id    BIGINT NOT NULL REFERENCES public.student_link_groups (id) ON DELETE CASCADE,
  student_id  TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.student_link_members ADD COLUMN IF NOT EXISTS group_id BIGINT;
ALTER TABLE public.student_link_members ADD COLUMN IF NOT EXISTS student_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.student_link_members ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- One student appears at most once per group (prevents duplicate tiles).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'student_link_members_group_student_unique'
  ) THEN
    ALTER TABLE public.student_link_members
      ADD CONSTRAINT student_link_members_group_student_unique
      UNIQUE (group_id, student_id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Indexes (fast "my linked family" + admin group lookups)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS student_link_members_student_idx
  ON public.student_link_members (student_id);
CREATE INDEX IF NOT EXISTS student_link_members_group_idx
  ON public.student_link_members (group_id);
CREATE INDEX IF NOT EXISTS student_link_groups_updated_idx
  ON public.student_link_groups (updated_at DESC);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (permissive app-key policies — see header note;
--    authorization is enforced in LinkedStudentService at query time)
-- ----------------------------------------------------------------------------
ALTER TABLE public.student_link_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_link_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read student_link_groups" ON public.student_link_groups;
CREATE POLICY "app read student_link_groups"
  ON public.student_link_groups FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert student_link_groups" ON public.student_link_groups;
CREATE POLICY "app insert student_link_groups"
  ON public.student_link_groups FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update student_link_groups" ON public.student_link_groups;
CREATE POLICY "app update student_link_groups"
  ON public.student_link_groups FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete student_link_groups" ON public.student_link_groups;
CREATE POLICY "app delete student_link_groups"
  ON public.student_link_groups FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read student_link_members" ON public.student_link_members;
CREATE POLICY "app read student_link_members"
  ON public.student_link_members FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert student_link_members" ON public.student_link_members;
CREATE POLICY "app insert student_link_members"
  ON public.student_link_members FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update student_link_members" ON public.student_link_members;
CREATE POLICY "app update student_link_members"
  ON public.student_link_members FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete student_link_members" ON public.student_link_members;
CREATE POLICY "app delete student_link_members"
  ON public.student_link_members FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 5. Realtime (admin list + student switch sheet update with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'student_link_groups'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.student_link_groups;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'student_link_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.student_link_members;
  END IF;
END $$;
