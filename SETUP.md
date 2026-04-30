# 새 맥 세팅 가이드 — 처음부터 끝까지

## 1. 기본 도구 설치

### Homebrew (패키지 매니저)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
설치 후 터미널 재시작.

### Git
```bash
brew install git
git config --global user.name "fury"
git config --global user.email "redblue1201@naver.com"
```

---

## 2. 백엔드 — Java 17 + Gradle

```bash
brew install openjdk@17

# 환경변수 등록 (~/.zshrc 에 추가)
echo 'export JAVA_HOME=$(brew --prefix openjdk@17)' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 확인
java -version   # openjdk 17.x.x
```

Gradle은 `gradlew`(Gradle Wrapper) 사용 — 별도 설치 불필요.

---

## 3. DB — PostgreSQL 16

```bash
brew install postgresql@16
brew services start postgresql@16

# 환경변수 등록
echo 'export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# DB + 유저 생성
createdb pokemon_card_db
psql -d pokemon_card_db -c "CREATE USER nightfury WITH PASSWORD 'nightfury';"
psql -d pokemon_card_db -c "GRANT ALL PRIVILEGES ON DATABASE pokemon_card_db TO nightfury;"
psql -d pokemon_card_db -c "ALTER DATABASE pokemon_card_db OWNER TO nightfury;"
```

### 스키마 + 데이터 복원
```bash
cd pokemon_card_app/db

# 스키마 먼저
psql -U nightfury -d pokemon_card_db -f schema.sql

# 카드/제품 데이터 (약 17,000장)
gunzip -c seed_data.sql.gz | psql -U nightfury -d pokemon_card_db

# 시세 스냅샷 (약 15만 건)
gunzip -c seed_price_snapshots.sql.gz | psql -U nightfury -d pokemon_card_db

echo "DB 복원 완료"
```

---

## 4. 프론트엔드 — Flutter

```bash
# Flutter SDK 다운로드 (공식 사이트에서)
# https://docs.flutter.dev/get-started/install/macos

# 또는 brew로
brew install --cask flutter

# 확인
flutter doctor   # 빨간 항목 체크

# iOS 시뮬레이터용
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### Xcode (iOS 개발 필수)
App Store에서 **Xcode** 설치 (약 12GB).  
설치 후:
```bash
xcodebuild -version   # Xcode 16.x 확인
```

### CocoaPods (iOS 패키지)
```bash
sudo gem install cocoapods
```

---

## 5. Python — 그레이딩 서비스

```bash
brew install python@3.11

cd pokemon_card_app/grading
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt`가 없으면 직접 설치:
```bash
pip install fastapi uvicorn opencv-python-headless numpy pillow python-multipart
```

---

## 6. Ollama — 카드 스캐너 AI

```bash
brew install ollama

# llava 모델 다운로드 (약 4.5GB, 한 번만)
ollama pull llava

# 동작 확인
curl http://localhost:11434/api/tags
```

Ollama는 brew 설치 후 자동으로 백그라운드 실행됨 (port 11434).

---

## 7. 코드 클론 및 실행

```bash
git clone https://github.com/nightfury9424/pokemon-card-app.git
cd pokemon-card-app
```

### 백엔드 실행
```bash
cd back
./gradlew bootRun
# http://localhost:8080
```

### 그레이딩 서비스 실행
```bash
cd grading
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 프론트 실행
```bash
cd front
flutter pub get
cd ios && pod install && cd ..
flutter run -d <device_id>

# 연결된 기기 확인
flutter devices
```

---

## 8. application.properties 수정

`back/src/main/resources/application.properties` 에서 맥 IP 주소 확인 후 수정:

```bash
# 맥 IP 확인
ipconfig getifaddr en0
```

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/pokemon_card_db
spring.datasource.username=nightfury
spring.datasource.password=nightfury
ollama.base-url=http://localhost:11434
ollama.model=llava
```

Flutter `front/lib/core/constants/api_constants.dart` 에서 IP 수정:
```dart
static const String baseUrl = 'http://<맥IP>:8080';
```

---

## 9. 설치 요약

| 도구 | 용도 | 설치 방법 |
|------|------|----------|
| Java 17 | Spring Boot 백엔드 | `brew install openjdk@17` |
| PostgreSQL 16 | 카드/시세 DB | `brew install postgresql@16` |
| Flutter | iOS 앱 | `brew install --cask flutter` |
| Xcode | iOS 빌드 | App Store |
| CocoaPods | iOS 패키지 | `sudo gem install cocoapods` |
| Python 3.11 | 그레이딩 분석 | `brew install python@3.11` |
| Ollama + llava | 카드 스캐너 AI | `brew install ollama && ollama pull llava` |
| Git | 버전 관리 | `brew install git` |
