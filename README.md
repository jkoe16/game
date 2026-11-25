# 3D PARTY WORLD

PC·모바일 크로스플레이 3D 온라인 파티 게임 (Godot 4.7, 전용 서버 방식).

**웹에서 바로 해보기 (혼자 연습 · 게스트/이메일/Google 로그인): https://game-28f1b.web.app**
— 온라인 서버를 올리면 웹·PC·휴대폰 브라우저가 같은 광장에서 함께 플레이 (WebSocket). 서버가 없으면 혼자 연습만.

**친구들과 플레이하기: [server/cloud/README.md](server/cloud/README.md)** (클라우드 서버 또는 내 PC가 서버)

## 새 컴퓨터에서 시작
```powershell
git clone https://github.com/jkoe16/game.git; cd game
powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1   # Godot·웹 템플릿 자동 설치
```

## 빠른 시작
```bash
export GODOT="/c/Users/User/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --import          # 최초 1회
"$GODOT" --path .                              # 메뉴 → "연습 모드" / "장애물 레이스 바로 연습" / "로컬 서버 열고 접속"
```
자세한 내용: [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md)

## 문서
| 문서 | 내용 |
|---|---|
| [GDD](docs/GDD.md) | 게임 디자인 |
| [TECHNICAL_DESIGN](docs/TECHNICAL_DESIGN.md) | 기술 구조, 코드 맵, 게임 모드 인터페이스 |
| [NETWORK_ARCHITECTURE](docs/NETWORK_ARCHITECTURE.md) | 전용 서버, 예측/보정, 보안 |
| [DATABASE_SCHEMA](docs/DATABASE_SCHEMA.md) | PostgreSQL 설계 |
| [BUILD_GUIDE](docs/BUILD_GUIDE.md) | 실행·테스트·빌드 |
| [TEST_PLAN](docs/TEST_PLAN.md) | 테스트 결과와 체크리스트 |

## 개발 로드맵 & 현재 상태
| Phase | 내용 | 상태 |
|---|---|---|
| 1 | 기획·설계 (GDD, 기술/네트워크/DB 설계, 폴더 구조) | ✅ 완료 |
| 2 | 캐릭터·이동·점프·계단·애니메이션·3인칭 카메라 | 🟡 프로토타입 완료 (Blender 모델 교체 필요) |
| 3 | PC·모바일 입력 (가상 조이스틱, 터치 카메라, 반응형 UI) | 🟡 PC 완료 / 터치 조작 구현·테스트 ✅ / 모바일 빌드·실기기 ⬜ |
| 4 | 전용 서버 (접속·검증·서버 권한 이동·예측/보정·보간) | 🟡 핵심 완료 / 방 코드 ✅ · 빠른 매칭(공개 광장 자동 분산) ✅ / 끊긴 플레이어 재접속(30초 자리 유지) ✅ |
| 5 | 3D 로비 (광장, 친구 초대, 방 시스템) | 🟡 그레이박스 광장 |
| 6 | 미니게임 5종 (장애물 레이스·생존·레이싱·협동·파티 코인) | 🟡 5종 규칙·맵·한 판 흐름(대기→카운트다운→경기→결과→로비) 구현, 오프라인 혼자 연습 ✅ / 아트·밸런스 ⬜ |
| 7 | 계정·성장 (Firebase Auth ✅ / Firestore 프로필·플레이 기록 ✅, 경험치·아이템 ⬜) | 🟡 |
| 8 | 최적화·QA | ⬜ |
| 9 | 출시 (배포·빌드·모니터링) | 🟡 웹(오프라인 연습 + 로그인) Firebase Hosting 배포 ✅ / 전용 서버·모바일 ⬜ |

## 테스트
```bash
"$GODOT" --headless --path . -s res://tests/run_tests.gd   # 169개 단위/물리/인증/미니게임 테스트
bash tests/integration/net_test.sh basic                     # 보안/동기화 통합 테스트
bash tests/integration/net_test.sh capacity                  # 8인 정원 테스트
bash tests/integration/net_test.sh ws                        # WebSocket(웹 접속 경로) 보안/동기화
bash tests/integration/net_test.sh gateway                   # 클라우드 게이트웨이 → 포털 → 미니게임 → 로비
bash tests/integration/net_test.sh rooms                     # 방 코드 격리 · 방 전용 미니게임 · 공개 광장 2번
node tests/integration/gateway_api_test.js                   # 방 조회 · 빠른 매칭 API (Godot 불필요)
bash tests/integration/net_test.sh auth                      # Firebase 인증 서버 (목 Firebase)
bash tests/integration/net_test.sh authflow                  # 로그인 흐름 (목 Firebase)
bash tests/integration/net_test.sh data                      # Firestore 프로필·규칙·서버 기록 (목)
bash tests/integration/net_test.sh minigames                 # 미니게임 5종 한 판씩 (서버 + 봇)
bash tests/integration/net_test.sh portal                    # 로비 포털 → 레이스 서버 → 로비 복귀
bash tests/integration/net_test.sh offline                   # 서버 없이 혼자 연습 (웹과 같은 경로)
bash tests/integration/net_test.sh touch                     # 모바일 터치 조작
bash tests/integration/net_test.sh reconnect                 # 끊긴 플레이어 재접속 (끊김·조용한 끊김·만료·나가기·경기 도중)
```
