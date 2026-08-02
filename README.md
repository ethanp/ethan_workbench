# Ethan Workbench

Personal Flutter workbench for your app fleet: a macOS companion runs a LAN agent that wraps `deploy.rb`, an iPhone app triggers deploys, and Mac-side tools (line age, more later) operate on local repos.

## Security

Auth is **pairing PIN → session token**, not open LAN access:

1. The Mac companion shows a 6-digit PIN (rotates every minute, or sooner via **New PIN**).
2. The phone enters that PIN once and receives a long-lived bearer token (stored locally).
3. Project list / deploy / job APIs require `Authorization: Bearer <token>`.
4. The Mac lists each connected phone and can **Revoke** one session or **Revoke all**. Revocation is immediate on the next phone request (including mid-deploy polls); the phone returns to the pairing screen. **Unpair** on the phone only clears its own stored token.
5. Paired sessions survive Mac companion restarts: the Mac stores **SHA-256 hashes** of tokens under Application Support (`paired_phone_sessions.json`, mode `600`). Raw tokens are never written on the Mac. Sessions older than 180 days require a fresh PIN.

Open without a token: `/health`, `/pair`. Everything else needs a valid session.

Keep the agent on a network you trust (home LAN / Tailscale). A stranger who can reach it **and** catch a live PIN could pair and then **deploy or run your Flutter apps** on your Mac/sim/phone — annoying and disruptive, but of course NOT a dangerous path to your bank credentials . Revoke sessions on the Mac if that happens. Don’t port-forward the agent to the public internet.

## Setup

```bash
cp .env.example .env
```

Edit `.env`:

| Variable | Purpose |
|---|---|
| `AGENT_HOST` | Mac Bonjour / local hostname, e.g. `MacBook-Pro.local` |
| `AGENT_PORT` | Agent port (default `8787`) |
| `FLUTTER_ROOT` | Absolute path to the folder that contains your Flutter apps |
| `DEPLOY_RB` | Optional. Defaults to `$FLUTTER_ROOT/ethan_workbench/deploy.rb` |

Sync (optional but required for deploy history / ledger) uses the shared host keys in the same `.env`: `SERVER_HOST_LAN`, `SERVER_HOST_TAILSCALE`, `POWERSYNC_JWT_SECRET`.

```bash
flutter pub get
```

## Local data (debugging)

| What | Where |
|---|---|
| Sync / agent env | `Flutter/ethan_workbench/.env` (gitignored) |
| PowerSync SQLite | `~/Documents/workbench_powersync.db` (`AppIdentity.localDatabaseStem`) |
| macOS app support | `~/Library/Application Support/com.ethan.ethanWorkbench` |
| Bundle id | `com.ethan.ethanWorkbench` |

Server-side history lives in Postgres `ethan_workbench.deploy_runs` on the home server.

## Run

**1. Mac companion** (leave running — this is the agent):

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

Open Ethan Workbench on the phone, enter the PIN shown on the Mac, then deploy projects from the list.

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
