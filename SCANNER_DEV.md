# 카드 스캐너 개발 문서

## 현재 상태 (2026-04-30)

ML Kit OCR 방식 → **Ollama Vision AI (llava)** 방식으로 전환 완료.
홀로그래픽·반사 카드, 소수문자 번호도 AI가 문맥 이해하여 인식.

---

## 아키텍처

```
iPhone (Flutter)
  │ takePicture() → JPEG
  ▼
Spring Boot /api/scanner/identify
  │ base64 인코딩 → Ollama API 호출
  ▼
Ollama (llava 모델, localhost:11434)
  │ "포켓몬 카드 수록번호를 읽어줘" → "227/264"
  ▼
Spring Boot → cards DB 조회 (collection_number + language='KO')
  │
  ▼
Flutter → 하단 모달 시트 (카드 이미지 + 자산 등록 버튼)
```

---

## 셋업 — 개발 환경 (Mac)

### 1. Ollama 설치

```bash
brew install ollama
```

설치 후 자동으로 백그라운드 실행됨 (port 11434).

### 2. llava 모델 다운로드 (한 번만)

```bash
ollama pull llava   # 약 4.5GB
```

### 3. 동작 확인

```bash
curl http://localhost:11434/api/tags   # llava 모델 목록 확인
```

### 4. Spring Boot 실행

```bash
cd back
./gradlew bootRun
```

`application.properties`에 이미 Ollama 설정 포함됨:
```properties
ollama.base-url=http://localhost:11434
ollama.model=llava
```

### 5. Flutter 실행

```bash
cd front
flutter run -d <device_id>
```

---

## 셋업 — 서버 배포 (Linux)

```bash
# Ollama 설치
curl -fsSL https://ollama.com/install.sh | sh

# llava 모델 다운로드
ollama pull llava

# 서비스 등록 (선택)
sudo systemctl enable ollama
sudo systemctl start ollama

# application.properties 수정 (서버라면 localhost 그대로 OK)
# ollama.base-url=http://localhost:11434
```

Spring Boot는 동일 서버에서 실행하므로 `localhost:11434` 그대로 사용.

---

## 구현된 파일

### 백엔드

| 파일 | 내용 |
|------|------|
| `back/src/.../scanner/ScannerController.java` | `/api/scanner/identify` 엔드포인트. 이미지 수신 → Ollama 호출 → DB 조회 |
| `back/src/.../card/CardController.java` | `GET /api/cards/number/{collectionNumber}` 수록번호 조회 추가 |
| `back/src/.../card/CardRepository.java` | `findByCollectionNumberAndLanguage()` 추가 |
| `back/src/main/resources/application.properties` | `ollama.base-url`, `ollama.model` 추가 |
| `back/build.gradle` | `springBoot { mainClass }` 명시 추가 (Spring Boot 4.x 호환) |

### 프론트엔드

| 파일 | 내용 |
|------|------|
| `front/lib/features/scanner/scanner_screen.dart` | ML Kit 제거. 1.5초 자동 촬영 → `/api/scanner/identify` 호출 |
| `front/lib/core/constants/api_constants.dart` | `scannerIdentify = '/api/scanner/identify'` 추가 |

---

## API

### `POST /api/scanner/identify`

```
Content-Type: multipart/form-data
image: <JPEG 파일>
```

**응답 (카드 인식 성공):**
```json
{
  "status": "success",
  "data": [
    {
      "cardId": "CRD_...",
      "name": "백마 버드렉스 VMAX",
      "rarityCode": "SSR",
      "jpScrydexRef": "s8b_ja-227",
      "enScrydexRef": "NO_EN"
    }
  ]
}
```

**응답 (인식 실패):**
```json
{ "status": "fail", "message": "카드 번호를 인식하지 못했습니다" }
```

---

## 스캐너 UX 흐름

1. 스캐너 화면 진입 → 후면 카메라 초기화 (veryHigh 해상도)
2. 1.5초마다 자동으로 `takePicture()` → `/api/scanner/identify` 호출
3. **인식 성공** → 하단 모달 시트 슬라이드 업:
   - 카드 이미지 + 이름 + 레어도
   - 수량 조절 (+ / -)
   - **자산 등록하기** 버튼 → `POST /api/assets`
   - **상세 보기** → 카드 상세 화면으로 이동
   - **계속 스캔** → 모달 닫고 재스캔
4. **인식 실패** → "인식하지 못했습니다" 메시지 후 자동 재시도

---

## Ollama 모델 선택 기준

| 모델 | 크기 | 속도 | 정확도 | 권장 |
|------|------|------|--------|------|
| `llava:7b` | 4.5GB | ★★★ | ★★★★ | **개발/서버** |
| `llava:13b` | 8.7GB | ★★ | ★★★★★ | 고사양 서버 |
| `moondream` | 1.6GB | ★★★★★ | ★★★ | 저사양 서버 |

`application.properties`의 `ollama.model` 값만 바꾸면 모델 전환 가능.

---

## 알려진 한계 / TODO

- [ ] Ollama 미실행 시 사용자 친화적 에러 메시지 (현재: "오류" 텍스트만)
- [ ] 카드가 DB에 없는 경우 (PR 카드, 해외판 등) 대응
- [ ] 응답 시간 최적화 — llava 첫 호출 시 모델 로딩으로 10~20초 소요
- [ ] 캐시 전략: 동일 카드 연속 스캔 시 API 재호출 방지

---

## 그레이딩 알고리즘 (참고)

→ `grading/GRADING_DEV.md` 참조 (v2.1 완료)
