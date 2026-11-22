-- 3D PARTY WORLD — PostgreSQL 스키마 v0.1 (설계안)
-- 상태: 작성 완료, **실제 PostgreSQL에서 아직 실행/검증하지 않음** (이 PC에 PostgreSQL 미설치)
-- 대상: PostgreSQL 15+
-- 원칙: 게임 서버·클라이언트는 DB에 직접 접속하지 않는다. 백엔드 API만 접근.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- 대소문자 무시 이메일

-- ---------------------------------------------------------------- 계정
CREATE TABLE accounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_type    TEXT NOT NULL CHECK (account_type IN ('guest', 'registered')),
    email           CITEXT UNIQUE,                       -- 게스트는 NULL
    password_hash   TEXT,                                -- Argon2id 인코딩 문자열 (평문 저장 금지)
    nickname        TEXT NOT NULL CHECK (char_length(nickname) BETWEEN 2 AND 16),
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    is_minor        BOOLEAN NOT NULL DEFAULT TRUE,       -- 확인 전까지 아동 보호 기본값
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at   TIMESTAMPTZ,
    CHECK (account_type = 'guest' OR (email IS NOT NULL AND password_hash IS NOT NULL))
);
CREATE INDEX accounts_nickname_idx ON accounts (nickname);

-- 리프레시 토큰 (원문 대신 SHA-256 해시만 저장, 회전 방식)
CREATE TABLE auth_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    refresh_token_hash  BYTEA NOT NULL UNIQUE,
    device_platform     TEXT NOT NULL CHECK (device_platform IN ('pc', 'android', 'ios')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ
);
CREATE INDEX auth_sessions_account_idx ON auth_sessions (account_id);

-- ---------------------------------------------------------------- 캐릭터 & 성장
CREATE TABLE characters (
    account_id      UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    appearance      JSONB NOT NULL DEFAULT '{"color":0,"hat":0}',   -- 서버가 보유 아이템과 대조 후 저장
    level           INT NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp              BIGINT NOT NULL DEFAULT 0 CHECK (xp >= 0),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 아이템 카탈로그 (외형 전용, 능력치 없음 = Pay-to-Win 불가)
CREATE TABLE items (
    id              TEXT PRIMARY KEY,                    -- 예: 'hat.crown'
    slot            TEXT NOT NULL CHECK (slot IN ('color', 'hat', 'outfit', 'accessory', 'emote', 'face')),
    rarity          TEXT NOT NULL DEFAULT 'common',
    price_coins     INT CHECK (price_coins IS NULL OR price_coins >= 0),   -- NULL = 판매 안 함(보상 전용)
    is_default      BOOLEAN NOT NULL DEFAULT FALSE,
    available_from  TIMESTAMPTZ,
    available_until TIMESTAMPTZ
);

CREATE TABLE inventory (
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    item_id         TEXT NOT NULL REFERENCES items(id),
    acquired_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    source          TEXT NOT NULL CHECK (source IN ('default', 'reward', 'purchase', 'event', 'admin')),
    PRIMARY KEY (account_id, item_id)
);

CREATE TABLE wallets (
    account_id      UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    coins           BIGINT NOT NULL DEFAULT 0 CHECK (coins >= 0)
);

-- 모든 재화 변동 기록 (감사·환불·부정 추적용, 삭제 금지)
CREATE TABLE wallet_ledger (
    id              BIGSERIAL PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts(id),
    delta           BIGINT NOT NULL,
    reason          TEXT NOT NULL,
    ref_id          TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX wallet_ledger_account_idx ON wallet_ledger (account_id, created_at);

-- ---------------------------------------------------------------- 친구 & 안전
CREATE TABLE friendships (
    requester_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    addressee_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    status          TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (requester_id, addressee_id),
    CHECK (requester_id <> addressee_id)
);
CREATE INDEX friendships_addressee_idx ON friendships (addressee_id);

CREATE TABLE blocks (
    blocker_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    blocked_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE reports (
    id              BIGSERIAL PRIMARY KEY,
    reporter_id     UUID NOT NULL REFERENCES accounts(id),
    target_id       UUID NOT NULL REFERENCES accounts(id),
    match_id        UUID,
    category        TEXT NOT NULL CHECK (category IN ('nickname', 'cheating', 'harassment', 'other')),
    detail          TEXT CHECK (char_length(detail) <= 500),
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'actioned', 'dismissed')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- 매치 기록
CREATE TABLE matches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mode_id         TEXT NOT NULL,
    map_id          TEXT NOT NULL,
    server_id       TEXT NOT NULL,                       -- 결과를 보고한 게임 서버 (서버 인증 키로 식별)
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ,
    status          TEXT NOT NULL CHECK (status IN ('running', 'finished', 'aborted'))
);

CREATE TABLE match_participants (
    match_id        UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    account_id      UUID NOT NULL REFERENCES accounts(id),
    platform        TEXT NOT NULL CHECK (platform IN ('pc', 'android', 'ios')),
    rank            INT,
    score           INT NOT NULL DEFAULT 0,
    xp_awarded      INT NOT NULL DEFAULT 0,
    left_early      BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (match_id, account_id)
);
CREATE INDEX match_participants_account_idx ON match_participants (account_id);

CREATE TABLE player_stats (
    account_id      UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    matches_played  INT NOT NULL DEFAULT 0,
    wins            INT NOT NULL DEFAULT 0,
    coop_clears     INT NOT NULL DEFAULT 0,
    play_seconds    BIGINT NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------- 미션 & 업적
CREATE TABLE mission_defs (
    id              TEXT PRIMARY KEY,
    period          TEXT NOT NULL CHECK (period IN ('daily', 'weekly', 'season', 'achievement')),
    goal_type       TEXT NOT NULL,                       -- 예: 'play_matches', 'coop_clear', 'emote_used'
    goal_value      INT NOT NULL CHECK (goal_value > 0),
    reward_xp       INT NOT NULL DEFAULT 0,
    reward_coins    INT NOT NULL DEFAULT 0,
    reward_item_id  TEXT REFERENCES items(id)
);

CREATE TABLE mission_progress (
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    mission_id      TEXT NOT NULL REFERENCES mission_defs(id),
    period_key      TEXT NOT NULL,                       -- 예: '2026-11-22', '2026-W47'
    progress        INT NOT NULL DEFAULT 0,
    claimed_at      TIMESTAMPTZ,
    PRIMARY KEY (account_id, mission_id, period_key)
);

-- ---------------------------------------------------------------- 운영
CREATE TABLE audit_log (
    id              BIGSERIAL PRIMARY KEY,
    actor           TEXT NOT NULL,                       -- 'system', 'admin:<id>', 'server:<id>'
    action          TEXT NOT NULL,
    target          TEXT,
    detail          JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
