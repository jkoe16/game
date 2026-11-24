class_name BuildInfo
extends RefCounted
## 빌드 버전 (git 커밋 앞 7자리). 업데이트가 실제로 반영됐는지 화면에서 확인하는 용도.
## 웹/PC: 배포 워크플로가 config/build.cfg 를 만든다. 서버: Render가 RENDER_GIT_COMMIT 환경 변수를 준다.

const PATH := "res://config/build.cfg"


static func client_version() -> String:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return "dev"
	return str(cf.get_value("build", "commit", "dev"))


static func server_version() -> String:
	var v := OS.get_environment("RENDER_GIT_COMMIT")
	if v == "":
		v = OS.get_environment("GIT_COMMIT")
	return v.substr(0, 7) if v != "" else client_version()
