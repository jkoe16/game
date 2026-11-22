class_name Appearance
extends RefCounted
## 캐릭터 외형 카탈로그와 검증. 외형은 인덱스로만 주고받고, 서버가 범위를 검증한다.
## (Phase 7에서 계정 보유 아이템과 대조하도록 확장)

const BODY_COLORS: Array[Color] = [
	Color(1.00, 0.66, 0.74),  # 딸기우유
	Color(0.55, 0.80, 1.00),  # 하늘
	Color(1.00, 0.85, 0.40),  # 바나나
	Color(0.60, 0.90, 0.60),  # 민트
	Color(0.78, 0.65, 1.00),  # 라벤더
	Color(1.00, 0.62, 0.40),  # 귤
	Color(0.95, 0.95, 0.95),  # 구름
	Color(0.45, 0.45, 0.55),  # 먹구름
]
const HATS: Array[String] = ["sprout", "none", "cap", "crown", "bow"]
const EMOTES: Array[String] = ["wave", "dance", "victory", "defeat"]


static func default_appearance() -> Dictionary:
	return {"color": 0, "hat": 0}


static func random_appearance() -> Dictionary:
	return {"color": randi() % BODY_COLORS.size(), "hat": randi() % HATS.size()}


static func sanitize(v: Variant) -> Dictionary:
	var out := default_appearance()
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = v
	var c: Variant = d.get("color", 0)
	if typeof(c) == TYPE_INT and c >= 0 and c < BODY_COLORS.size():
		out["color"] = c
	var h: Variant = d.get("hat", 0)
	if typeof(h) == TYPE_INT and h >= 0 and h < HATS.size():
		out["hat"] = h
	return out
