class_name DataFlowTest
extends RefCounted
## Firestore 데이터 흐름 테스트 (목 Firebase 대상).
##  pre  : 로그인 → 프로필 저장/읽기 → 보안 규칙 위반 시도가 거부되는지
##  post : 게임 서버가 기록한 stats/{uid} 를 본인이 읽을 수 있는지
## 실행: godot --headless --path . -- --firebase-config=... --data-flow-test=pre|post

const EMAIL := "data@example.com"
const PASSWORD := "secret123"

static var passed := 0
static var failed := 0


static func check(cond: bool, label: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  " + label)
	else:
		failed += 1
		print("  FAIL  " + label + ("  -- " + detail if detail != "" else ""))


static func run(phase: String, auth: Node, data: Node) -> int:
	auth.persist_session = false
	var r: Dictionary = await auth.sign_in_email(EMAIL, PASSWORD)
	if not r["ok"]:
		r = await auth.sign_up_email(EMAIL, PASSWORD)
	check(r["ok"], "[%s] signed in as %s" % [phase, EMAIL], str(r))
	var uid: String = auth.uid
	var fs: FirestoreClient = data.fs

	if phase == "pre":
		r = await data.load_profile()
		check(r["ok"] and not r["exists"], "new account has no profile yet", str(r))
		r = await data.save_profile("데이터봇", {"color": 3, "hat": 2})
		check(r["ok"], "save own profile (Korean nickname)", str(r))
		data.profile = {}
		r = await data.load_profile()
		check(r["exists"] and data.profile.get("nickname") == "데이터봇" and data.profile.get("appearance") == {"color": 3, "hat": 2}, "profile read back with correct types", str(data.profile))

		r = await fs.set_fields("profiles/" + uid, {"nickname": "<script>", "appearance": {"color": 0, "hat": 0}})
		check(r["status"] == 403, "rules: invalid nickname rejected", str(r["status"]))
		r = await fs.set_fields("profiles/" + uid, {"nickname": "Okay", "appearance": {"color": 99, "hat": 0}})
		check(r["status"] == 403, "rules: out-of-range appearance rejected", str(r["status"]))
		r = await fs.set_fields("profiles/" + uid, {"nickname": "Okay", "appearance": {"color": 1, "hat": 0}, "level": 99})
		check(r["status"] == 403, "rules: extra field (level) rejected", str(r["status"]))
		r = await fs.set_fields("profiles/someone-else", {"nickname": "Hacker", "appearance": {"color": 1, "hat": 0}})
		check(r["status"] == 403, "rules: writing another player's profile rejected", str(r["status"]))
		r = await fs.increment("stats/" + uid, {"sessions": 1000})
		check(r["status"] == 403, "rules: client cannot write own stats", str(r["status"]))
		r = await fs.get_doc("stats/someone-else")
		check(r["status"] == 403, "rules: cannot read another player's stats", str(r["status"]))

	elif phase == "post":
		r = await data.load_stats()
		var s: Dictionary = data.stats
		check(r["ok"] and int(s.get("sessions", 0)) >= 1, "server recorded a session in stats/{uid}", str(s))
		check(int(s.get("playSeconds", 0)) >= 3, "play time recorded", str(s.get("playSeconds")))
		check(typeof(s.get("lastSeen")) == TYPE_STRING and str(s.get("lastSeen")) != "", "lastSeen server timestamp recorded")
		r = await data.load_profile()
		check(data.profile.get("nickname") == "데이터봇", "profile unchanged by server", str(data.profile))

	print("DATA_FLOW_RESULT phase=%s passed=%d failed=%d" % [phase, passed, failed])
	return failed
