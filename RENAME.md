# Renaming Ethan Workbench

Product identity lives in one place for Dart: [`lib/app_identity.dart`](lib/app_identity.dart)
(`syncAppName`, `displayName`, `localDatabaseStem`).

Server / iOS client `.env` keys are **unbranded** (`SERVER_*`, `FLUTTER_ROOT`,
`DEPLOY_RB`) so a product rename does not churn those. Deploy phase lines use
`DEPLOY_PHASE:`.

Shared convention for all sync apps: workspace cursor rule `sync-app-identity`.

## Checklist

1. Rename the Flutter folder + `pubspec.yaml` `name` + every `package:…` import
2. Update `AppIdentity.syncAppName` / `displayName` (and keep `localDatabaseStem` stable unless you intend a fresh on-device DB)
3. Bundle IDs + platform display names (`Info.plist` / macOS `AppInfo.xcconfig`)
4. Strings in `db/*.sql` + `db/powersync.yaml` (must match the folder / sync app name)
5. Infra `.env` / `.env.prod` keys `{NEW}_POSTGRES_PASSWORD` / `{NEW}_POWERSYNC_JWT_KEY`
6. `./sync-app-db.sh <new_app>` (and regenerate compose) + `./reset-sync-app-db.sh <new_app>` on the server
7. Optional: GitHub repo rename

Default deploy.rb path is `$FLUTTER_ROOT/<syncAppName>/deploy.rb` — it follows `AppIdentity.syncAppName` automatically once the folder matches.
