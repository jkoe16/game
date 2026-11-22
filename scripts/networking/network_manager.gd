extends Node
## Autoload "Net" — 모든 RPC의 단일 진입점.
## RPC는 양쪽에서 같은 노드 경로(/root/Net)에 있어야 하므로 여기에 모은다.
## 수신한 RPC는 실제 처리기(GameServer / GameClient)로 전달만 하고, 검증은 처리기에서 한다.
##
## 채널 번호는 NetConfig.CH_* 와 일치: 0=신뢰성, 1=입력, 2=스냅샷

var server_handler: Node = null
var client_handler: Node = null


func start_server(port: int, max_clients: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients, NetConfig.ENET_CHANNELS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# 클라이언트가 서버를 경유해 다른 클라이언트에게 RPC를 보내는 기능 차단
	(multiplayer as SceneMultiplayer).server_relay = false
	return OK


func start_client(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, NetConfig.ENET_CHANNELS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func stop() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func kick(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.disconnect_peer(peer_id)


## ENet의 기본 패킷 스로틀은 RTT 변동을 감지하면 unreliable 패킷을 확률적으로 버린다.
## 통합 테스트에서 입력이 수백 개씩 유실되는 원인으로 확인됨 → 스로틀을 최대값으로 고정해 비활성화.
## (전송량은 게임 측에서 60Hz 입력 / 30Hz 스냅샷으로 이미 제한하고 있음)
func disable_throttle(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var p: ENetPacketPeer = peer.get_peer(peer_id)
		if p:
			p.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


## 서버 전용: 해당 피어가 아직 연결 상태인지 (연결 종료 중인 피어에 전송하면 ENet 오류 발생)
func is_peer_active(peer_id: int) -> bool:
	var peer := multiplayer.multiplayer_peer
	if not (peer is ENetMultiplayerPeer):
		return false
	var p: ENetPacketPeer = peer.get_peer(peer_id)
	return p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED


## 서버까지의 왕복 지연(ms). 클라이언트 전용.
func get_rtt_ms() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and not multiplayer.is_server():
		var server_peer: ENetPacketPeer = peer.get_peer(1)
		if server_peer:
			return int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return -1


# ---------------------------------------------------------------- client → server

@rpc("any_peer", "call_remote", "reliable", 0)
func c_hello(data) -> void:
	if multiplayer.is_server() and server_handler:
		server_handler.on_hello(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "call_remote", "unreliable", 1)
func c_input(packet) -> void:
	if multiplayer.is_server() and server_handler:
		server_handler.on_input(multiplayer.get_remote_sender_id(), packet)


@rpc("any_peer", "call_remote", "reliable", 0)
func c_emote(emote_id) -> void:
	if multiplayer.is_server() and server_handler:
		server_handler.on_emote(multiplayer.get_remote_sender_id(), emote_id)


# ---------------------------------------------------------------- server → client
# "authority" 모드: 서버(peer 1)만 호출 가능. 클라이언트가 보낸 호출은 엔진이 거부한다.

@rpc("authority", "call_remote", "reliable", 0)
func s_welcome(data) -> void:
	if client_handler:
		client_handler.on_welcome(data)


@rpc("authority", "call_remote", "reliable", 0)
func s_reject(reason) -> void:
	if client_handler:
		client_handler.on_reject(reason)


@rpc("authority", "call_remote", "reliable", 0)
func s_player_joined(info) -> void:
	if client_handler:
		client_handler.on_player_joined(info)


@rpc("authority", "call_remote", "reliable", 0)
func s_player_left(peer_id) -> void:
	if client_handler:
		client_handler.on_player_left(peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func s_emote(peer_id, emote_id) -> void:
	if client_handler:
		client_handler.on_emote(peer_id, emote_id)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func s_snapshot(packet) -> void:
	if client_handler:
		client_handler.on_snapshot(packet)


## 게임 모드 상태 (단계, 남은 시간, 점수판, 문/코인 등) — 변경 시 + 0.5초마다
@rpc("authority", "call_remote", "reliable", 0)
func s_mode_state(state) -> void:
	if client_handler:
		client_handler.on_mode_state(state)


## 다른 서버로 이동 (로비 ↔ 미니게임). route = "host:port"
@rpc("authority", "call_remote", "reliable", 0)
func s_transfer(route, target) -> void:
	if client_handler:
		client_handler.on_transfer(route, target)


@rpc("authority", "call_remote", "reliable", 0)
func s_notice(text) -> void:
	if client_handler:
		client_handler.on_notice(text)
