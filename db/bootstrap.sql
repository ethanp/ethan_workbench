-- phone_deploy role bootstrap
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phone_deploy') THEN
    CREATE ROLE phone_deploy LOGIN;
  END IF;
END
$$;

ALTER ROLE phone_deploy WITH REPLICATION;
