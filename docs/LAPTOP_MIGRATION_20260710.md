# 노트북 마이그레이션 A~Z (2026-07-10)

> 이 맥 → **새 노트북 전체 이전**. git에 없는 **로컬 운영환경·데이터·시크릿** 전수 목록.
> 환경 설치(도구/DB복원 기본 절차)는 [`docs/SETUP.md`](SETUP.md). **이 문서는 그 위에 "이 맥에서만 돌던 로컬 운영상태"를 옮기는 체크리스트.**

## 0. 요약 — 새 노트북이 받아야 할 4덩어리
1. **git**: 전부 origin에 있음 → `git clone`. 브랜치 `main` / `feat/oripa-1.2.0`(오리파 구현) / `feat/oripa`(웹프로토) / `backup/laptop-migration-20260710`(밀기 전 untracked 343개) / `capture/prod-20260703`(서버트리).
2. **시크릿/설정 7종** (git 밖, 수동 복사) — §1
3. **로컬 운영 서비스**: 메타몽 KREAM 에이전트(launchd) + 로컬 postgres — §2, §3
4. **대용량 로컬 데이터**: scanner 47GB + pokefolio_backups 1GB — §4 (로컬 DB는 이전 불필요·재생성 §3)

---

## 1. 시크릿/설정 (git에 없음 → USB/암호화폴더로 수동 복사)
| 파일 | 용도 |
|---|---|
| `front/ios/Runner/GoogleService-Info.plist` | Firebase iOS (빌드 필수) |
| `front/android/app/google-services.json` | Firebase Android |
| `~/pem/pokefolio-upload.jks` | 안드로이드 서명 키스토어 |
| `~/pem/LightsailDefaultKey-ap-northeast-2.pem` | prod SSH 키 (서버 접속) |
| `~/.appstoreconnect/private_keys/AuthKey_HY8YGY46VK.p8` + `AuthKey_VL83MMC8WW.p8` | ASC API 키 (IPA 업로드) |
| `python/.env` (10줄) | KREAM 계정/토큰 등 수집 시크릿 |
| `admin/.env.production` (1줄) | 어드민 빌드 설정 |
| `~/Library/LaunchAgents/com.pokefolio.kream-agent.plist` | **KREAM_AGENT_TOKEN 내장** — §2 |

`~/.claude/projects/-Users-fury-pokemon-card-app/memory/` (Claude 기억 127개 .md)도 원하면 복사.

---

## 2. ★메타몽/KREAM 시세 수집 에이전트 (로컬 launchd — **밀면 수집 중단!**)
- **현재 라이브**: `com.pokefolio.kream-agent` (launchd, RunAtLoad+KeepAlive). `python/.venv_kream/bin/python python/kream_agent.py` 가 **curl_cffi로 KREAM 10초 폴링 → prod API(`POKEFOLIO_API`)로 POST**. Chrome 불필요. 로그 `/tmp/kream_agent.log`.
- **옮길 것**: plist(§1) + `python/kream_agent.py`(git 있음) + `python/.env`(§1) + `python/kream_state.json`(**증분 커서 — 안 옮기면 갭/중복**) + `.venv_kream`(재생성 가능).
- **새 노트북 재설정**:
  1. `python/.env`, `python/kream_state.json` 복사
  2. `.venv_kream` 재생성: `cd python && python3 -m venv .venv_kream && .venv_kream/bin/pip install curl_cffi requests`(+ kream_agent.py import 패키지)
  3. plist를 `~/Library/LaunchAgents/`에 복사 → `launchctl load ~/Library/LaunchAgents/com.pokefolio.kream-agent.plist`
  4. 검증: `tail -f /tmp/kream_agent.log` (폴링/POST 로그)
- ⚠️ **이 에이전트는 이 노트북에서만 돈다** → 밀고 새 세팅 완료 전까지 **메타몽 시세 수집 멈춤(갭 발생)**. 장기적으로 **prod/클라우드 이전 검토 권장**(노트북 의존 제거).
- (레거시) `kream_ditto.py` = Chrome 9222 CDP attach 방식([`docs/KREAM.md`](KREAM.md)) — 현재 agent로 대체됨. Chrome CDP는 이 방식에서만 필요.

---

## 3. 로컬 PostgreSQL (dev DB) — ★이전 불필요 (재생성)
- 로컬 `pokemon_card_db`(nightfury)는 **prod DB의 사본/시드일 뿐 진실원 아님.** 메타몽 수집은 prod API로 POST, 가격 배치도 prod cron → **로컬 DB에 고유 데이터 없음 → 덤프/이전 불필요.**
- 새 노트북에서 **로컬 백엔드 돌릴 때만** 필요 → 재생성:
  - (a) repo 시드: `db/schema.sql` + `db/seed_price_snapshots.sql.gz`(git에 있음) — SETUP.md §3
  - (b) 최신 전체 데이터 원하면 prod에서: `ssh <prod> "docker exec pokefolio-postgres pg_dump -U pokefolio pokemon_card_db" | gzip > fresh.sql.gz` → 로컬 restore
- ★**오리파(현재 작업)는 순수 Flutter mock → 로컬 DB 필요 없음.**

---

## 4. 대용량 로컬 데이터 (외장 드라이브/클라우드로)
| 데이터 | 크기 | 내용 / 이전 방법 |
|---|---|---|
| `scanner/data/cards` | 38GB | EN/JP/KO 카드 이미지(~15,962장). 외장 복사 권장(재다운로드+증분 인덱싱 가능하나 오래 걸림) |
| `scanner/db/card_db.faiss` | (scanner 47GB의 일부) | DINOv2 FAISS 인덱스. 외장 복사 or 재빌드 |
| `~/pokefolio_backups` | 1.0GB | ★`snkrdunk_catalog_20260620`(41,610 매핑 진실원) · DB/게시판 dump · SNK 분석 등. **꼭 복사** |

(로컬 dev DB는 재생성 대상 → §3, 이전 불필요)

---

## 5. 환경 설치 = [`docs/SETUP.md`](SETUP.md) (그대로 유효)
- Homebrew · Oracle JDK 20.0.2 · postgresql@14 · Flutter 3.41.4 · Xcode 16 · CocoaPods 1.16.2 · Miniconda(`scanner_v2` env)
- **추가 venv/conda**(SETUP.md 외): `python/.venv_kream`(§2) · `grading/venv`(FastAPI) · conda `scanner_v2`(scanner)

## 6. 로컬 서비스 실행 (참고 — CLAUDE.md 실행 명령어)
- `back` 8080 (Spring Boot) · `grading` 8081 (venv, uvicorn) · `scanner` 8082 (conda scanner_v2, DINOv2+FAISS)

---

## 7. 권장 순서
1. 새 맥 도구 설치 (SETUP.md §1~6)
2. `git clone` + `git worktree add ../pokemon-card-app-oripa feat/oripa-1.2.0`
3. 시크릿 7종(§1) 제자리 복사
4. 대용량 데이터(§4) 외장→새 맥 복사
5. (로컬 백엔드 돌릴 때만) postgres 생성 + DB 재생성(§3, repo 시드/prod). 오리파엔 불필요
6. venv/conda 재생성 (§5)
7. kream-agent plist load(§2) + 로그 확인
8. back/grading/scanner 기동 + `flutter run` 검증
