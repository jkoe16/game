class_name MapRegistry
extends RefCounted
## 맵 ID → 씬 경로. 서버가 맵 ID를 보내고 클라이언트가 같은 씬을 로드한다.
## 새 맵은 여기에 등록만 하면 된다.

const MAPS := {
	"lobby_plaza": "res://scenes/maps/lobby_plaza.tscn",
	"race_course": "res://scenes/maps/race_course.tscn",
	"survival_arena": "res://scenes/maps/survival_arena.tscn",
	"race_track": "res://scenes/maps/race_track.tscn",
	"coop_rooms": "res://scenes/maps/coop_rooms.tscn",
	"coin_arena": "res://scenes/maps/coin_arena.tscn",
}


static func has_map(map_id: String) -> bool:
	return MAPS.has(map_id)


static func instantiate(map_id: String) -> GameMap:
	if not MAPS.has(map_id):
		return null
	var scene: PackedScene = load(MAPS[map_id])
	return scene.instantiate() as GameMap
