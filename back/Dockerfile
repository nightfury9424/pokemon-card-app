# PokeFolio back — Phase 1-8: Spring Boot 4.0.4 (Java 20) + Python 3 (스크래퍼 cron 호출용)
# Multi-stage build:
#   1. build  - gradle bootJar
#   2. runtime - java 20 jre + python3 + deps + jar + scripts

# ───────────── Stage 1: build ─────────────
FROM eclipse-temurin:20-jdk-jammy AS build
WORKDIR /workspace

# gradle wrapper + deps (캐시 활용)
COPY back/gradle gradle
COPY back/gradlew back/settings.gradle back/build.gradle ./
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies > /dev/null 2>&1 || true

# source + build
COPY back/src src
RUN ./gradlew --no-daemon bootJar -x test

# ───────────── Stage 2: runtime ─────────────
FROM eclipse-temurin:20-jre-jammy
WORKDIR /app

# Python3 + pip — PriceSyncScheduler가 호출하는 시세 스크립트 실행용
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv ca-certificates curl tzdata \
    && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Python deps (시세 스크래퍼).
# jammy(22.04)는 PEP 668 미적용 + pip 22.0.2라 --break-system-packages 옵션 자체가 없음 (pip 23.0+).
# noble(24.04)로 base 올리면 옵션 추가 또는 venv 분리 필요 (출시 후 개선 — Codex Medium).
COPY python/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Spring boot jar
COPY --from=build /workspace/build/libs/*.jar /app/app.jar

# Python scripts (PYTHON_SCRIPTS_DIR=/app/python)
COPY python/ /app/python/

# non-root user + data dirs
RUN useradd -ms /bin/bash -u 1000 pokefolio \
    && mkdir -p /opt/pokefolio/data/uploads /opt/pokefolio/data/images /app/logs \
    && chown -R pokefolio:pokefolio /opt/pokefolio /app

USER pokefolio
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://localhost:8080/api/health || exit 1

ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=70", \
    "-Dfile.encoding=UTF-8", \
    "-Duser.timezone=Asia/Seoul", \
    "-jar", "/app/app.jar"]
