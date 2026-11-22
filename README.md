# 3D PARTY WORLD

PC·모바일 크로스플레이 3D 온라인 파티 게임 (Godot 4.7, 전용 서버 방식).

## 빠른 시작
```bash
export GODOT="/c/Users/User/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --import          # 최초 1회
"$GODOT" --path .                              # 메뉴 → "연습 모드" 또는 "로컬 서버 열고 접속"
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
| 3 | PC·모바일 입력 (가상 조이스틱, 터치 카메라, 반응형 UI) | 🟡 PC 완료 / 모바일 ⬜ |
| 4 | 전용 서버 (접속·검증·서버 권한 이동·예측/보정·보간) | 🟡 핵심 완료 / 방 코드·매치메이킹·재접속 ⬜ |
| 5 | 3D 로비 (광장, 친구 초대, 방 시스템) | 🟡 그레이박스 광장 |
| 6 | 미니게임 5종 (첫 번째: 장애물 레이스) | ⬜ |
| 7 | 계정·성장 (Firebase Auth ✅ / Firestore 프로필·플레이 기록 ✅, 경험치·아이템 ⬜) | 🟡 |
| 8 | 최적화·QA | ⬜ |
| 9 | 출시 (배포·빌드·모니터링) | ⬜ |

## 테스트
```bash
"$GODOT" --headless --path . -s res://tests/run_tests.gd   # 86개 단위/물리/인증 테스트
bash tests/integration/net_test.sh basic                     # 보안/동기화 통합 테스트
bash tests/integration/net_test.sh capacity                  # 8인 정원 테스트
bash tests/integration/net_test.sh auth                      # Firebase 인증 서버 (목 Firebase)
bash tests/integration/net_test.sh authflow                  # 로그인 흐름 (목 Firebase)
bash tests/integration/net_test.sh data                      # Firestore 프로필·규칙·서버 기록 (목)
```
