# 데이터베이스 설계

> **2026-11-22 결정: 백엔드를 Firebase(Authentication + Firestore)로 변경.** 아래 0장이 현재 구조이며, 1장 이하의 PostgreSQL 설계(`server/database/schema.sql`)는 데이터 항목 참고용으로만 남겨 둔다.

## 0. Firestore 구조 (현재, 프로젝트 game-28f1b)
| 컬렉션/문서 | 내용 | 읽기 | 쓰기 |
|---|---|---|---|
| `profiles/{uid}` | `nickname`(2~16자 한글/영문/숫자/_), `appearance{color 0~7, hat 0~4}` | 로그인한 누구나 | 본인만, 규칙이 형식·범위·필드 목록 검증 |
| `stats/{uid}` | `sessions`, `playSeconds`, `lastSeen`(서버 시각) — 추후 xp/level/wins | 본인만 | **게임 서버만** (서비스 계정) |
| 그 외 전부 | matches, inventory, wallets 등 추가 예정 | 거부 | 거부 (서버 전용으로 추가) |

- 보안 규칙: `server/firebase/firestore.rules` (배포: `server/firebase` 에서 `npx firebase-tools deploy --only firestore:rules`)
- 클라이언트: Firestore REST + 플레이어 ID 토큰 (`scripts/data/player_data.gd`, autoload `PlayerData`)
- 게임 서버: 서비스 계정 JWT → OAuth 액세스 토큰 (`scripts/data/service_account_auth.gd`). 입장 시 프로필을 **서버가 직접 읽어** 닉네임·외형 결정(클라이언트 주장 무시), 퇴장 시 `stats` 원자적 증가.
- 서비스 계정 키는 서버 PC에만 (`--service-account=경로` 또는 `GOOGLE_APPLICATION_CREDENTIALS`). 저장소·클라이언트에 포함 금지 (`.gitignore` 등록).
- 키가 없으면 서버는 로그인 검증만 하고 Firestore 기능은 끈 채로 동작.

---

# (참고) PostgreSQL 설계 — 대체됨

> DDL: `server/database/schema.sql` · 미검증

## 1. 접근 원칙
- DB에 접속하는 것은 **백엔드 API 하나뿐**. 게임 서버는 백엔드의 내부 API(서버 인증 키)로 결과만 보고하고, 클라이언트는 공개 API만 사용.
- DB 비밀번호·JWT 서명 키는 서버 환경변수/시크릿 매니저에만 둔다. 저장소·클라이언트 빌드에 포함 금지.

## 2. ER 개요
```
accounts 1─1 characters        accounts 1─N auth_sessions
accounts 1─1 wallets 1─N wallet_ledger
accounts N─M items  (inventory)
accounts N─M accounts (friendships, blocks)
accounts 1─N reports (reporter / target)
matches 1─N match_participants N─1 accounts
accounts 1─1 player_stats
mission_defs 1─N mission_progress N─1 accounts
audit_log (독립)
```

## 3. 테이블 요약
| 테이블 | 용도 | 핵심 제약 |
|---|---|---|
| accounts | 게스트/회원 계정 | 회원은 email+password_hash 필수, 닉네임 2~16자, `is_minor` 기본 TRUE |
| auth_sessions | 리프레시 토큰 | 원문이 아닌 SHA-256 해시만 저장, 만료·폐기 시각 |
| characters | 외형(JSONB)·레벨·경험치 | xp ≥ 0 |
| items | 외형 아이템 카탈로그 | slot 제한, **능력치 컬럼 없음** (P2W 구조적 차단) |
| inventory | 보유 아이템 | 획득 경로(source) 기록 |
| wallets / wallet_ledger | 코인 잔액 / 모든 변동 기록 | 잔액 음수 불가, 원장은 추가만 |
| friendships / blocks | 친구 요청·수락 / 차단 | 자기 자신 불가 |
| reports | 신고 | 사유 카테고리, 처리 상태 |
| matches / match_participants | 경기·참가자 결과 | 보고한 게임 서버 ID 기록 |
| player_stats | 누적 통계 | |
| mission_defs / mission_progress | 일일·주간·시즌·업적 | 기간 키로 초기화 없이 관리 |
| audit_log | 운영 감사 기록 | |

## 4. 보안 결정
- **비밀번호**: Argon2id (메모리 64MB, 반복 3, 병렬 1 — 서버 사양 측정 후 조정). bcrypt보다 GPU 공격 저항성 우수.
- **토큰**: 액세스 토큰 15분(JWT, Ed25519 서명), 리프레시 토큰 30일·회전·해시 저장. 게임 서버는 공개키만 보유해 액세스 토큰을 검증.
- **게스트 → 회원 전환**: 같은 `accounts.id` 유지, `account_type`만 변경 (진행도 보존).
- **결과 신뢰**: 게임 결과는 클라이언트가 아니라 게임 서버가 서버 인증 키로 보고. 백엔드는 해당 서버가 그 매치를 배정받았는지 확인.
- **아동 보호**: `is_minor=TRUE`면 친구 요청·채팅 등 소통 기능을 보호자 설정 전까지 제한.

## 5. 백업·운영 (Phase 9)
- 일 1회 전체 백업 + WAL 아카이빙(시점 복구), 백업 복원 리허설 월 1회.
- 개인정보 최소 수집: 이메일·닉네임 외 수집하지 않음. 탈퇴 시 `status='deleted'` + 개인정보 즉시 비식별화, 원장·매치 기록은 익명 ID로 보존.
