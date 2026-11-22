class_name NetConfig
extends RefCounted
## 네트워크 공용 상수. 서버와 클라이언트가 반드시 같은 값을 사용해야 한다.

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 8
## 정원 초과 접속자에게 "room_full" 거절 메시지를 보내기 위한 여유 슬롯
const EXTRA_CONNECTION_SLOTS := 4
const ENET_CHANNELS := 3

## RPC 전송 채널 (network_manager.gd의 @rpc 어노테이션 값과 일치해야 함)
const CH_RELIABLE := 0   # 입장/퇴장/감정표현 등 신뢰성 필요 이벤트
const CH_INPUT := 1      # 클라이언트 입력 (unreliable + 미확인 입력 중복 전송, 순서는 seq로 서버가 정렬)
const CH_SNAPSHOT := 2   # 서버 상태 스냅샷 (unreliable_ordered)

const TICK_RATE := 60
const SNAPSHOT_EVERY_N_TICKS := 2      # 30 Hz
const INPUT_REDUNDANCY := 16           # 패킷마다 서버가 아직 확인(ack)하지 않은 입력을 최대 16개까지 함께 보냄 (손실 버스트 복구)
const MAX_INPUT_QUEUE := 8             # 서버 입력 대기열 상한 (지연 누적 방지)
const INPUT_CREDIT_MAX := 8.0          # 입력 시간 예산 상한 (틱). 이만큼 입력이 없으면 외삽 시작
const MAX_INPUTS_PER_TICK := 3         # 한 틱에 따라잡기로 처리할 수 있는 최대 입력 수
const MAX_SEQ_JUMP := 600              # 이보다 큰 seq 점프는 위조로 간주
const MAX_INPUT_PACKETS_PER_SEC := 90  # 정상: 60/s
const FLOOD_KICK_PACKETS_PER_SEC := 240
const MAX_VIOLATIONS := 30
const HELLO_TIMEOUT_MS := 5000
const EMOTE_COOLDOWN_MS := 1200
const INTERP_DELAY_TICKS := 6          # 원격 플레이어 보간 지연 100ms
