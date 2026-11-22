#!/usr/bin/env bash
# 전체 테스트 한 번에 실행. 사용법: GODOT=/path/to/godot_console tests/run_all.sh [log_dir]
# 단위 테스트 출력에 SCRIPT ERROR 가 하나라도 있으면 실패로 처리 (오류난 테스트 함수가 조용히 건너뛰어지는 것 방지).
set -u
GODOT="${GODOT:?set GODOT to the Godot console executable}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
FAILED=()

"$GODOT" --headless --path "$ROOT" --import > "$OUT/import.log" 2>&1
"$GODOT" --headless --path "$ROOT" -s res://tests/run_tests.gd > "$OUT/unit.log" 2>&1
UNIT=$(grep -E "^RESULT" "$OUT/unit.log")
ERRS=$(grep -c "SCRIPT ERROR" "$OUT/unit.log")
echo "unit: $UNIT  script_errors=$ERRS"
if ! echo "$UNIT" | grep -q "failed=0" || [ "$ERRS" != "0" ]; then FAILED+=(unit); grep -E "FAIL|SCRIPT ERROR" "$OUT/unit.log" | head -20; fi

for sc in basic capacity auth authflow data touch minigames portal; do
  RES=$(bash "$ROOT/tests/integration/net_test.sh" "$sc" "$OUT/$sc" 2>&1)
  LINE=$(echo "$RES" | grep NET_RESULT)
  echo "$LINE"
  if ! echo "$LINE" | grep -q "failed=0"; then FAILED+=("$sc"); echo "$RES" | grep FAIL; fi
done

if [ ${#FAILED[@]} -eq 0 ]; then echo "ALL_TESTS_PASSED (logs: $OUT)"; else echo "TESTS_FAILED: ${FAILED[*]} (logs: $OUT)"; exit 1; fi
