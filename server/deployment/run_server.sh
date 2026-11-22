#!/usr/bin/env bash
# 전용 게임 서버 실행 (헤드리스). 사용법: GODOT=/path/to/godot server/deployment/run_server.sh [port] [max_players] [map]
set -euo pipefail
GODOT="${GODOT:?set GODOT to the Godot executable (console build recommended)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${1:-7777}"
MAX="${2:-8}"
MAP="${3:-lobby_plaza}"
exec "$GODOT" --headless --path "$ROOT" -- --server --port="$PORT" --max-players="$MAX" --map="$MAP"
