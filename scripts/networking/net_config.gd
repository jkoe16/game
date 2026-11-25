class_name NetConfig
extends RefCounted
## 네트워크 공용 상수. 서버와 클라이언트가 반드시 같은 값을 사용해야 한다.

const PROTOCOL_VERSION := 3  # 2: 스냅샷에 아이템(점프 강화·보호막) 시간 추가 / 3: 재접속(세션 토큰, c_leave)
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
## 웹(WebSocket=TCP)은 입력이 사라지지 않는 대신 0.1~0.3초씩 몰려 도착한다.
## 이때 입력을 버리거나 멋대로 외삽하면 클라이언트 예측과 어긋나 캐릭터가 미끄러지듯 보정된다 → 넉넉하게.
const MAX_INPUT_QUEUE := 30            # 서버 입력 대기열 상한 (0.5초분, 그 이상만 버림)
const INPUT_CREDIT_MAX := 20.0         # 입력 시간 예산 상한 (틱). 약 0.33초 입력이 없을 때만 외삽 시작
## 입력이 끊긴 플레이어를 직전 이동으로 외삽하는 최대 틱 수 (0.5초). 끊긴 캐릭터가 계속 걸어가 떨어지지 않게
const MAX_EXTRAPOLATE_TICKS := 30
const MAX_INPUTS_PER_TICK := 4         # 한 틱에 따라잡기로 처리할 수 있는 최대 입력 수
const MAX_SEQ_JUMP := 600              # 이보다 큰 seq 점프는 위조로 간주
const MAX_INPUT_PACKETS_PER_SEC := 90  # 정상: 60/s
const FLOOD_KICK_PACKETS_PER_SEC := 240
const MAX_VIOLATIONS := 30
const HELLO_TIMEOUT_MS := 5000
const EMOTE_COOLDOWN_MS := 1200
const INTERP_DELAY_TICKS := 6          # 원격 플레이어 보간 지연 100ms

## 재접속: 연결이 갑자기 끊긴 플레이어의 자리(캐릭터·점수·진행도)를 이 시간 동안 남겨 둔다.
## 그 안에 같은 세션 토큰(또는 같은 Firebase 계정)으로 다시 들어오면 이어서 플레이한다.
const RECONNECT_GRACE_MS := 30000
## 서버: 접속 중인 플레이어에게서 이 시간 동안 아무 입력도 오지 않으면 끊긴 것으로 보고 연결을 닫는다
## (WebSocket은 회선이 조용히 끊기면 한참 뒤에야 감지되기 때문). 닫힌 뒤에는 위 유예 시간 동안 자리 유지.
const INPUT_SILENCE_MS := 10000
## 클라이언트: 스냅샷(초당 30개)이 이 시간 동안 하나도 오지 않으면 끊긴 것으로 보고 재접속을 시작
const SNAPSHOT_SILENCE_MS := 4000
## 클라이언트 재접속 시도 간격 / 최대 횟수 (유예 시간 안에서 시도)
const RECONNECT_RETRY_SEC := 1.0
const RECONNECT_MAX_ATTEMPTS := 25
