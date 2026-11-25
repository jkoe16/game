# server/

| 폴더 | 내용 | 상태 |
|---|---|---|
| `game_server/` | 게임 서버는 **이 Godot 프로젝트 자체**를 `--headless -- --server`로 실행한다. 서버 코드는 `scripts/multiplayer/game_server.gd`. | ✅ 동작 |
| `cloud/` | 게이트웨이 `gateway.js`: 방 코드·빠른 매칭(공개 광장 분산)·방별 서버 프로세스 켜고 끄기 | ✅ 동작 (별도 매치메이커 서비스 대신 여기서 처리) |
| `backend/` | 계정·인증·친구·결과 저장 API (Node.js 예정) | ⬜ Phase 7 |
| `database/` | PostgreSQL 스키마 `schema.sql` | 📝 설계 완료, 미검증 |
| `deployment/` | 서버 실행 스크립트 | ✅ 로컬 실행용 |

이 폴더에는 `.gdignore`가 있어 Godot 임포트 대상에서 제외된다.
