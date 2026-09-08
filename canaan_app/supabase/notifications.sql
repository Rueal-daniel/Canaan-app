-- ============================================================================
-- CANAAN APP — CENTRAL NOTIFICATION SYSTEM (one-time setup) — v2
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards +
-- information_schema checks everywhere).
--
-- ARCHITECTURE (event-based, no duplication):
--   Existing feature tables (attendance_reports, notices,
--   student_leave_applications, lesson_plans, memory_verses,
--   credential_change_requests, password_reset_requests, download_center,
--   teacher_attendance, recitation_*) remain the SOURCE OF TRUTH.
--
--   notifications            → ONE row per event. The app ADOPTS the
--                               pre-existing legacy table
--                               (id bigint, title, message, audience,
--                               sender_name, sender_id, read_by,
--                               created_at) and only ADDS the missing
--                               event columns below. Legacy rows are kept
--                               untouched and keep working.
--   notification_recipients  → WHO receives it + read/unread state.
--                               1 notice to 100 users = 1 event + 100 rows.
--   notification_archive     → per-recipient snapshots of old notifications
--                               moved out of the hot tables (retention).
--
-- NOTE on related_id / user_id: TEXT on purpose. Feature tables use mixed
-- key types (uuid for students/teachers/admin, bigint for notices,
-- lesson_plans, memory_verses, ...). TEXT holds either form.
-- ============================================================================

-- Required for gen_random_uuid() (recipient/archive ids).
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. notifications — adopt the legacy table, add missing event columns
-- ----------------------------------------------------------------------------
-- Fresh install (no legacy table yet): create it in the legacy-compatible
-- shape so every deployment ends up with the same schema.
CREATE TABLE IF NOT EXISTS public.notifications (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title         TEXT NOT NULL DEFAULT '',
  message       TEXT NOT NULL DEFAULT '',
  audience      TEXT,
  sender_name   TEXT,
  sender_id     TEXT,
  read_by       TEXT[] NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  type          TEXT,
  related_id    TEXT,
  destination   TEXT NOT NULL DEFAULT 'dashboard',
  audience_type TEXT,
  section       TEXT,
  expires_at    TIMESTAMPTZ
);

-- Existing deployment: add whatever event columns are missing.
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS related_id TEXT;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS destination TEXT NOT NULL DEFAULT 'dashboard';
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS audience_type TEXT;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS section TEXT;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Guarantee the app's minimal insert payload
-- (type/title/message/related_id/destination/audience_type/section)
-- can ALWAYS be written: any other NOT NULL column without a default
-- gets a harmless default (or is made nullable). Legacy reads are
-- unaffected; existing rows are untouched.
DO $$
DECLARE
  col RECORD;
BEGIN
  FOR col IN
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND is_nullable = 'NO'
      AND column_default IS NULL
      AND column_name NOT IN ('id', 'title', 'message')
  LOOP
    IF col.data_type IN ('text', 'character varying', 'character') THEN
      EXECUTE format(
        'ALTER TABLE public.notifications ALTER COLUMN %I SET DEFAULT %L',
        col.column_name, ''
      );
    ELSIF col.data_type LIKE 'timestamp%' THEN
      EXECUTE format(
        'ALTER TABLE public.notifications ALTER COLUMN %I SET DEFAULT now()',
        col.column_name
      );
    ELSE
      EXECUTE format(
        'ALTER TABLE public.notifications ALTER COLUMN %I DROP NOT NULL',
        col.column_name
      );
    END IF;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. notification_recipients — who receives it + read state
--    (BIGINT key to match the legacy notifications.id)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_recipients (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id BIGINT      NOT NULL
    REFERENCES public.notifications (id) ON DELETE CASCADE,
  user_id         TEXT        NOT NULL,
  is_read         BOOLEAN     NOT NULL DEFAULT false,
  read_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One recipient row per (event, user): the duplicate-prevention guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS notification_recipients_unique_event_user
  ON public.notification_recipients (notification_id, user_id);

-- ----------------------------------------------------------------------------
-- 3. notification_archive — cold storage for old per-recipient snapshots
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_archive (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  original_notification_id BIGINT,
  user_id                 TEXT        NOT NULL,
  type                    TEXT        NOT NULL DEFAULT '',
  title                   TEXT        NOT NULL DEFAULT '',
  message                 TEXT        NOT NULL DEFAULT '',
  related_id              TEXT,
  destination             TEXT        NOT NULL DEFAULT 'dashboard',
  is_read                 BOOLEAN     NOT NULL DEFAULT true,
  read_at                 TIMESTAMPTZ,
  original_created_at     TIMESTAMPTZ,
  archived_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 4. Indexes (fast "show my unread notifications" at scale)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS notifications_created_at_idx
  ON public.notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_type_idx
  ON public.notifications (type);
CREATE INDEX IF NOT EXISTS notifications_related_idx
  ON public.notifications (type, related_id);
CREATE INDEX IF NOT EXISTS notifications_expires_idx
  ON public.notifications (expires_at);

CREATE INDEX IF NOT EXISTS notification_recipients_user_idx
  ON public.notification_recipients (user_id);
CREATE INDEX IF NOT EXISTS notification_recipients_notification_idx
  ON public.notification_recipients (notification_id);
CREATE INDEX IF NOT EXISTS notification_recipients_unread_idx
  ON public.notification_recipients (user_id, is_read)
  WHERE is_read = false;
CREATE INDEX IF NOT EXISTS notification_recipients_created_idx
  ON public.notification_recipients (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS notification_archive_user_idx
  ON public.notification_archive (user_id, archived_at DESC);

-- ----------------------------------------------------------------------------
-- 5. Row Level Security
-- ----------------------------------------------------------------------------
-- The Canaan app signs in with its own username/password tables (it uses
-- the anon key directly, not Supabase Auth / auth.uid()). RLS is enabled
-- and every role used by the app (anon + authenticated) is granted access;
-- per-user isolation is enforced in the app layer (NotificationService
-- always filters notification_recipients by the logged-in user_id).
-- These policies only WIDEN access to what the app needs; existing reads
-- (e.g. the teacher dashboard count) keep working.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_archive ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read notifications" ON public.notifications;
CREATE POLICY "app read notifications"
  ON public.notifications FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert notifications" ON public.notifications;
CREATE POLICY "app insert notifications"
  ON public.notifications FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update notifications" ON public.notifications;
CREATE POLICY "app update notifications"
  ON public.notifications FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete notifications" ON public.notifications;
CREATE POLICY "app delete notifications"
  ON public.notifications FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read recipients" ON public.notification_recipients;
CREATE POLICY "app read recipients"
  ON public.notification_recipients FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert recipients" ON public.notification_recipients;
CREATE POLICY "app insert recipients"
  ON public.notification_recipients FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update recipients" ON public.notification_recipients;
CREATE POLICY "app update recipients"
  ON public.notification_recipients FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete recipients" ON public.notification_recipients;
CREATE POLICY "app delete recipients"
  ON public.notification_recipients FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read archive" ON public.notification_archive;
CREATE POLICY "app read archive"
  ON public.notification_archive FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app write archive" ON public.notification_archive;
CREATE POLICY "app write archive"
  ON public.notification_archive FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete archive" ON public.notification_archive;
CREATE POLICY "app delete archive"
  ON public.notification_archive FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 6. Realtime (bell badge updates with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notification_recipients'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_recipients;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 7. Optional cleanup helper: archive everything older than [days] (default 90)
--    The app calls this opportunistically; run it manually any time too:
--      SELECT archive_old_notifications(90);
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_old_notifications(days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  cutoff TIMESTAMPTZ := now() - (days || ' days')::INTERVAL;
  moved  INTEGER := 0;
BEGIN
  INSERT INTO public.notification_archive (
    original_notification_id, user_id, type, title, message,
    related_id, destination, is_read, read_at, original_created_at
  )
  SELECT n.id, r.user_id, COALESCE(n.type, ''), n.title, n.message,
         n.related_id, COALESCE(n.destination, 'dashboard'),
         r.is_read, r.read_at, n.created_at
  FROM public.notifications n
  JOIN public.notification_recipients r ON r.notification_id = n.id
  WHERE n.created_at < cutoff
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS moved = ROW_COUNT;

  DELETE FROM public.notifications n WHERE n.created_at < cutoff;

  RETURN moved;
END;
$func$;
