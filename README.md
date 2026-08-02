# Ethan Workbench

Personal Flutter workbench for your app fleet: a macOS companion runs a LAN agent that wraps `deploy.rb`, an iPhone app triggers deploys, and Mac-side tools (line age, more later) operate on local repos.

## Security

Auth is **pairing PIN → session token**, not open LAN access:

1. The Mac companion shows a 6-digit PIN (rotates every minute, or sooner via **New PIN**).
2. The phone enters that PIN once and receives a long-lived bearer token (stored locally).
3. Project list / deploy / job APIs require `Authorization: Bearer <token>`.
4. The Mac lists each connected phone and can **Revoke** one session or **Revoke all**. Revocation is immediate on the next phone request (including mid-deploy polls); the phone returns to the pairing screen. **Unpair** on the phone only clears its own stored token.

Open without a token: `/health`, `/pair`. Everything else needs a valid session.

Trust boundary is still your LAN — anyone who can reach the agent and see/enter a live PIN can pair until you revoke them. Do not expose the agent beyond a trusted network.

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

```bash
flutter pub get
```

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
