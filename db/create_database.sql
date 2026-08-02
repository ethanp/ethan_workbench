-- Run as postgres/viant superuser once to create the ethan_workbench database.
-- Source of truth: Flutter/ethan_workbench/db/create_database.sql

SELECT 'CREATE DATABASE ethan_workbench OWNER ethan_workbench'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ethan_workbench')\gexec

GRANT ALL PRIVILEGES ON DATABASE ethan_workbench TO ethan_workbench;
