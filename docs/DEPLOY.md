# 포켓폴리오 배포 가이드

## 서버 스펙 결정

| 단계 | 사용자 | 구성 | 월 비용 |
|------|--------|------|---------|
| 초기~500명 | ~500 | AWS Lightsail 16GB | ~12만원 |
| 1,000명 | ~1,000 | Lightsail 16GB + S3 분리 | ~13~18만원 |
| 5,000명 | ~5,000 | API/DB/Scanner 서버 분리 | ~30~80만원 |
| 스캔 폭증 | 5,000+ | Scanner GPU 서버 분리 | +25~70만원 |

### 왜 16GB인가
Spring Boot + FastAPI Scanner(DINOv2+FAISS) + FastAPI Grading + PostgreSQL 동시 운영 시 메모리 분배:

```
Spring Boot        ~800MB
FastAPI Scanner    ~2.5GB  (DINOv2 모델 상시 로딩)
FastAPI Grading    ~500MB
PostgreSQL         ~300MB
OS + Docker + Nginx ~500MB
──────────────────────────
합계               ~4.6GB  (피크 시 6GB+)
```

8GB는 `/identify` 동시 요청 2~3개만 몰려도 OOM 위험. **16GB가 안전한 운영 최소 스펙.**

---

## 운영 서버에 올릴 것 / 제외할 것

### 올릴 것
```
scanner/
├── main.py, app/           # FastAPI 코드
├── model/dinov2_finetuned/ # ~330MB
├── db/faiss_index          # ~수십MB
├── db/card_ids.json
└── data/cards/             # ref 이미지 ~9.4GB
```

### 제외할 것 (`.dockerignore`에 추가)
```
data/crawl_raw/
data/realshots/
training_data.json
crawl_results*.json
label.html
finetune.py
*.ipynb
__pycache__/
*.pyc
.git/
.DS_Store
```

> **핵심 원칙**: 운영 서버는 완성된 모델과 FAISS 인덱스를 서빙하는 곳. 학습/크롤 원본은 로컬에서만 관리.

---

## ML 파이프라인 → 배포 흐름

```
1. 파인튜닝 완료        (로컬)
   python finetune.py --data data/crawl_raw/training_data.json --epochs 10

2. FAISS 재빌드         (로컬)
   python build_db.py

3. 스캔 검증            (로컬)
   - /identify 테스트 (같은 카드 5장 이상)
   - faiss_index ↔ card_ids 매칭 확인
   - 오인식 여부 확인

4. 운영 산출물 정리     (로컬)
   release/scanner/
   ├── model/dinov2_finetuned/
   ├── db/faiss_index
   ├── db/card_ids.json
   └── data/cards/

5. DB 스키마 덤프       (로컬)
6. 환경변수 정리
7. Docker Compose 준비
8. Lightsail 16GB 배포
```

---

## 환경변수 설정

### `application-prod.properties`
```properties
spring.datasource.url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto=validate

google.client-id=${GOOGLE_CLIENT_ID}
jwt.secret=${JWT_SECRET}

card.image.dir=/app/data/cards
trade.image.dir=/app/trade_images

scanner.base-url=http://scanner:8082
grading.service.url=http://grading:8081
```

### `.env` (Git에 절대 올리지 말 것)
```env
DB_HOST=postgres
DB_PORT=5432
DB_NAME=pokemon_card_db
DB_USER=nightfury
DB_PASSWORD=강한비밀번호_여기에

GOOGLE_CLIENT_ID=389670144815-8m1et1a1mc8q1hg32dmub2g1jgud7gtn.apps.googleusercontent.com
JWT_SECRET=최소32자이상_랜덤문자열_여기에

PTCG_API_KEY=399acbbdae2b6773750166fc7e2da323cebc6e991b9b896e45e5458c3b08d63b
```

### `.env.example` (Git에 올릴 것)
```env
DB_HOST=postgres
DB_PORT=5432
DB_NAME=pokemon_card_db
DB_USER=
DB_PASSWORD=

GOOGLE_CLIENT_ID=
JWT_SECRET=

PTCG_API_KEY=
```

---

## Docker Compose

```yaml
services:
  nginx:
    image: nginx:stable
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - back
      - scanner
      - grading
    restart: unless-stopped

  back:
    build: ./back
    environment:
      SPRING_PROFILES_ACTIVE: prod
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      JWT_SECRET: ${JWT_SECRET}
      PTCG_API_KEY: ${PTCG_API_KEY}
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  scanner:
    build: ./scanner
    volumes:
      - /opt/pokemon-app/scanner/model:/app/model:ro
      - /opt/pokemon-app/scanner/db:/app/db:ro
      - /opt/pokemon-app/scanner/data/cards:/app/data/cards:ro
    environment:
      MAX_CONCURRENT_IDENTIFY: 1
    restart: unless-stopped

  grading:
    build: ./grading
    restart: unless-stopped

  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  postgres_data:
```

> **주의**: 8080/8081/8082/5432 포트는 외부 직접 오픈 금지. Nginx만 80/443 공개.

---

## 첫 배포 순서

### 1. DB 스키마/데이터 덤프 (로컬)
```bash
# 전체 덤프 (스키마 + 데이터, 권장)
pg_dump -h localhost -U nightfury -d pokemon_card_db -Fc > pokemon_card_db.dump

# 스키마만 필요한 경우
pg_dump -h localhost -U nightfury -d pokemon_card_db --schema-only > schema.sql
```

### 2. 서버에 파일 업로드
```bash
# 운영 산출물 (model/db/images)
rsync -avz --partial --info=progress2 \
  scanner/model/ ubuntu@SERVER_IP:/opt/pokemon-app/scanner/model/

rsync -avz --partial --info=progress2 \
  scanner/db/ ubuntu@SERVER_IP:/opt/pokemon-app/scanner/db/

rsync -avz --partial --info=progress2 \
  scanner/data/cards/ ubuntu@SERVER_IP:/opt/pokemon-app/scanner/data/cards/
# data/cards는 9.4GB라 시간 걸림

# DB 덤프
scp pokemon_card_db.dump ubuntu@SERVER_IP:~/
```

### 3. 서버에서 DB 먼저 기동
```bash
# postgres만 먼저 실행
docker compose up -d postgres

# DB 복원
docker exec -i $(docker compose ps -q postgres) \
  pg_restore -U nightfury -d pokemon_card_db < ~/pokemon_card_db.dump
```

### 4. 전체 서비스 기동
```bash
docker compose up -d
docker compose logs -f
```

### 5. SSL 설정
```bash
# Let's Encrypt (무료)
certbot --nginx -d yourdomain.com
```

---

## Scanner workers 주의

```bash
# workers=1 고정 (DINOv2 모델이 worker마다 따로 로딩됨)
uvicorn main:app --host 0.0.0.0 --port 8082 --workers 1
```

workers 늘리면 메모리 배수로 증가. 500명 기준은 workers=1 + 동시 요청 제한으로 운영.

---

## 이미지 업데이트 배포 (이후)

```bash
# 로컬에서 재학습 후
python finetune.py && python build_db.py

# 산출물만 동기화
rsync -avz --delete --partial --info=progress2 \
  scanner/model/ ubuntu@SERVER_IP:/opt/pokemon-app/scanner/model/
rsync -avz --delete --partial --info=progress2 \
  scanner/db/ ubuntu@SERVER_IP:/opt/pokemon-app/scanner/db/

# 서버에서 scanner만 재시작
docker compose restart scanner
```

---

## 5,000명 이후 분리 구조

```
로드밸런서 / Nginx
├── API 서버 (Spring Boot)
├── DB 서버 (PostgreSQL / RDS)
├── Scanner 서버 (FastAPI + DINOv2 + FAISS)
├── Grading 서버 (FastAPI)
└── Object Storage (카드 이미지 / 유저 업로드)
```

DB보다 **Scanner가 먼저 병목**. 5,000명부터는 Scanner 서버 분리 필수.
