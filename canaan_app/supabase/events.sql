-- ============================================================================
-- CANAAN APP — EVENTS & CALENDAR (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- ARCHITECTURE (same pattern as notices / download_center):
--   events  → SOURCE OF TRUTH for every calendar event. One row per event,
--              whether created via "Add Event" or "Create Monthly Program".
--              Monthly programs are just N rows sharing the same month —
--              no separate monthly table, so realtime + notifications +
--              teacher/student filtering all work uniformly.
--
-- Canonical values (enforced in the app layer, kept permissive here so
-- older app versions can never break on insert):
--   event_type : sunday_school | activity | special_program | others
--   audience   : everyone | students | teachers
--   section    : all | sub-junior | junior | senior
--                (multi-section, e.g. "Junior + Senior", is stored as a
--                comma-separated slug list: 'junior,senior')
--   status     : published | draft
--                (only `published` rows are visible to teachers/students)
--
-- Notifications: publishing an event fans out through the EXISTING
-- `notifications` + `notification_recipients` tables
-- (type='event', destination='events_calendar') — see
-- NotificationService.eventPublished. No new notification tables.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. events table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.events (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title           TEXT NOT NULL DEFAULT '',
  event_date      DATE NOT NULL,
  start_time      TEXT NOT NULL DEFAULT '',
  end_time        TEXT NOT NULL DEFAULT '',
  location        TEXT NOT NULL DEFAULT '',
  event_type      TEXT NOT NULL DEFAULT 'sunday_school',
  description     TEXT NOT NULL DEFAULT '',
  audience        TEXT NOT NULL DEFAULT 'everyone',
  section         TEXT NOT NULL DEFAULT 'all',
  attachment_url  TEXT NOT NULL DEFAULT '',
  attachment_name TEXT NOT NULL DEFAULT '',
  status          TEXT NOT NULL DEFAULT 'published',
  created_by      TEXT NOT NULL DEFAULT '',
  created_by_id   TEXT,
  published_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Existing deployment: add whatever columns are missing.
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS event_date DATE;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS start_time TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS end_time TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS event_type TEXT NOT NULL DEFAULT 'sunday_school';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS audience TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT 'all';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS attachment_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS attachment_name TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS created_by TEXT NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS created_by_id TEXT;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Backfill: event_date must never be null (default to today for legacy rows).
UPDATE public.events SET event_date = CURRENT_DATE WHERE event_date IS NULL;

-- ----------------------------------------------------------------------------
-- 2. Indexes (fast calendar + list queries)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS events_date_idx ON public.events (event_date);
CREATE INDEX IF NOT EXISTS events_status_date_idx ON public.events (status, event_date);
CREATE INDEX IF NOT EXISTS events_created_idx ON public.events (created_at DESC);
CREATE INDEX IF NOT EXISTS events_type_idx ON public.events (event_type);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- ----------------------------------------------------------------------------
-- The Canaan app signs in with its own username/password tables (it uses
-- the anon key directly, not Supabase Auth / auth.uid()). RLS is enabled
-- and every role used by the app (anon + authenticated) is granted access;
-- per-user visibility (audience/section/status) is enforced in the app
-- layer (EventService.visibleTo) at query time.
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read events" ON public.events;
CREATE POLICY "app read events"
  ON public.events FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert events" ON public.events;
CREATE POLICY "app insert events"
  ON public.events FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update events" ON public.events;
CREATE POLICY "app update events"
  ON public.events FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete events" ON public.events;
CREATE POLICY "app delete events"
  ON public.events FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 4. Realtime (calendars + lists update with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
  END IF;
END $$;
