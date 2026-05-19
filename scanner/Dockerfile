# PokeFolio scanner — DINOv2 + FAISS + FastAPI (CPU 추론)
# 베타 1단계 — CPU. 모델/FAISS index는 host volume read-only mount.

FROM python:3.11-slim
WORKDIR /app

# OS deps: opencv-headless / faiss-cpu / pillow 의존
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgomp1 libglib2.0-0 libsm6 libxext6 libxrender1 \
        ca-certificates curl tzdata \
    && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY scanner/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        -r /tmp/requirements.txt

# 코드만 복사 (model/db FAISS는 docker-compose volume mount).
# card_meta.json + card_db.faiss는 /app/scanner/db로 마운트됨.
COPY scanner/main.py /app/scanner/
COPY scanner/app /app/scanner/app

# non-root
# /app/scanner/data — main.py의 StaticFiles mount("/data") 필수 (없으면 FastAPI startup fail).
# /app/scanner/data/cards — admin 카드 이미지 업로드 시 저장처 (Phase 2에서 volume mount 권고).
RUN useradd -ms /bin/bash -u 1000 pokefolio \
    && mkdir -p /app/scanner/data/cards \
    && chown -R pokefolio:pokefolio /app
USER pokefolio

WORKDIR /app/scanner
EXPOSE 8082

ENV PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    KMP_DUPLICATE_LIB_OK=TRUE \
    OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl -fsS http://localhost:8082/health || exit 1

ENTRYPOINT ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8082"]
