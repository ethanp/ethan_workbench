# Phone Deploy

Personal Flutter tool: a macOS companion runs a LAN agent that wraps `deploy.rb`, and an iPhone app lists your local Flutter projects and triggers iOS builds/installs.

## Security

The Mac agent has **no authentication**. Anyone on the same network who can reach the agent port can list projects and start deploys. Use only on a trusted LAN (or add auth before exposing further).

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

Open Phone Deploy on the phone, pull to refresh the project list, tap an app to deploy.

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
