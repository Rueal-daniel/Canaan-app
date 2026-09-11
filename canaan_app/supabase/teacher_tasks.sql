-- ============================================================================
-- CANAAN APP — TEACHER TASK MANAGEMENT (one-time setup)
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. Idempotent (safe to run again).
--
-- DESIGN (no duplication — same philosophy as notifications/progress):
--   teacher_tasks             → ONE row per task created by Admin
--                                (title/description/type/section/due date).
--                                Assigning to All Teachers still stores the
--                                task ONCE here.
--   teacher_task_assignments  → one row per (task, teacher): the teacher's
--                                own status (not_completed / working /
--                                completed) + completion timestamp.
--                                Teacher-specific status lives ONLY here.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.teacher_tasks (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title       TEXT        NOT NULL DEFAULT '',
  description TEXT        NOT NULL DEFAULT '',
  task_type   TEXT        NOT NULL DEFAULT 'Other',
  section     TEXT,
  due_date    DATE,
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.teacher_task_assignments (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id      BIGINT      NOT NULL
    REFERENCES public.teacher_tasks (id) ON DELETE CASCADE,
  teacher_id   TEXT        NOT NULL,
  teacher_name TEXT        NOT NULL DEFAULT '',
  status       TEXT        NOT NULL DEFAULT 'not_completed'
    CHECK (status IN ('not_completed', 'working', 'completed')),
  completed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, teacher_id)
);

CREATE INDEX IF NOT EXISTS teacher_tasks_due_idx
  ON public.teacher_tasks (due_date);
CREATE INDEX IF NOT EXISTS teacher_tasks_section_idx
  ON public.teacher_tasks (section);
CREATE INDEX IF NOT EXISTS teacher_tasks_type_idx
  ON public.teacher_tasks (task_type);

CREATE INDEX IF NOT EXISTS task_assign_teacher_idx
  ON public.teacher_task_assignments (teacher_id);
CREATE INDEX IF NOT EXISTS task_assign_task_idx
  ON public.teacher_task_assignments (task_id);
CREATE INDEX IF NOT EXISTS task_assign_status_idx
  ON public.teacher_task_assignments (status);
CREATE INDEX IF NOT EXISTS task_assign_teacher_status_idx
  ON public.teacher_task_assignments (teacher_id, status);

-- ----------------------------------------------------------------------------
-- Row Level Security (same contract as the other Canaan tables: the app
-- signs in with its own username/password tables via the anon key, so
-- role scoping is enforced in the app layer — teachers only ever query
-- their own teacher_id; Admin manages everything).
-- ----------------------------------------------------------------------------
ALTER TABLE public.teacher_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_task_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read teacher tasks" ON public.teacher_tasks;
CREATE POLICY "app read teacher tasks"
  ON public.teacher_tasks FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "app write teacher tasks" ON public.teacher_tasks;
CREATE POLICY "app write teacher tasks"
  ON public.teacher_tasks FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "app update teacher tasks" ON public.teacher_tasks;
CREATE POLICY "app update teacher tasks"
  ON public.teacher_tasks FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "app delete teacher tasks" ON public.teacher_tasks;
CREATE POLICY "app delete teacher tasks"
  ON public.teacher_tasks FOR DELETE
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "app read task assignments"
  ON public.teacher_task_assignments;
CREATE POLICY "app read task assignments"
  ON public.teacher_task_assignments FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "app write task assignments"
  ON public.teacher_task_assignments;
CREATE POLICY "app write task assignments"
  ON public.teacher_task_assignments FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "app update task assignments"
  ON public.teacher_task_assignments;
CREATE POLICY "app update task assignments"
  ON public.teacher_task_assignments FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "app delete task assignments"
  ON public.teacher_task_assignments;
CREATE POLICY "app delete task assignments"
  ON public.teacher_task_assignments FOR DELETE
  TO anon, authenticated USING (true);

-- ----------------------------------------------------------------------------
-- Realtime (status changes + new tasks arrive with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'teacher_tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.teacher_tasks;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'teacher_task_assignments'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.teacher_task_assignments;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Overdue warnings: Admin writes a warning on an overdue assignment,
-- the teacher reads it in their task. One row per warning (history is
-- kept, newest first). Deleting the task/assignment cascades.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.teacher_task_warnings (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id UUID        NOT NULL
    REFERENCES public.teacher_task_assignments (id) ON DELETE CASCADE,
  task_id       BIGINT      NOT NULL
    REFERENCES public.teacher_tasks (id) ON DELETE CASCADE,
  teacher_id    TEXT        NOT NULL,
  teacher_name  TEXT        NOT NULL DEFAULT '',
  message       TEXT        NOT NULL DEFAULT '',
  created_by    TEXT,
  is_read       BOOLEAN     NOT NULL DEFAULT false,
  read_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS task_warn_assignment_idx
  ON public.teacher_task_warnings (assignment_id);
CREATE INDEX IF NOT EXISTS task_warn_teacher_idx
  ON public.teacher_task_warnings (teacher_id);
CREATE INDEX IF NOT EXISTS task_warn_unread_idx
  ON public.teacher_task_warnings (teacher_id, is_read)
  WHERE is_read = false;
CREATE INDEX IF NOT EXISTS task_warn_created_idx
  ON public.teacher_task_warnings (assignment_id, created_at DESC);

ALTER TABLE public.teacher_task_warnings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read task warnings"
  ON public.teacher_task_warnings;
CREATE POLICY "app read task warnings"
  ON public.teacher_task_warnings FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "app write task warnings"
  ON public.teacher_task_warnings;
CREATE POLICY "app write task warnings"
  ON public.teacher_task_warnings FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "app update task warnings"
  ON public.teacher_task_warnings;
CREATE POLICY "app update task warnings"
  ON public.teacher_task_warnings FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "app delete task warnings"
  ON public.teacher_task_warnings;
CREATE POLICY "app delete task warnings"
  ON public.teacher_task_warnings FOR DELETE
  TO anon, authenticated USING (true);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'teacher_task_warnings'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.teacher_task_warnings;
  END IF;
END $$;
