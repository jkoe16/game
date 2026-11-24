extends Node
## 진입점. 실행 인자에 따라 전용 서버 / 클라이언트 / 메뉴로 분기한다.
##
## 사용자 인자는 "--" 뒤에 둔다. 예)
##   godot --headless -- --server --port=7777 --max-players=8
##   godot -- --connect=127.0.0.1:7777 --nickname=Tester
##   godot --headless -- --connect=127.0.0.1:7777 --bot=walker --quit-after=10
##   godot -- --offline
##   인증: --auth=firebase|dev (서버), --login=anonymous|email:<주소>:<비번> (테스트 봇 클라이언트)

var args := {}
var server: GameServer
var client: GameClient
var menu: MainMenu
var hud: Hud
var _local_server_pids: Array[int] = []


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	# 타이머는 분기(로그인 대기 등) 전에 등록해야 로그인 실패 시에도 테스트가 종료된다
	if args.has("screenshot"):
		# 시각 QA용: 지정 시간 후 화면을 PNG로 저장하고 종료.  --screenshot=경로.png [--shot-delay=초]
		get_tree().create_timer(float(args.get("shot-delay", 2.5))).timeout.connect(_save_screenshot)
	if args.has("report-at"):
		get_tree().create_timer(float(args["report-at"])).timeout.connect(_print_report)
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(_quit_with_report)

	if args.has("touch-test"):
		var touch_failures: int = await TouchTest.run(self)
		get_tree().quit(1 if touch_failures > 0 else 0)
		return
	if args.has("data-flow-test"):
		var data_failures: int = await DataFlowTest.run(str(args["data-flow-test"]), Auth, PlayerData)
		get_tree().quit(1 if data_failures > 0 else 0)
	elif args.has("auth-flow-test"):
		var failures: int = await AuthFlowTest.run(Auth)
		get_tree().quit(1 if failures > 0 else 0)
	elif args.has("server") or OS.has_feature("dedicated_server"):
		_start_server()
	elif args.has("connect"):
		if args.has("login") and not await _bot_login(str(args["login"])):
			print("CLIENT_RESULT " + JSON.stringify({"welcomed": false, "rejected": "login_failed"}))
			get_tree().quit(1)
			return
		var hp: Array = Net.parse_address(str(args["connect"]))
		_start_client(hp[0], hp[1], false)
	elif args.has("offline"):
		_start_client("", 0, true)
	else:
		_show_menu()


## 테스트 봇용 로그인. spec: "anonymous" | "email:<주소>:<비밀번호>" (없는 계정이면 가입)
func _bot_login(spec: String) -> bool:
	Auth.persist_session = false
	var r: Dictionary
	if spec == "anonymous":
		r = await Auth.sign_in_anonymous()
	elif spec.begins_with("email:"):
		var parts := spec.split(":", true, 2)
		r = await Auth.sign_in_email(parts[1], parts[2])
		if not r["ok"] and r["code"] in ["INVALID_LOGIN_CREDENTIALS", "EMAIL_NOT_FOUND"]:
			r = await Auth.sign_up_email(parts[1], parts[2])
	else:
		r = {"ok": false, "error": "unknown login spec", "code": "SPEC"}
	print("[MAIN] bot login (%s): %s" % [spec.get_slice(":", 0), "ok uid=" + Auth.uid if r["ok"] else r["code"]])
	return r["ok"]


static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _start_server() -> void:
	server = GameServer.new()
	server.name = "GameServer"
	var mode_id := str(args.get("mode", "lobby"))
	var info: Dictionary = ModeRegistry.MODES.get(mode_id, {})
	server.mode_id = mode_id
	server.port = int(args.get("port", info.get("port", NetConfig.DEFAULT_PORT)))
	server.max_players = clampi(int(args.get("max-players", info.get("max_players", NetConfig.DEFAULT_MAX_PLAYERS))), 1, 32)
	server.transport = "ws" if str(args.get("transport", "enet")) == "ws" else "enet"
	server.mode_cfg = _mode_cfg_from_args()
	var mode := str(args.get("auth", ""))
	if mode == "":
		mode = "firebase" if FirebaseConfig.load_default().is_server_ready() else "dev"
	server.auth_mode = mode
	server.service_account_path = ServiceAccountAuth.find_key_path(args)
	add_child(server)
	if not server.start():
		get_tree().quit(1)


func _start_client(host: String, port: int, offline: bool) -> void:
	client = GameClient.new()
	client.name = "GameClient"
	client.offline = offline
	if offline and typeof(args.get("offline")) == TYPE_STRING:
		client.offline_start_mode = str(args["offline"])
	client.address = host
	client.port = port
	client.nickname = str(args.get("nickname", "Player%d" % (randi() % 1000)))
	client.bot_mode = str(args.get("bot", ""))
	client.bot_portal = str(args.get("bot-portal", ""))
	client.force_touch = args.has("touch")
	if args.has("touch"):
		Input.emulate_touch_from_mouse = true
	client.platform = "mobile" if OS.has_feature("mobile") else "pc"
	client.appearance = Appearance.random_appearance() if args.has("random-look") or client.bot_mode != "" else client.appearance
	if menu:
		client.appearance = menu.get_appearance()
	add_child(client)
	if DisplayServer.get_name() != "headless":
		hud = Hud.new()
		hud.client = client
		add_child(hud)
		client.status_changed.connect(hud.set_status)
	client.session_ended.connect(_on_session_ended)
	client.start()


## Firebase가 설정되어 있으면: 자동 로그인 시도 → 실패 시 로그인 화면 → 메뉴
func _show_menu() -> void:
	if Auth.is_configured() and not Auth.is_signed_in():
		if not await Auth.restore_session():
			var login := LoginScreen.new()
			add_child(login)
			await login.finished
	if menu == null:
		_build_menu()
	menu.show()
	menu.refresh_account()
	if PlayerData.is_available():
		var r: Dictionary = await PlayerData.load_profile()
		if r["exists"]:
			menu.apply_profile(PlayerData.profile)
		elif not r["ok"]:
			push_warning("[MAIN] profile load failed: %s" % r["error"])
		await PlayerData.load_stats()
		menu.refresh_account()


## 게임 시작 전 닉네임·외형을 Firestore에 저장 (실패해도 게임은 진행, 서버는 hello 값을 사용)
func _save_profile_from_menu() -> void:
	if menu and PlayerData.is_available():
		var r: Dictionary = await PlayerData.save_profile(menu.get_nickname(), menu.get_appearance())
		if not r["ok"]:
			push_warning("[MAIN] profile save failed: %s" % r["error"])


func _build_menu() -> void:
	menu = MainMenu.new()
	add_child(menu)
	menu.logout_requested.connect(func() -> void:
		Auth.sign_out()
		PlayerData.clear()
		menu.hide()
		_show_menu())
	menu.link_requested.connect(func() -> void:
		var link := LoginScreen.new()
		link.mode = "link"
		add_child(link)
		await link.finished
		menu.refresh_account())
	menu.offline_requested.connect(func(nick: String) -> void:
		args["nickname"] = nick
		args["offline"] = true
		await _save_profile_from_menu()
		_close_menu()
		_start_client("", 0, true))
	menu.practice_requested.connect(func(nick: String, practice_mode: String) -> void:
		args["nickname"] = nick
		args["offline"] = practice_mode
		await _save_profile_from_menu()
		_close_menu()
		_start_client("", 0, true))
	menu.join_requested.connect(func(nick: String, addr: String) -> void:
		args["nickname"] = nick
		await _save_profile_from_menu()
		var hp: Array = Net.parse_address(addr)
		_close_menu()
		_start_client(hp[0], hp[1], false))
	menu.host_requested.connect(func(nick: String) -> void:
		args["nickname"] = nick
		await _save_profile_from_menu()
		_spawn_local_server()
		_close_menu()
		_start_client("127.0.0.1", NetConfig.DEFAULT_PORT, false))


func _close_menu() -> void:
	if menu:
		menu.hide()


## 개발 편의: 같은 PC에서 전용 서버를 "별도 프로세스"로 띄운다 (리슨 서버 아님).
func _spawn_local_server() -> void:
	var exe := OS.get_executable_path()
	var cmd: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
	cmd.append_array(["--", "--server"])
	for k in ["auth", "firebase-config"]:
		if args.has(k):
			cmd.append("--%s=%s" % [k, args[k]])
	# 로비 + 미니게임 5개 = 서버 프로세스 6개 (같은 PC 개발용. 운영은 매치메이커가 배치)
	for mode_id in ModeRegistry.MODES:
		var c := cmd.duplicate()
		c.append("--mode=" + mode_id)
		if mode_id == "lobby":
			c.append("--routes=auto")
		else:
			c.append("--lobby=:%d" % NetConfig.DEFAULT_PORT)
		_local_server_pids.append(OS.create_process(exe, c))
	print("[MAIN] spawned local servers: %s" % [_local_server_pids])


func _on_session_ended(reason: String) -> void:
	print("[MAIN] session ended: %s" % reason)
	if args.has("quit-after"):
		return  # 테스트 모드: 결과 보고 시점까지 대기
	if DisplayServer.get_name() == "headless":
		_quit_with_report()


func _save_screenshot() -> void:
	if client and client.local_player and args.has("emote"):
		client.request_emote(int(args["emote"]))
		await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(str(args["screenshot"]))
	print("[MAIN] screenshot saved: %s (%s)" % [args["screenshot"], error_string(err)])
	get_tree().quit()


func _print_report() -> void:
	if server:
		print("SERVER_RESULT " + JSON.stringify(server.report()))
	if client:
		print("CLIENT_RESULT " + JSON.stringify(client.report()))


func _quit_with_report() -> void:
	if not args.has("report-at"):
		_print_report()
	Net.stop()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		for pid in _local_server_pids:
			if pid > 0:
				OS.kill(pid)
		_local_server_pids.clear()


## 모드 설정 인자: --transport=enet|ws --routes=auto|gateway|mode=host:port,... --lobby=host:port --min-players= --wait-sec= --countdown-sec= --round-sec= --results-sec=
func _mode_cfg_from_args() -> Dictionary:
	var cfg := {}
	for k in ["min-players", "wait-sec", "countdown-sec", "round-sec", "results-sec", "lobby"]:
		if args.has(k):
			cfg[k.replace("-", "_").replace("players", "players")] = args[k]
	if cfg.has("min_players"):
		cfg["min_players"] = int(cfg["min_players"])
	var routes_arg := str(args.get("routes", ""))
	if routes_arg == "auto":
		cfg["routes"] = ModeRegistry.default_routes()
	elif routes_arg == "gateway":
		# 클라우드: 게이트웨이 한 주소 아래 경로로 구분 (wss://서버/obstacle_race). 클라이언트가 현재 주소 기준으로 경로만 바꿈
		var g := {}
		for id in ModeRegistry.MODES:
			if id != "lobby":
				g[id] = "/" + id
		cfg["routes"] = g
	elif routes_arg != "":
		var r := {}
		for pair in routes_arg.split(","):
			var kv := pair.split("=")
			if kv.size() == 2:
				r[kv[0]] = kv[1]
		cfg["routes"] = r
	return cfg
