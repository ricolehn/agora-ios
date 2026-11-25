#!/usr/bin/env bash
# Starts a throwaway Agora server (the web repository's backend + PocketBase) on http://localhost:3000 for the
# simulator screenshots. Usage: start-server.sh <agora checkout> <work dir>. Leaves server.log and pocketbase.log in
# the work dir; the server runs in the background until the job ends.
set -euo pipefail

agora="$(cd "$1" && pwd)"
work="$(mkdir -p "$2" && cd "$2" && pwd)"
port="${PORT:-3000}"
pb_port="${POCKETBASE_PORT:-8090}"

# Same PocketBase version as the server's Docker image
version="$(sed -n 's/^ARG POCKETBASE_VERSION=//p' "$agora/Dockerfile")"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) asset="darwin_arm64" ;;
  Darwin-x86_64) asset="darwin_amd64" ;;
  Linux-x86_64) asset="linux_amd64" ;;
  Linux-aarch64) asset="linux_arm64" ;;
  *) echo "Unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
if [ ! -x "$work/pocketbase" ]; then
  curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${version}/pocketbase_${version}_${asset}.zip" -o "$work/pb.zip"
  unzip -oq "$work/pb.zip" pocketbase -d "$work"
fi

(cd "$agora/backend" && npm ci --omit=dev --no-audit --no-fund --loglevel=error)

mkdir -p "$work/pb" "$work/data"
"$work/pocketbase" serve --dir "$work/pb" --automigrate=false --http "127.0.0.1:$pb_port" >"$work/pocketbase.log" 2>&1 &
for _ in $(seq 1 60); do curl -fsS "http://127.0.0.1:$pb_port/api/health" >/dev/null 2>&1 && break; sleep 1; done

# The test stand-in of the built web app is enough: the app reads only /assets/config.js (served by the backend)
PORT="$port" POCKETBASE_PORT="$pb_port" POCKETBASE_BIN="$work/pocketbase" POCKETBASE_DIR="$work/pb" DATA_DIR="$work/data" \
  FRONTEND_DIR="$agora/tests/fixtures/frontend" node "$agora/backend/server.js" >"$work/server.log" 2>&1 &
for _ in $(seq 1 60); do curl -fsS "http://127.0.0.1:$port/api/status" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:$port/api/status"; echo
