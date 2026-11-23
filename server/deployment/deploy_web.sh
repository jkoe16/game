#!/usr/bin/env bash
# 웹 빌드 + Firebase Hosting 배포 (https://game-28f1b.web.app)
#
# 사용법 (Git Bash, 프로젝트 루트에서):
#   export GODOT="/c/Users/User/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
#   bash server/deployment/deploy_web.sh            # 빌드 + Hosting 배포
#   bash server/deployment/deploy_web.sh --rules    # + Firestore 보안 규칙 배포
#
# 준비: Godot 웹 내보내기 템플릿 4.7.2, config/firebase.cfg (없으면 로그인 없는 빌드),
#       Firebase CLI 로그인 (npx firebase-tools login)
set -euo pipefail
GODOT="${GODOT:?set GODOT to the Godot console executable}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f config/firebase.cfg ] || echo "경고: config/firebase.cfg 없음 → 로그인 없는 빌드가 됩니다"

rm -rf build/web && mkdir -p build/web && touch build/.gdignore
"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
[ -f build/web/index.wasm ] || { echo "내보내기 실패"; exit 1; }

rm -rf server/firebase/public && cp -r build/web server/firebase/public
TARGETS="hosting"
[ "${1:-}" = "--rules" ] && TARGETS="hosting,firestore:rules"
cd server/firebase
npx --yes firebase-tools deploy --only "$TARGETS" --project game-28f1b --non-interactive
