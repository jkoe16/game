#!/usr/bin/env bash
# 네트워크 통합 테스트: 헤드리스 전용 서버 1개 + 헤드리스 봇 클라이언트 여러 개를 실제 프로세스로 실행.
#
# 사용법: GODOT=/path/to/godot_console tests/integration/net_test.sh [scenario] [out_dir]
#   scenario = basic    : 정상 봇 2 + 위조/플러드/버전불일치/무응답 클라이언트 (보안·동기화 검증, 개발 인증)
#            = capacity : 정상 봇 9 → 8명 입장, 1명 room_full 거절 (정원 검증, 개발 인증)
#            = auth     : 목 Firebase 서버 + Firebase 인증 서버. 게스트/이메일/위조 토큰/토큰 없음/중복 로그인
#            = authflow : 목 Firebase 대상 클라이언트 Auth 흐름 (게스트→이메일 연결, 갱신, 복원, Google, 오류)
#            = data     : 목 Firebase+Firestore. 프로필 저장·보안 규칙 거부·서버의 프로필 로드·플레이 기록 저장
#            = minigames: 미니게임 5종 서버 + 봇 2개씩, 한 판 전체 진행 (대기→카운트다운→경기→결과)
#            = portal   : 로비 포털 → 장애물 레이스 서버 → 결과 후 로비 복귀
#            = ws       : basic과 같지만 WebSocket 전송 (웹 브라우저 접속 경로)
#            = jitter   : WebSocket + 입력이 0~300ms씩 몰려 도착하는 프록시 → 보정(미끄러짐)이 적은지
#            = gateway  : 클라우드 게이트웨이(server/cloud/gateway.js)가 서버 6개 실행, 봇이 ws://게이트웨이/ 로 접속 → 포털 → 레이스 → 로비
#            = rooms    : 게이트웨이 방 코드 (방끼리 격리, 방 전용 미니게임 이동, 빈 서버 자동 종료)
#            = offline  : 서버 없이 로컬 규칙 실행 (오프라인/웹 연습): 포털 → 레이스 완주 → 로비 복귀
#
# 결과 판정은 tests/integration/check_results.js 가 수행한다 (Node.js 필요).
set -u
SCENARIO="${1:-basic}"
OUT="${2:-$(mktemp -d)}"
GODOT="${GODOT:?set GODOT to the Godot console executable}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${PORT:-17777}"
MOCK_PORT=19099
FB_CFG="--firebase-config=res://tests/integration/firebase_mock.cfg"
mkdir -p "$OUT"
rm -f "$OUT"/*.log
PIDS=()
MOCK_PID=""

# 새 스크립트 클래스가 추가돼도 실패하지 않도록 매번 임포트(클래스 캐시 갱신)
"$GODOT" --headless --path "$ROOT" --import > "$OUT/import.log" 2>&1

run_fg() { # 포그라운드 실행 (순서가 중요한 단계)
  local name="$1" q="$2"; shift 2
  "$GODOT" --headless --path "$ROOT" -- --quit-after="$q" "$@" > "$OUT/$name.log" 2>&1
}

run() { # name, quit_after, extra args...
  local name="$1" q="$2"; shift 2
  "$GODOT" --headless --path "$ROOT" -- --quit-after="$q" "$@" > "$OUT/$name.log" 2>&1 &
  PIDS+=($!)
}

start_mock() {
  node "$ROOT/tests/integration/mock_firebase.js" "$MOCK_PORT" demo-party test-api-key "$(cygpath -m "$OUT/test_service_account.json")" > "$OUT/mock_firebase.txt" 2>&1 &
  MOCK_PID=$!
  for _ in $(seq 1 50); do grep -q MOCK_FIREBASE_READY "$OUT/mock_firebase.txt" 2>/dev/null && return; sleep 0.1; done
  echo "mock firebase failed to start"; cat "$OUT/mock_firebase.txt"; exit 1
}

case "$SCENARIO" in
  basic)
    run server 17 --server --auth=dev --port="$PORT" --max-players=8 --report-at=11.5
    sleep 2
    run walker1 12 --connect=127.0.0.1:"$PORT" --nickname=Walker1 --bot=walker
    run walker2 12 --connect=127.0.0.1:"$PORT" --nickname=Walker2 --bot=walker
    sleep 1
    run cheat 11 --connect=127.0.0.1:"$PORT" --nickname=Cheater --bot=cheat
    run flood 11 --connect=127.0.0.1:"$PORT" --nickname=Flooder --bot=flood
    run badversion 6 --connect=127.0.0.1:"$PORT" --nickname=OldClient --bot=badversion
    run silent 10 --connect=127.0.0.1:"$PORT" --nickname=Silent --bot=silent
    ;;
  ws)
    WS="ws://127.0.0.1:$PORT"
    run server 17 --server --transport=ws --auth=dev --port="$PORT" --max-players=8 --report-at=11.5
    sleep 2
    run walker1 12 --connect="$WS" --nickname=Walker1 --bot=walker
    run walker2 12 --connect="$WS" --nickname=Walker2 --bot=walker
    sleep 1
    run cheat 11 --connect="$WS" --nickname=Cheater --bot=cheat
    run flood 11 --connect="$WS" --nickname=Flooder --bot=flood
    run badversion 6 --connect="$WS" --nickname=OldClient --bot=badversion
    run silent 10 --connect="$WS" --nickname=Silent --bot=silent
    ;;
  jitter)
    # 들쭉날쭉한 인터넷(입력이 0~300ms씩 몰려 도착)에서도 보정(미끄러짐)이 적어야 한다
    run server 22 --server --transport=ws --auth=dev --port="$PORT" --max-players=8 --report-at=17
    node "$ROOT/tests/integration/jitter_proxy.js" $((PORT + 1)) "$PORT" 300 > "$OUT/jitter.txt" 2>&1 &
    GW_PID=$!
    sleep 2
    run walker1 18 --connect="ws://127.0.0.1:$((PORT + 1))" --nickname=Walker1 --bot=walker
    run walker2 18 --connect="ws://127.0.0.1:$((PORT + 1))" --nickname=Walker2 --bot=walker
    ;;
  gateway)
    GW_PORT=18080
    PORT=$GW_PORT PORT_OFFSET=10000 GODOT_BIN="$GODOT" GAME_DIR="$ROOT" AUTH_MODE=dev \
      MINIGAME_ARGS="--min-players=1 --wait-sec=1 --countdown-sec=1 --round-sec=8 --results-sec=2" \
      node "$ROOT/server/cloud/gateway.js" > "$OUT/gateway.txt" 2>&1 &
    GW_PID=$!
    sleep 4
    run traveler 33 --connect="ws://127.0.0.1:$GW_PORT/" --nickname=Traveler --bot=objective --bot-portal=obstacle_race
    ;;
  rooms)
    # 방 코드: 같은 방끼리만 보이고, 방 전용 미니게임으로 이동했다가 같은 방 로비로 돌아옴. 빈 서버는 자동 종료
    GW_PORT=18081
    PORT=$GW_PORT PORT_BASE=27000 GODOT_BIN="$GODOT" GAME_DIR="$ROOT" AUTH_MODE=dev IDLE_SEC=4 \
      MINIGAME_ARGS="--min-players=1 --wait-sec=1 --countdown-sec=1 --round-sec=8 --results-sec=2" \
      node "$ROOT/server/cloud/gateway.js" > "$OUT/gateway.txt" 2>&1 &
    GW_PID=$!
    sleep 2
    GW="ws://127.0.0.1:$GW_PORT"
    run room_a1 16 --connect="$GW/r/ABCD" --nickname=RoomA1 --bot=walker
    run room_a2 16 --connect="$GW/r/abcd" --nickname=RoomA2 --bot=walker
    run room_b1 16 --connect="$GW/r/WXYZ" --nickname=RoomB1 --bot=walker
    run public1 16 --connect="$GW/" --nickname=Public1 --bot=walker
    run traveler 36 --connect="$GW/r/TRIP" --nickname=Traveler --bot=objective --bot-portal=obstacle_race
    run bad 6 --connect="$GW/r/x!" --nickname=BadCode --bot=walker
    run plaza2 36 --connect="$GW/p/2" --nickname=Plaza2 --bot=objective --bot-portal=obstacle_race
    run badplaza 6 --connect="$GW/p/99" --nickname=BadPlaza --bot=walker
    ;;
  capacity)
    run server 17 --server --auth=dev --port="$PORT" --max-players=8 --report-at=11.5
    sleep 2
    for i in 1 2 3 4 5 6 7 8 9; do
      run "walker$i" 12 --connect=127.0.0.1:"$PORT" --nickname="Bot$i" --bot=walker
      sleep 0.4
    done
    ;;
  auth)
    start_mock
    run server 16 --server --auth=firebase "$FB_CFG" --port="$PORT" --max-players=8 --report-at=10.5
    sleep 2
    run guest 11 "$FB_CFG" --login=anonymous --connect=127.0.0.1:"$PORT" --nickname=Guest --bot=walker
    run email1 11 "$FB_CFG" --login=email:kid@example.com:secret123 --connect=127.0.0.1:"$PORT" --nickname=Email1 --bot=walker
    run forged 8 "$FB_CFG" --login=anonymous --connect=127.0.0.1:"$PORT" --nickname=Forger --bot=forged
    run notoken 8 "$FB_CFG" --connect=127.0.0.1:"$PORT" --nickname=NoToken --bot=walker
    run badpw 8 "$FB_CFG" --login=email:x@example.com:123 --connect=127.0.0.1:"$PORT" --nickname=BadPw --bot=walker
    sleep 4
    run email2 7 "$FB_CFG" --login=email:kid@example.com:secret123 --connect=127.0.0.1:"$PORT" --nickname=Email2 --bot=walker
    ;;
  data)
    start_mock
    run server 26 --server --auth=firebase "$FB_CFG" --service-account="$(cygpath -m "$OUT/test_service_account.json")" --port="$PORT" --max-players=8 --report-at=11
    sleep 2
    run_fg datapre 20 "$FB_CFG" --data-flow-test=pre
    run_fg player 9 "$FB_CFG" --login=email:data@example.com:secret123 --connect=127.0.0.1:"$PORT" --nickname=WrongNick --bot=walker
    sleep 2
    run_fg datapost 20 "$FB_CFG" --data-flow-test=post
    ;;
  minigames)
    # 모드마다 서버 1개 + 목표 추적 봇 2개. 짧은 라운드로 대기→카운트다운→경기→결과까지 한 판 진행
    declare -A RSEC=([obstacle_race]=40 [survival]=25 [racing]=45 [coop]=30 [party]=20)
    declare -A MPORT=([obstacle_race]=17781 [survival]=17782 [racing]=17783 [coop]=17784 [party]=17785)
    for m in obstacle_race survival racing coop party; do
      r=${RSEC[$m]}; p=${MPORT[$m]}
      run "srv_$m" $((r + 14)) --server --auth=dev --mode=$m --port=$p --min-players=2 --wait-sec=1 --countdown-sec=1 --round-sec=$r --results-sec=3 --report-at=$((r + 9))
    done
    sleep 2
    for m in obstacle_race survival racing coop party; do
      r=${RSEC[$m]}; p=${MPORT[$m]}
      for b in 1 2; do
        run "bot_${m}_$b" $((r + 9)) --connect=127.0.0.1:$p --nickname="${m:0:5}Bot$b" --bot=objective
      done
    done
    ;;
  portal)
    run server 40 --server --auth=dev --mode=lobby --port="$PORT" --routes=obstacle_race=:17781 --report-at=34
    run srv_race 40 --server --auth=dev --mode=obstacle_race --port=17781 --lobby=:"$PORT" --min-players=1 --wait-sec=1 --countdown-sec=1 --round-sec=8 --results-sec=2 --report-at=34
    sleep 2
    run traveler 33 --connect=127.0.0.1:"$PORT" --nickname=Traveler --bot=objective --bot-portal=obstacle_race
    ;;
  offline)
    run offline_race 70 --offline=obstacle_race --bot=objective
    run offline_portal 25 --offline --bot=objective --bot-portal=obstacle_race
    ;;
  touch)
    run touch 30 --touch-test
    ;;
  authflow)
    start_mock
    run authflow 30 "$FB_CFG" --auth-flow-test --session-file=user://test_auth_session.cfg
    ;;
esac

wait "${PIDS[@]}"
[ -n "${GW_PID:-}" ] && kill "$GW_PID" 2>/dev/null && sleep 1
[ -n "$MOCK_PID" ] && curl -s "http://127.0.0.1:$MOCK_PORT/stats" > "$OUT/mock_stats.json" 2>/dev/null; [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null
echo "logs in $OUT"
node "$ROOT/tests/integration/check_results.js" "$SCENARIO" "$OUT"
