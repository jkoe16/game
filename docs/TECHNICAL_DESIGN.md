# 기술 설계서

## 1. 기술 스택과 결정 이유
| 영역 | 선택 | 이유 |
|---|---|---|
| 엔진 | Godot 4.7.2 stable | 설치된 버전, 헤드리스 서버·모바일 내보내기 지원 |
| 언어 | GDScript (정적 타입 위주) | 서버/클라이언트 코드 공유, 빠른 반복 |
| 렌더러 | **Mobile** (+ OpenGL3 폴백) | PC·모바일 동일 화질 기준. Vulkan/D3D12/Metal 미지원 저사양 기기는 Compatibility로 자동 폴백 |
| 물리 | Jolt (프로젝트 기본값 유지) | 안정성/성능. 결정성 테스트 통과 |
| 네트워크 | ENetMultiplayerPeer + SceneMultiplayer RPC | 엔진 내장, UDP, 채널별 신뢰성 선택 |
| 백엔드 | Node.js (설치됨 v26) + PostgreSQL | Phase 7. **PostgreSQL은 이 PC에 미설치** → 설치 승인 필요 |

## 2. 실행 모드 (하나의 프로젝트, 인자로 분기)
`scripts/main/main.gd`가 `--` 뒤 사용자 인자를 해석:

| 모드 | 명령 |
|---|---|
| 전용 서버 | `godot --headless --path . -- --server [--port=7777] [--max-players=8] [--map=lobby_plaza]` |
| 클라이언트 | `godot --path . -- --connect=IP:PORT [--nickname=이름]` |
| 오프라인 연습 | `godot --path . -- --offline` |
| 메뉴 | 인자 없음 |
| 테스트 봇 | `--bot=walker|cheat|flood|badversion|silent --quit-after=초 [--report-at=초]` |
| 스크린샷 QA | `--screenshot=경로.png [--shot-delay=초] [--emote=0..3]` |

"로컬 서버 열고 접속" 메뉴도 **별도 프로세스**로 전용 서버를 띄운다 (리슨 서버 구조 없음).

## 3. 코드 구조 (실제)
```
scripts/
  main/main.gd                    진입점, 인자 분기, 테스트 리포트
  networking/
    net_config.gd                 네트워크 상수 (틱, 채널, 제한값)
    network_manager.gd            Autoload "Net": 모든 RPC 정의
    player_input.gd               입력 1틱 (양자화)
    input_codec.gd / snapshot_codec.gd   바이너리 직렬화 + 검증
  multiplayer/
    game_server.gd                방 1개 서버: 입장/검증/시뮬레이션/스냅샷
    game_client.gd                접속/월드 구성/스냅샷 적용
  player/
    player_body.gd                CharacterBody3D 이동 규칙 (서버·클라 공용)
    local_player_controller.gd    입력 수집, 예측, 보정
    remote_interpolator.gd        원격 플레이어 보간
    character_visual.gd           모델 + AnimationPlayer/AnimationTree
  camera/third_person_camera.gd   SpringArm3D 3인칭 카메라
  gameplay/
    game_map.gd                   맵 공통 기반 (스폰, kill height, 헤드리스 시 시각요소 생략)
    map_registry.gd               map_id → 씬
    maps/lobby_plaza.gd           로비 레이아웃
  systems/ appearance.gd, validation.gd
  ui/ main_menu.gd, hud.gd
shaders/toon.gdshader             공용 카툰 셰이더
scenes/ main/main.tscn, player/player.tscn, maps/lobby_plaza.tscn
tests/ run_tests.gd (단위/물리), integration/ (네트워크)
```

## 4. 이동 시스템
- `PlayerBody.simulate(input, delta)` 하나가 규칙의 전부 (가속/감속/공중제어/중력/코요테/점프/회전/계단).
- 서버와 클라이언트가 같은 함수·같은 양자화 입력을 쓰므로 결과가 동일 (결정성 테스트: 240틱 후 오차 < 1mm).
- 계단: `CharacterBody3D`에 없어서 직접 구현 (위→앞→아래 `test_move`, 바닥 위에서만, 0.35m 이하).
- 충돌 레이어: 1=world, 2=players. 현재 플레이어끼리는 충돌하지 않음 (예측 불일치 방지). 밀치기는 Phase 6에서 서버 판정 넉백 이벤트로 구현 예정.

## 5. 게임 모드 모듈 인터페이스 (Phase 6 설계)
```gdscript
class_name GameMode extends Node
# 서버에서만 규칙 실행. 클라이언트는 상태 표시만.
func get_mode_id() -> String
func get_map_id() -> String
func get_player_limits() -> Vector2i          # (최소, 최대)
func on_round_start(players: Array) -> void
func on_player_tick(player, delta) -> void      # 체크포인트, 탈락 판정 등
func on_player_left(peer_id) -> void
func is_round_over() -> bool
func compute_results() -> Array                # [{peer_id, rank, score, xp, rewards}]
func get_public_state() -> Dictionary          # 스냅샷에 실을 모드 상태 (타이머, 남은 인원 등)
```
새 모드 = `GameMode` 상속 스크립트 + 맵 씬 + `ModeRegistry` 등록. 서버 코어는 수정하지 않는다.

## 6. 렌더링/성능 계획 (Phase 8에서 실측으로 확정)
- 셰이더: 텍스처 없는 단색 툰 셰이더, 머티리얼 캐시 공유로 드로우콜 절감 (`GameMap.toon_material`).
- 헤드리스 서버는 메시/조명/환경을 생성하지 않음.
- 예정: GLB 에셋 LOD, 정적 지오메트리 MultiMesh/병합, 오클루전 컬링(Occluder3D), ETC2/ASTC 텍스처 압축(설정 완료), 그래픽 프리셋(낮음: 그림자 OFF·렌더 스케일 0.75).
- 현재 측정값: GTX 1650 / D3D12 / 1280×720 로비 60 FPS (vsync 상한). 모바일 실기기 측정 전.

## 7. 알려진 제약
- 캐릭터·맵은 프로토타입(프리미티브) 에셋. Blender 에셋 제작 필요.
- 한글은 OS 시스템 폰트 폴백으로 표시 중 → 출시 전 Noto Sans KR(OFL) 등 폰트 동봉 필요 (모바일 기기별 차이 방지).
- 오디오 미구현.
