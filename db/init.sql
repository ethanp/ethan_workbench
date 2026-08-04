-- ethan_workbench deploy ledger (synced via PowerSync).

CREATE TABLE IF NOT EXISTS deploy_runs (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    project_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    force INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    source_hash TEXT,
    started_at BIGINT NOT NULL,
    finished_at BIGINT,
    exit_code INTEGER,
    log TEXT
);

CREATE INDEX IF NOT EXISTS deploy_runs_project_platform_started_idx
    ON deploy_runs (project_id, platform, started_at DESC);

CREATE TABLE IF NOT EXISTS deploy_state (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    platform TEXT NOT NULL,
    source_hash TEXT,
    last_status TEXT NOT NULL,
    last_deployed_at BIGINT,
    last_run_id TEXT,
    UNIQUE (project_id, platform)
);

CREATE INDEX IF NOT EXISTS deploy_state_project_idx
    ON deploy_state (project_id);
