-- ============================================================================
-- CANAAN APP — SCHOOL / CANAAN GALLERY (one-time setup) — v1
-- ============================================================================
-- Run this ONCE in Supabase: Dashboard → SQL Editor → New query → paste →
-- Run. It is idempotent (safe to run again; IF NOT EXISTS guards).
--
-- ARCHITECTURE (same pattern as download_center + download_center_files):
--   gallery_posts   → ONE row per gallery post (title, descriptions,
--                     event date/type/section, author, timestamps).
--   gallery_photos  → ONE row per photo (gallery_id → gallery_posts.id,
--                     public photo_url + storage_path + display_order).
--                     One event with many photos = 1 post + N photo rows
--                     (never a URL list crammed into one column).
--   Storage bucket `gallery-photos` (public) holds the image files at
--   `{gallery_id}/{timestamp}-{rand}-{filename}`.
--
-- Canonical values (enforced in the app layer, kept permissive here so
-- older app versions can never break on insert):
--   event_type : sunday_school | activity | special_program | others
--   section    : all | sub-junior | junior | senior   (single value per post)
--
-- Visibility: every post is published immediately (no drafts). Students
-- see `all` + their own section; teachers see every post. Enforced in
-- the app layer (GalleryService.visibleTo).
--
-- Notifications: publishing a gallery fans out through the EXISTING
-- `notifications` + `notification_recipients` tables
-- (type='gallery', destination='gallery') — see
-- NotificationService.galleryPublished. No new notification tables.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. gallery_posts
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gallery_posts (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title             TEXT NOT NULL DEFAULT '',
  description       TEXT NOT NULL DEFAULT '',
  event_description TEXT NOT NULL DEFAULT '',
  event_date        DATE,
  event_type        TEXT NOT NULL DEFAULT 'sunday_school',
  section           TEXT NOT NULL DEFAULT 'all',
  created_by        TEXT NOT NULL DEFAULT '',
  created_by_id     TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS event_description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS event_date DATE;
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS event_type TEXT NOT NULL DEFAULT 'sunday_school';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT 'all';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS created_by TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS created_by_id TEXT;
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.gallery_posts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ----------------------------------------------------------------------------
-- 2. gallery_photos
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gallery_photos (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  gallery_id    BIGINT NOT NULL
    REFERENCES public.gallery_posts (id) ON DELETE CASCADE,
  photo_url     TEXT NOT NULL DEFAULT '',
  storage_path  TEXT NOT NULL DEFAULT '',
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.gallery_photos ADD COLUMN IF NOT EXISTS gallery_id BIGINT;
ALTER TABLE public.gallery_photos ADD COLUMN IF NOT EXISTS photo_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_photos ADD COLUMN IF NOT EXISTS storage_path TEXT NOT NULL DEFAULT '';
ALTER TABLE public.gallery_photos ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.gallery_photos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Backfill orphan guard: photos whose post is gone are removed by the
-- FK cascade above; nothing else to repair.

-- ----------------------------------------------------------------------------
-- 3. Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS gallery_posts_date_idx
  ON public.gallery_posts (event_date DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS gallery_posts_created_idx
  ON public.gallery_posts (created_at DESC);
CREATE INDEX IF NOT EXISTS gallery_posts_type_idx
  ON public.gallery_posts (event_type);
CREATE INDEX IF NOT EXISTS gallery_photos_gallery_idx
  ON public.gallery_photos (gallery_id, display_order);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (tables)
-- ----------------------------------------------------------------------------
-- The Canaan app signs in with its own username/password tables (it uses
-- the anon key directly, not Supabase Auth / auth.uid()). RLS is enabled
-- and every role used by the app (anon + authenticated) is granted access;
-- per-user visibility (section) is enforced in the app layer
-- (GalleryService.visibleTo) at query time.
ALTER TABLE public.gallery_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gallery_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app read gallery_posts" ON public.gallery_posts;
CREATE POLICY "app read gallery_posts"
  ON public.gallery_posts FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert gallery_posts" ON public.gallery_posts;
CREATE POLICY "app insert gallery_posts"
  ON public.gallery_posts FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update gallery_posts" ON public.gallery_posts;
CREATE POLICY "app update gallery_posts"
  ON public.gallery_posts FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete gallery_posts" ON public.gallery_posts;
CREATE POLICY "app delete gallery_posts"
  ON public.gallery_posts FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app read gallery_photos" ON public.gallery_photos;
CREATE POLICY "app read gallery_photos"
  ON public.gallery_photos FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "app insert gallery_photos" ON public.gallery_photos;
CREATE POLICY "app insert gallery_photos"
  ON public.gallery_photos FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "app update gallery_photos" ON public.gallery_photos;
CREATE POLICY "app update gallery_photos"
  ON public.gallery_photos FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "app delete gallery_photos" ON public.gallery_photos;
CREATE POLICY "app delete gallery_photos"
  ON public.gallery_photos FOR DELETE
  TO anon, authenticated
  USING (true);

-- ----------------------------------------------------------------------------
-- 5. Storage bucket `gallery-photos` (public read, app write)
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('gallery-photos', 'gallery-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "app read gallery photos" ON storage.objects;
CREATE POLICY "app read gallery photos"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'gallery-photos');

DROP POLICY IF EXISTS "app upload gallery photos" ON storage.objects;
CREATE POLICY "app upload gallery photos"
  ON storage.objects FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'gallery-photos');

DROP POLICY IF EXISTS "app update gallery photos" ON storage.objects;
CREATE POLICY "app update gallery photos"
  ON storage.objects FOR UPDATE
  TO anon, authenticated
  USING (bucket_id = 'gallery-photos')
  WITH CHECK (bucket_id = 'gallery-photos');

DROP POLICY IF EXISTS "app delete gallery photos" ON storage.objects;
CREATE POLICY "app delete gallery photos"
  ON storage.objects FOR DELETE
  TO anon, authenticated
  USING (bucket_id = 'gallery-photos');

-- ----------------------------------------------------------------------------
-- 6. Realtime (galleries update with no refresh)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'gallery_posts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.gallery_posts;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'gallery_photos'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.gallery_photos;
  END IF;
END $$;
