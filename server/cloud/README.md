# 친구들과 온라인으로 플레이하기

플레이 방법은 두 가지예요.

| 방법 | 친구가 하는 일 | 필요한 것 |
|---|---|---|
| **A. 클라우드 서버** (추천) | 웹 링크를 열거나 PC 버전으로 접속 (휴대폰 브라우저도 됨) | Render 무료 계정 (카드 불필요) 또는 Fly.io (유료, 약 월 $2~6) |
| **B. 내 PC가 서버** | PC 버전 `3DPartyWorld.exe` 실행 → 내 IP 입력 | 같은 와이파이면 바로 / 인터넷이면 공유기 포트포워딩 |

---

## A. 클라우드 서버 (웹 + PC 모두 접속)

### 구조
```
 [웹 브라우저] ─┐                     ┌─ Godot 서버: 로비 (7777)
 [PC 버전]   ─┼─ wss://주소/경로 ─ [gateway.js] ─┼─ Godot 서버: 장애물 레이스 (7781) ... 미니게임 5개
 [휴대폰 웹]  ─┘    (한 포트, 8080)     └─ (죽으면 자동 재시작)
```
- `server/cloud/gateway.js`: 의존성 없는 Node.js 게이트웨이. 경로(`/`, `/obstacle_race` 등)를 보고 내부 Godot 서버로 연결을 넘긴다.
- Godot 서버는 `--transport=ws`(WebSocket)로 실행. 로비 포털 → 미니게임 이동은 `/obstacle_race` 같은 **경로**로 안내.
- `Dockerfile`: Godot 4.7.2 + 게이트웨이를 한 컨테이너로. 메모리 약 320MB 사용.
- 로그인: `config/firebase.cfg`가 있으므로 서버는 Firebase 토큰을 검증한다 (게스트 로그인도 가능).
  플레이 기록 저장까지 하려면 서비스 계정 키를 비밀로 넣고 `GOOGLE_APPLICATION_CREDENTIALS`로 경로를 지정 (선택).

### 1) Render에 무료로 올리기 (추천 · 카드 없이 웹에서만)
1. https://render.com → **Get Started** → **GitHub로 가입**
2. 대시보드 오른쪽 위 **New +** → **Blueprint**
3. 저장소 목록에서 `jkoe16/game` 선택 (안 보이면 "Configure account"로 GitHub 저장소 접근 허용)
4. `render.yaml`을 읽어 **3d-party-world** 서비스가 표시됨 → **Apply** (첫 빌드 5~10분)
5. 서비스 화면 위쪽의 주소 `https://3d-party-world-xxxx.onrender.com` → 게임 주소는 **`wss://3d-party-world-xxxx.onrender.com`**
6. 확인: 브라우저로 `https://...onrender.com/healthz` → `{"ok":true,...}`

무료 요금제 제약: 15분 동안 아무도 없으면 서버가 잠들고, 다음 접속 때 깨어나는 데 30초~1분 걸려요.
게임은 "서버를 깨우는 중이에요..."를 표시하며 약 90초까지 자동으로 다시 시도해요. CPU가 작아서 많은 인원(10명 이상)은 버벅일 수 있어요.

### 2) Fly.io에 올리기 (유료, 잠들지 않고 빠름)
**PowerShell 없이 (GitHub 웹에서)**: Fly.io 대시보드 → Tokens → 토큰 복사 → GitHub 저장소 Settings → Secrets and variables → Actions →
`FLY_API_TOKEN` 추가 → Actions 탭 → "온라인 서버 배포 (Fly.io)" → **Run workflow**

**PowerShell로**:
1. https://fly.io 가입 (카드 등록 필요. 아무도 없을 땐 서버가 꺼지고 접속하면 켜져서 요금이 적음)
2. flyctl 설치 (PowerShell):
   ```powershell
   iwr https://fly.io/install.ps1 -useb | iex
   ```
3. 프로젝트 폴더에서:
   ```bash
   fly auth login
   fly launch --no-deploy --copy-config      # 앱 이름을 물어보면 원하는 이름 입력 (예: my-party-world)
   fly deploy
   ```
4. 끝나면 주소가 나옵니다: `https://<앱이름>.fly.dev` → 게임에서 쓸 주소는 **`wss://<앱이름>.fly.dev`**
5. 확인: 브라우저로 `https://<앱이름>.fly.dev/healthz` 를 열면 `{"ok":true,...}`

### 3) 게임에 서버 주소 넣고 다시 배포
1. `config/online.cfg` 의 `server_url` 을 채우기:
   ```ini
   [online]
   server_url="wss://my-party-world.fly.dev"
   ```
2. 웹 다시 배포: `bash server/deployment/deploy_web.sh` → https://game-28f1b.web.app 메뉴에 **"친구들과 온라인 플레이"** 버튼이 생김
   - PowerShell 없이: GitHub → Actions → **"웹 배포 (Firebase + GitHub Pages)"** → Run workflow
     (Firebase까지 올리려면 `FIREBASE_SERVICE_ACCOUNT` 비밀값 필요. 방법은 `.github/workflows/deploy-web.yml` 맨 위 설명)
3. PC 버전 다시 빌드: `"$GODOT" --headless --path . --export-release "Windows" build/windows/3DPartyWorld.exe`

친구에게는 **https://game-28f1b.web.app 링크만** 보내면 돼요. 로그인(게스트 가능) → "친구들과 온라인 플레이" → 같은 광장에서 만남 → 포털에 올라서면 다 같이 미니게임으로 이동.

### 로컬에서 미리 해보기
```bash
docker build -t party-server .
docker run --rm -p 8080:8080 -e AUTH_MODE=dev party-server
"$GODOT" --path . -- --connect=ws://127.0.0.1:8080/ --nickname=나
```
또는 Docker 없이: `GODOT_BIN="$GODOT" GAME_DIR=. AUTH_MODE=dev node server/cloud/gateway.js`

---

## B. 내 PC가 서버 (PC 버전끼리)

1. 나: `3DPartyWorld.exe` 실행 → **"로컬 서버 열고 접속"** (로비 + 미니게임 서버 6개가 내 PC에서 실행됨)
2. 처음 실행 때 Windows 방화벽 창이 뜨면 **허용** (UDP 7777, 7781~7785)
3. 내 IP 확인: PowerShell에서 `ipconfig` → "IPv4 주소" (예: 192.168.0.5)
4. 친구: `3DPartyWorld.exe` 실행 → 서버 주소에 `192.168.0.5:7777` → **"서버 접속"**

- **같은 와이파이**: 위 순서 그대로 하면 됩니다.
- **다른 집(인터넷)**: 공유기 관리 페이지에서 **UDP 7777, 7781~7785** 를 내 PC로 포트포워딩하고,
  친구는 내 공인 IP(https://ifconfig.me 에서 확인)를 입력. 포트포워딩이 어렵다면 A(클라우드)를 쓰세요.
- 미니게임 이동 때 친구는 자동으로 "지금 접속한 서버 주소"의 다른 포트로 이동합니다.

친구에게 `3DPartyWorld.exe` 파일 하나만 보내면 돼요 (설치 필요 없음, 약 110MB).
Windows가 "PC 보호" 경고를 띄우면 "추가 정보 → 실행" (서명 인증서가 없는 개인 제작 게임이라 뜨는 경고).
