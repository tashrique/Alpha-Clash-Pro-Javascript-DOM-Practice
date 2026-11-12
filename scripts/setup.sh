#!/usr/bin/env bash
# Reads .env, writes Config.local.xcconfig (git-ignored), and generates LyricDash.xcodeproj.
# Usage: ./scripts/setup.sh            (run again whenever you change .env)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example. Fill it in, then run ./scripts/setup.sh again."
  exit 1
fi

# Parse KEY=VALUE lines without executing the file.
get() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//' | xargs; }

TEAM="$(get APPLE_TEAM_ID)"
BUNDLE="$(get BUNDLE_ID)"
GROUP="$(get APP_GROUP_ID)"
CLIENT="$(get SPOTIFY_CLIENT_ID)"

[[ -z "$TEAM" ]]   && echo "warning: APPLE_TEAM_ID is empty. You can also pick your team in Xcode > Signing & Capabilities."
[[ -z "$CLIENT" ]] && echo "warning: SPOTIFY_CLIENT_ID is empty. 'Connect Spotify' won't work until you set it."
[[ "$GROUP" != group.* ]] && { echo "error: APP_GROUP_ID must start with 'group.'"; exit 1; }

cat > Config.local.xcconfig <<EOF
// Generated from .env by scripts/setup.sh. Do not commit.
DEVELOPMENT_TEAM = $TEAM
BUNDLE_ID_BASE = $BUNDLE
APP_GROUP_ID = $GROUP
SPOTIFY_CLIENT_ID = $CLIENT
EOF
echo "Wrote Config.local.xcconfig"

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then brew install xcodegen; else
    echo "error: install XcodeGen first (brew install xcodegen)"; exit 1; fi
fi
xcodegen generate
echo "Done. Open LyricDash.xcodeproj, pick your iPhone, press Run."
