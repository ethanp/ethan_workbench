-- ethan_workbench role bootstrap
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ethan_workbench') THEN
    CREATE ROLE ethan_workbench LOGIN;
  END IF;
END
$$;

ALTER ROLE ethan_workbench WITH REPLICATION;
