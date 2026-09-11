-- ============================================================================
-- CANAAN APP — LANGUAGE PREFERENCE + BILINGUAL NOTIFICATIONS (one-time)
-- ============================================================================
-- Run this ONCE in Supabase: SQL Editor → New query → paste → Run.
-- Idempotent (safe to re-run).
--
-- 1. `language` ('en' | 'ne', default 'en') on the three profile tables
--    so each user's choice roams across devices. The app ALSO keeps a
--    local copy per user, so everything works even before this runs.
-- 2. `title_ne` / `message_ne` on notifications: system notification
--    titles/messages in Nepali. Displayed when the reader uses Nepali;
--    English otherwise. User-typed content is never translated.
-- ============================================================================

ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en';
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en';
ALTER TABLE public."admin"
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en';

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS title_ne TEXT;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS message_ne TEXT;
