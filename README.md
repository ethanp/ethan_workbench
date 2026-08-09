# Ethan Workbench

Personal Flutter workbench for your app fleet: a macOS companion runs a LAN **server** that wraps `deploy.rb`, an **iOS client** triggers deploys, and Mac-side tools (line age, more later) operate on local repos.

## Security

Auth is a **shared password** from `.env`, not open LAN access:

1. Set `SERVER_PASSWORD` in the Mac companion `.env` (gitignored) and restart the server.
2. On the iPhone, enter that same password once. It is stored locally and sent as `Authorization: Bearer <password>` on every request.
3. Project list / deploy / job APIs require a matching bearer password. `/health` stays open for reachability checks.
4. If `SERVER_PASSWORD` is empty/unset, the server **fails closed** (everything except `/health` returns 401).
5. To revoke phones: change `SERVER_PASSWORD` and restart the Mac server. Use **Sign out** on the phone to clear its stored password only.

Keep the server on a network you trust (home LAN / Tailscale). A stranger who can reach it **and** know the password could **deploy or run your Flutter apps** on your Mac/sim/phone — annoying and disruptive, but of course not a path to bank credentials. Don’t port-forward the server to the public internet.

## Setup

```bash
cp .env.example .env
```

Edit `.env`:

| Variable | Purpose |
|---|---|
| `SERVER_HOST` | Mac Bonjour / local hostname, e.g. `MacBook-Pro.local` |
| `SERVER_PORT` | Deploy server port (default `8787`) |
| `SERVER_PASSWORD` | Shared password for the iOS client (required) |
| `FLUTTER_ROOT` | Absolute path to the folder that contains your Flutter apps |
| `DEPLOY_RB` | Optional. Defaults to `$FLUTTER_ROOT/ethan_workbench/deploy.rb` |

Sync (optional but required for deploy history / ledger) uses the shared host keys in the same `.env`: `SERVER_HOST_LAN`, `SERVER_HOST_TAILSCALE`, `POWERSYNC_JWT_SECRET`.

```bash
flutter pub get
```

## Local data (debugging)

| What | Where |
|---|---|
| Sync / server env | `Flutter/ethan_workbench/.env` (gitignored) |
| PowerSync SQLite | `~/Documents/workbench_powersync.db` (`AppIdentity.localDatabaseStem`) |
| macOS app support | `~/Library/Application Support/com.ethan.ethanWorkbench` |
| Bundle id | `com.ethan.ethanWorkbench` |

Server-side history lives in Postgres `ethan_workbench.deploy_runs` on the home server.

## Run

**1. Mac companion** (leave running — this is the server for the iOS client):

```bash
cd ethan_workbench
flutter run -d macos
```

**2. iPhone app** (same Wi‑Fi, phone unlocked, Developer Mode on):

```bash
cd ethan_workbench
ruby deploy.rb ios --force
# or: flutter run -d <your-iphone-id>
```

Open Ethan Workbench on the phone, enter the shared `SERVER_PASSWORD`, then deploy projects from the list.

On the Mac companion, projects with an `ios/` folder also get a **meSim** plate: boots the iPhone Simulator named `meSim` if needed, then `flutter run` on it (same hot reload / stop controls as macOS Run).

## Manual deploys from other apps

`deploy.rb` ships in this repo. From any Flutter app directory:

```bash
ruby ../ethan_workbench/deploy.rb ios
ruby ../ethan_workbench/deploy.rb ios --force
ruby ../ethan_workbench/deploy.rb macos
```

## Dependencies

- [ethan_utils](https://github.com/ethanp/ethan_utils) (via path)
- Flutter, Xcode, a physical iPhone for device installs

## Renaming this app

See [RENAME.md](RENAME.md).
