-- Run as postgres/viant superuser once to create the phone_deploy database.
-- Source of truth: Flutter/phone_deploy/db/create_database.sql

SELECT 'CREATE DATABASE phone_deploy OWNER phone_deploy'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'phone_deploy')\gexec

GRANT ALL PRIVILEGES ON DATABASE phone_deploy TO phone_deploy;
