-- Persist deploy console logs on deploy_runs for history / Cursor debugging.
ALTER TABLE deploy_runs
  ADD COLUMN IF NOT EXISTS log TEXT;
