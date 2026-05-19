# PokeFolio grading — FastAPI (그레이딩 알고리즘)
# 베타 1단계 minimal.

FROM python:3.11-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgomp1 libglib2.0-0 libsm6 libxext6 libxrender1 \
        ca-certificates curl tzdata \
    && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

COPY grading/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY grading/ /app/

RUN useradd -ms /bin/bash -u 1000 pokefolio \
    && chown -R pokefolio:pokefolio /app
USER pokefolio

EXPOSE 8081
ENV PYTHONUNBUFFERED=1

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://localhost:8081/health || exit 1

ENTRYPOINT ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081"]
