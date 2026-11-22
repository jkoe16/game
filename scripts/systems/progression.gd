class_name Progression
extends RefCounted
## 경험치 → 레벨 (서버가 xp를 누적하고, 레벨은 표시용으로 계산). 초반은 빨리, 뒤로 갈수록 천천히 오른다.
## Lv2=40xp, Lv3=160xp, Lv5=640xp, Lv10=3240xp — 한 판 평균 25~60xp 기준.

static func level_for_xp(xp: int) -> int:
	return 1 + int(floor(sqrt(maxf(xp, 0) / 40.0)))


static func xp_for_level(level: int) -> int:
	return 40 * (level - 1) * (level - 1)


## 현재 레벨 안에서의 진행률 0..1
static func progress(xp: int) -> float:
	var lv := level_for_xp(xp)
	var a := xp_for_level(lv)
	var b := xp_for_level(lv + 1)
	return clampf(float(xp - a) / float(b - a), 0.0, 1.0)
