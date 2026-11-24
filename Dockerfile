# 3D PARTY WORLD 온라인 서버 (게이트웨이 + Godot 전용 서버 6개)
# 빌드:  docker build -t party-server .
# 실행:  docker run -p 8080:8080 party-server      → ws://localhost:8080/
# 메모리 약 750MB 사용 → 클라우드 인스턴스는 1GB 이상 권장
FROM node:22-bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip \
 && apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /game
COPY . .
# 에셋 임포트 (클래스 캐시 생성). 실패해도 다음 단계에서 확인됨
RUN godot --headless --path . --import > /tmp/import.log 2>&1 || (tail -50 /tmp/import.log; exit 1)

ENV PORT=8080 GODOT_BIN=/usr/local/bin/godot GAME_DIR=/game
EXPOSE 8080
CMD ["node", "server/cloud/gateway.js"]
