import 'package:powersync/powersync.dart';

/// Client mirror of `db/init.sql`. PowerSync adds `id` automatically.
final Schema ethanWorkbenchSchema = Schema([
  Table('deploy_runs', [
    Column.text('project_id'),
    Column.text('project_name'),
    Column.text('platform'),
    Column.integer('force'),
    Column.text('status'),
    Column.text('source_hash'),
    Column.integer('started_at'),
    Column.integer('finished_at'),
    Column.integer('exit_code'),
    Column.text('log'),
  ]),
  Table('deploy_state', [
    Column.text('project_id'),
    Column.text('platform'),
    Column.text('source_hash'),
    Column.text('last_status'),
    Column.integer('last_deployed_at'),
    Column.text('last_run_id'),
  ]),
]);
