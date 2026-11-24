class_name OnlineConfig
extends RefCounted
## 공개 온라인 서버 주소 로더.  res://config/online.cfg
##   [online]
##   server_url="wss://my-game-server.fly.dev"
## 비어 있으면 메뉴에 "친구들과 온라인 플레이" 버튼이 나오지 않는다.
## 실행 인자 --server-url=<주소> 로 덮어쓸 수 있다.

const PATH := "res://config/online.cfg"


static func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			return a.substr("--server-url=".length()).strip_edges()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return ""
	return str(cf.get_value("online", "server_url", "")).strip_edges()
