# Phone Deploy

Personal Flutter tool: a macOS companion runs a LAN agent that wraps `deploy.rb`, and an iPhone app lists your local Flutter projects and triggers iOS builds/installs.

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
| `PHONE_DEPLOY_AGENT_HOST` | Mac Bonjour / local hostname, e.g. `MacBook-Pro.local` |
| `PHONE_DEPLOY_AGENT_PORT` | Agent port (default `8787`) |
| `PHONE_DEPLOY_FLUTTER_ROOT` | Absolute path to the folder that contains your Flutter apps |
| `PHONE_DEPLOY_DEPLOY_RB` | Optional. Defaults to `$PHONE_DEPLOY_FLUTTER_ROOT/phone_deploy/deploy.rb` |

```bash
flutter pub get
```

## Run

**1. Mac companion** (leave running — this is the agent):

```bash
cd phone_deploy
flutter run -d macos
```

**2. iPhone app** (same Wi‑Fi, phone unlocked, Developer Mode on):

```bash
cd phone_deploy
ruby deploy.rb ios --force
# or: flutter run -d <your-iphone-id>
```

Open Phone Deploy on the phone, enter the PIN shown on the Mac, then deploy projects from the list.

## Manual deploys from other apps

`deploy.rb` ships in this repo. From any Flutter app directory:

```bash
ruby ../phone_deploy/deploy.rb ios
ruby ../phone_deploy/deploy.rb ios --force
ruby ../phone_deploy/deploy.rb macos
```

## Dependencies

- [ethan_utils](https://github.com/ethanp/ethan_utils) (via Git)
- Flutter, Xcode, a physical iPhone for device installs
