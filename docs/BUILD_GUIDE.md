# 빌드 · 실행 가이드

## 새 컴퓨터에서 시작하기
```powershell
git clone https://github.com/jkoe16/game.git
cd game
powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1    # Godot 4.7.2 + 웹 템플릿 설치, 에셋 임포트
```
- 웹 빌드를 안 할 거면 `-SkipTemplates` (1.2GB 다운로드 생략)
- 스크립트가 마지막에 출력하는 `export GODOT=...` 를 Git Bash에서 실행한 뒤 테스트·배포
- 직접 해야 하는 것: `gh auth login` (push용), `npx firebase-tools login` (웹 배포용). 로그인 정보는 비밀이라 git에 없음

## 준비물
- Godot **4.7.2 stable** (이 PC: `C:\Users\User\Desktop\Godot_v4.7.2-stable_win64.exe\`)
  - 자동화/서버에는 `Godot_v4.7.2-stable_win64_console.exe` 사용 (콘솔 출력이 보임)
- Node.js 18+ (통합 테스트 판정 스크립트용, 이 PC: v26)
- Git Bash (통합 테스트 셸 스크립트)

아래 예시는 Git Bash 기준이며 `GODOT` 변수를 먼저 지정합니다.
```bash
export GODOT="/c/Users/User/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
cd /c/Users/User/Documents/gloveer
```

## 1. 최초 1회: 에셋 임포트
```bash
"$GODOT" --headless --path . --import
```

## 2. 실행
| 목적 | 명령 |
|---|---|
| 에디터 열기 | `"$GODOT" --path . -e` |
| 메뉴로 시작 | `"$GODOT" --path .` |
| 혼자 연습 (광장부터) | `"$GODOT" --path . -- --offline` |
| 미니게임 바로 연습 | `"$GODOT" --path . -- --offline=obstacle_race` (survival / racing / coop / party) |
| 전용 서버 | `"$GODOT" --headless --path . -- --server --port=7777 --max-players=8` |
| 서버에 접속 | `"$GODOT" --path . -- --connect=127.0.0.1:7777 --nickname=나` |

**같은 PC에서 멀티플레이 확인**: 전용 서버를 띄운 뒤 클라이언트 창을 2개 이상 실행. 또는 메뉴의 "로컬 서버 열고 접속" (서버를 별도 프로세스로 자동 실행).

**다른 PC/폰에서 접속**: 서버 PC의 방화벽에서 UDP 7777 인바운드 허용 → 클라이언트에서 `--connect=서버PC의IP:7777`. (방화벽 변경은 사용자가 직접 승인/설정)

## 3. 테스트
```bash
# 단위·물리 테스트 (약 10초)
"$GODOT" --headless --path . -s res://tests/run_tests.gd

# 네트워크 통합 테스트 (각 약 20초, 실제 서버/클라이언트 프로세스 사용)
bash tests/integration/net_test.sh basic
bash tests/integration/net_test.sh capacity
```
`tests/integration/net_test.sh [scenario] [로그폴더]` — 로그 폴더를 생략하면 임시 폴더 사용.

## 4. 내보내기
### 웹 (Firebase Hosting) — 구성 완료
- 프리셋: `export_presets.cfg` → "Web" (스레드 끔 = GitHub Pages처럼 COOP/COEP 헤더 없는 호스팅에서 동작)
- 내보내기 템플릿 4.7.2 필요: `%APPDATA%\Godot\export_templates\4.7.2.stable\web_*.zip`
- 빌드: `"$GODOT" --headless --path . --export-release "Web" build/web/index.html`
- 배포 (빌드까지 한 번에): `bash server/deployment/deploy_web.sh` (보안 규칙도: `--rules`) → https://game-28f1b.web.app
  - 최초 1회 `npx firebase-tools login` 필요. `server/firebase/public`은 배포용 복사본 (git 제외)
  - 예전 주소 https://jkoe16.github.io/game/ (`gh-pages` 브랜치)는 수동 갱신, 현재 갱신 안 함
- 웹 제약
  - 렌더러는 Compatibility(WebGL2) 고정. 이 렌더러에서는 그림자 켠 방향광이 과노출되어 **해 그림자를 끔** (`GameMap.setup_environment`)
  - 브라우저는 ENet(UDP) 불가 → 메뉴에 온라인 버튼 숨김, 오프라인 연습만. 온라인 웹 지원은 WebSocket/WebRTC 서버 필요 (미구현)
  - 브라우저는 OS 폰트 폴백이 없음 → 한글 폰트 `assets/ui/fonts/NanumGothic-Regular.ttf` (OFL) 를 프로젝트 기본 폰트로 지정
  - 로그인: 내보내기 때 `config/firebase.cfg`를 포함 (include_filter, git에도 포함됨)
  - 웹 Google 로그인: Firebase JS SDK 팝업 (`html/head_include`의 `window.pwGoogleSignIn`) → 배포 도메인이 Firebase 승인 도메인에 있어야 함 (`game-28f1b.web.app`은 기본 포함, `jkoe16.github.io` 추가 완료)

### 그 밖의 플랫폼 (Phase 9에서 구성 예정)- Windows/Linux 전용 서버: 내보내기 프리셋 "Dedicated Server" (리소스 → 서버용 비시각 리소스 제거) — 미구성
- Windows/macOS 클라이언트, Android(APK/AAB), iOS(Xcode 프로젝트) — 미구성
- Android 키스토어, iOS 서명 인증서, 스토어 계정은 **사용자 승인/소유 필요**하므로 임의로 만들지 않음.

## 5. 폴더 안내
- `server/` 와 `docs/` 에는 `.gdignore`가 있어 Godot가 임포트하지 않음.
- `server/database/schema.sql` — PostgreSQL 스키마 (미검증)
- `server/deployment/` — 서버 실행 스크립트

## 6. Firebase (프로젝트 game-28f1b)
- 클라이언트 설정: `config/firebase.cfg` (웹 API 키·프로젝트 ID). 공개 식별자라 git에 포함. 다른 프로젝트용 예시: `config/firebase.example.cfg`
- **내보내기 시 주의**: `.cfg`는 리소스가 아니므로 내보내기 프리셋 → 리소스 → "리소스 외 파일 포함 필터"에 `config/firebase.cfg` 추가 필요 (Web 프리셋은 설정 완료).
- 전용 서버 (로그인 검증 + Firestore):
  ```bash
  "$GODOT" --headless --path . -- --server --auth=firebase --service-account="C:/secrets/game-28f1b-server.json"
  ```
  `--auth` 생략 시 `config/firebase.cfg`가 있으면 firebase, 없으면 dev(검증 없음, 로컬 전용).
- 보안 규칙 배포 (최초 1회 `npx firebase-tools login` 필요):
  ```bash
  cd server/firebase && npx firebase-tools deploy --only firestore:rules --project game-28f1b
  ```
- 테스트(인터넷·실계정 불필요, 목 Firebase 사용): `net_test.sh auth | authflow | data`
