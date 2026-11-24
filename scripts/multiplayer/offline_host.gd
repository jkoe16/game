class_name OfflineHost
extends Node
## 오프라인(서버 없음) 연습 모드에서 GameMode 규칙을 로컬로 실행한다.
## GameMode가 서버에 요구하는 API(get_player_pos, teleport_player, transfer_*, notify_player)를
## 로컬 플레이어 1명(peer_id 1)에 대해 흉내 낸다. 웹 빌드(ENet 불가)의 혼자 하기 모드에도 쓰인다.
##
## 틱 기준 = 로컬 컨트롤러의 seq (오프라인에서 장애물 시뮬레이션 틱과 같음).

signal transfer_requested(mode_id: String)

const PEER_ID := 1
## 오프라인 연습용 짧은 대기 (혼자니까 바로 시작)
const OFFLINE_CFG := {"min_players": 1, "wait_sec": 1.0, "countdown_sec": 3.0, "results_sec": 6.0, "lobby": "lobby"}

var client: GameClient
var mode: GameMode
var mode_id := ""
var tick := 0


func setup(p_client: GameClient, p_mode_id: String) -> void:
	client = p_client
	mode_id = p_mode_id
	mode = ModeRegistry.create(mode_id)
	var cfg := {} if mode_id == "lobby" else OFFLINE_CFG.duplicate()
	mode.setup(self, client.map, cfg)
	if mode is LobbyMode:
		var routes := {}
		for id in ModeRegistry.MODES:
			if id != "lobby":
				routes[id] = "offline:" + id
		(mode as LobbyMode).routes = routes
	add_child(mode)
	var pos := mode.on_player_joined(PEER_ID, client.nickname)
	if client.local_player:
		client.local_player.teleport(pos)
	_push_state()


func _physics_process(_delta: float) -> void:
	if mode == null or client.controller == null or client.local_player == null:
		return
	tick = client.controller.seq
	client.map.round_start_tick = mode.round_start_tick
	client.server_tick_est = tick
	mode.server_tick(tick)
	client.local_player.frozen = mode.is_frozen(PEER_ID)
	if mode.dirty or tick % 30 == 0:
		_push_state()


func _push_state() -> void:
	mode.dirty = false
	client.on_mode_state(mode.public_state())


## 낙하 처리 (컨트롤러가 호출). 서버의 _simulate_one과 같은 규칙.
func on_fell() -> Vector3:
	var p := mode.on_fell(PEER_ID)
	return mode.spectator_point() if p == Vector3.INF else p


# ------------------------------------------------------------------ GameMode가 쓰는 "서버" API

func get_player_pos(peer_id: int) -> Vector3:
	if peer_id == PEER_ID and client.local_player:
		return client.local_player.global_position
	return Vector3.ZERO


func teleport_player(peer_id: int, pos: Vector3) -> void:
	if peer_id == PEER_ID and client.local_player:
		client.local_player.teleport(pos)


func transfer_player(peer_id: int, route: String, _target: String) -> void:
	if peer_id != PEER_ID:
		return
	var target_mode := route.trim_prefix("offline:")
	if ModeRegistry.has_mode(target_mode):
		transfer_requested.emit.call_deferred(target_mode)


func transfer_all(route: String, target: String) -> void:
	transfer_player(PEER_ID, route, target)


func give_item(peer_id: int, kind: String, secs: float) -> void:
	if peer_id == PEER_ID and client.local_player:
		GameServer._apply_item(client.local_player, kind, secs)


func notify_player(_peer_id: int, text: String) -> void:
	client.status_changed.emit(text)
