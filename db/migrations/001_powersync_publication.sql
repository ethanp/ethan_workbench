-- PowerSync logical-replication publication for ethan_workbench.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'powersync') THEN
    CREATE PUBLICATION powersync FOR TABLE
      deploy_runs,
      deploy_state;
  END IF;
END
$$;
