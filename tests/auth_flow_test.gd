class_name AuthFlowTest
extends RefCounted
## Auth autoload 전체 흐름 테스트 (목 Firebase 서버 대상).
## 실행: godot --headless --path . -- --firebase-config=res://tests/integration/firebase_mock.cfg --auth-flow-test --session-file=user://test_session.cfg

static var passed := 0
static var failed := 0


static func check(cond: bool, label: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  " + label)
	else:
		failed += 1
		print("  FAIL  " + label + ("  -- " + detail if detail != "" else ""))


static func run(auth: Node) -> int:
	var email := "flow%d@example.com" % (Time.get_ticks_usec() % 1000000)
	auth.sign_out()

	var r: Dictionary = await auth.sign_in_anonymous()
	check(r["ok"] and auth.is_anonymous() and auth.uid != "", "guest (anonymous) sign-in", str(r))
	var guest_uid: String = auth.uid

	r = await auth.link_email(email, "short")
	check(r["code"] == "WEAK_PASSWORD", "link rejects weak password", str(r))
	r = await auth.link_email(email, "secret123")
	check(r["ok"] and auth.uid == guest_uid and auth.provider == "password" and auth.email == email, "guest linked to email keeps same uid", str(r))

	var old_token: String = auth.id_token
	var ok: bool = await auth.refresh()
	check(ok and auth.id_token != "" and auth.uid == guest_uid, "refresh token → new ID token")

	auth.expires_at = 0  # 만료된 것처럼
	var tok: String = await auth.get_valid_id_token()
	check(tok != "" and auth.expires_at > int(Time.get_unix_time_from_system()), "expired ID token auto-refreshed")
	check(old_token != "", "had token before refresh")

	# 세션 저장 → 메모리 초기화 → 복원
	var saved_uid: String = auth.uid
	auth.uid = ""
	auth.id_token = ""
	auth.refresh_token = ""
	ok = await auth.restore_session()
	check(ok and auth.uid == saved_uid, "session restored from encrypted file")

	auth.sign_out()
	check(not auth.is_signed_in() and not FileAccess.file_exists(auth.SESSION_PATH if "SESSION_PATH" in auth else ""), "sign-out clears session")

	r = await auth.sign_in_email(email, "wrongpass")
	check(r["code"] == "INVALID_LOGIN_CREDENTIALS" and r["error"].contains("올바르지"), "wrong password → Korean error", str(r))
	r = await auth.sign_in_email(email, "secret123")
	check(r["ok"] and auth.uid == guest_uid, "email sign-in returns same account")
	r = await auth.sign_up_email(email, "secret123")
	check(r["code"] == "EMAIL_EXISTS", "duplicate sign-up rejected", str(r))
	r = await auth.send_password_reset(email)
	check(r["ok"], "password reset email requested", str(r))
	r = await auth.send_password_reset("nobody@example.com")
	check(not r["ok"], "reset for unknown email fails")

	auth.sign_out()
	r = await auth.sign_in_anonymous()
	var guest2: String = auth.uid
	r = await auth.sign_in_with_google_id_token("google-test-alice")
	check(r["ok"] and auth.provider == "google.com" and auth.uid == guest2 and auth.email == "alice@gmail.test", "Google sign-in links guest account", str(r))
	auth.sign_out()
	r = await auth.sign_in_with_google_id_token("google-test-alice")
	check(r["ok"] and auth.uid == guest2, "Google sign-in again → same account")
	r = await auth.sign_in_with_google_id_token("garbage")
	check(not r["ok"], "invalid Google credential rejected")

	var real_key: String = auth.config.api_key
	auth.config.api_key = "wrong-key"
	r = await auth.sign_in_anonymous()
	check(r["code"] == "API_KEY_INVALID", "wrong API key detected", str(r))
	auth.config.api_key = real_key

	auth.sign_out()
	print("AUTH_FLOW_RESULT passed=%d failed=%d" % [passed, failed])
	return failed
