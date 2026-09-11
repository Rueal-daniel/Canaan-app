-- CANAAN ID NUMBERS (idempotent)
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS student_id_number TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS students_id_number_idx
  ON public.students (student_id_number);

-- Cleanup: teacher/admin ID columns are not used — drop them if a
-- previous version of this script created them.
ALTER TABLE public.teachers
  DROP COLUMN IF EXISTS teacher_id_number;

ALTER TABLE public."admin"
  DROP COLUMN IF EXISTS admin_id_number;
