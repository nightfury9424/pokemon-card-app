# 새 맥 세팅 가이드

> 이 문서는 현재 개발 환경을 **그대로** 복제하기 위한 가이드입니다.
> Claude에게 이 파일을 보여주고 "SETUP.md 보고 똑같이 세팅해줘" 하면 됩니다.

---

## 현재 환경 스펙 (기준 맥)

| 항목 | 버전 |
|------|------|
| macOS | Sonoma 14.6.1 (arm64, Apple Silicon) |
| Java | JDK 20.0.2 (Oracle) |
| Spring Boot | 4.0.4 |
| Flutter | 3.41.4 (stable) |
| Dart | 3.11.1 |
| Xcode | 16.2 |
| CocoaPods | 1.16.2 |
| PostgreSQL | 14.17 (Homebrew) |
| Python | 3.13.2 (Homebrew) |
| Shell | zsh + Oh My Zsh |

---

## 1. Homebrew 설치

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

설치 후 터미널에 표시되는 `eval "$(/opt/homebrew/bin/brew shellenv)"` 명령 실행.

---

## 2. Oh My Zsh 설치

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

---

## 3. Java JDK 20.0.2 설치

Oracle 공식 다운로드에서 macOS ARM64용 `.dmg` 파일 설치:
```
https://www.oracle.com/java/technologies/javase/jdk20-archive-downloads.html
→ macOS ARM64 DMG Installer (jdk-20.0.2_macos-aarch64_bin.dmg)
```

설치 후 `~/.zshrc`에 추가:
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-20.0.2.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH
```

```bash
source ~/.zshrc
java -version   # java version "20.0.2" 확인
```

---

## 4. PostgreSQL 14 설치

```bash
brew install postgresql@14
brew services start postgresql@14

echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

psql --version   # psql (PostgreSQL) 14.x 확인
```

### DB 생성

```bash
# 기본 postgres 유저로 접속
psql postgres

# psql 프롬프트에서 실행:
CREATE USER nightfury WITH SUPERUSER;
CREATE DATABASE pokemon_card_db OWNER nightfury;
\q
```

### 스키마 + 데이터 복원

```bash
cd ~/pokemon_card_app/db

# 1. 스키마
psql -U nightfury -d pokemon_card_db -f schema.sql

# 2. 카드/제품/세트매핑 데이터 (17,599장)
gunzip -c seed_data.sql.gz | psql -U nightfury -d pokemon_card_db

# 3. 시세 데이터 (149,297건)
gunzip -c seed_price_snapshots.sql.gz | psql -U nightfury -d pokemon_card_db

# 확인
psql -U nightfury -d pokemon_card_db -c "SELECT COUNT(*) FROM cards;"
# → 17599
```

---

## 5. Flutter 3.41.4 설치

Flutter는 SDK 폴더를 직접 받아서 설치 (brew 아님):

```bash
mkdir -p ~/develop
cd ~/develop

# Flutter 3.41.4 다운로드
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.4-stable.zip

unzip flutter_macos_arm64_3.41.4-stable.zip
rm flutter_macos_arm64_3.41.4-stable.zip
```

`~/.zshrc`에 추가:
```bash
export PATH="$HOME/develop/flutter/bin:$PATH"
```

```bash
source ~/.zshrc
flutter --version   # Flutter 3.41.4 확인
flutter doctor      # 이슈 확인
```

---

## 6. Xcode 설치

App Store에서 **Xcode 16** 설치 (약 12GB, 시간 걸림).

설치 후:
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -version   # Xcode 16.x 확인

# iOS 시뮬레이터 다운로드 (Xcode → Settings → Platforms → iOS)
```

---

## 7. CocoaPods 설치

```bash
sudo gem install cocoapods -v 1.16.2
pod --version   # 1.16.2 확인
```

---

## 8. Python 3.13 + 그레이딩 서비스

```bash
brew install python@3.13

python3 --version   # Python 3.13.x 확인
```

그레이딩 venv 셋업:
```bash
cd ~/pokemon_card_app/grading
python3 -m venv venv
source venv/bin/activate
pip install \
  fastapi==0.111.0 \
  uvicorn==0.29.0 \
  python-multipart==0.0.9 \
  "opencv-python-headless==4.9.0.80" \
  "numpy==1.26.4" \
  pytest==8.2.0 \
  httpx==0.27.0
```

---

## 9. 스캐너 v2 — DINOv2 + FAISS (신규 개발 대상)

Ollama llava 방식은 폐기. 새 노트북에서 DINOv2+FAISS 방식으로 새로 구현.
→ **`SCANNER_DEV.md` 참고해서 구현 시작**

> Ollama는 설치 불필요.

---

## 10. 코드 클론

```bash
cd ~
git clone https://github.com/nightfury9424/pokemon-card-app.git pokemon_card_app
cd pokemon_card_app
```

---

## 11. application.properties 수정

**파일**: `back/src/main/resources/application.properties`

수정할 항목:

```bash
# 현재 맥 IP 확인
ipconfig getifaddr en0
```

```properties
# 이미지 저장 경로 — 새 맥 경로로 수정
card.image.dir=/Users/<유저명>/pokemon_card_app/scanner/data/cards
trade.image.dir=/Users/<유저명>/pokemon_card_app/trade_images

# DB 비밀번호 없음 (빈 값 유지)
spring.datasource.password=
```

**파일**: `front/lib/core/constants/api_constants.dart`

```dart
// 새 맥 IP로 수정
static const String baseUrl = 'http://<새맥IP>:8080';
```

---

## 12. iOS 앱 세팅

```bash
cd ~/pokemon_card_app/front
flutter pub get
cd ios
pod install
cd ..
```

Xcode에서 서명 설정:
```bash
open ios/Runner.xcworkspace
```
- **Runner 타겟 → Signing & Capabilities**
- Team 선택 또는 "Automatically manage signing" 체크
- Bundle ID: `com.fury.pokemoncardapp`

---

## 13. 실행 순서

터미널 4개 열기:

**① 백엔드**
```bash
cd ~/pokemon_card_app/back
./gradlew bootRun
# http://localhost:8080/swagger-ui.html 확인
```

**② 그레이딩 서비스**
```bash
cd ~/pokemon_card_app/grading
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8081
```

**③ Flutter 앱**
```bash
cd ~/pokemon_card_app/front
flutter run -d <device_id>

# 연결 기기 확인
flutter devices
```

**④ 스캐너 v2** (DINOv2 FastAPI, SCANNER_DEV.md 구현 후)
```bash
cd scanner_v2
uvicorn main:app --host 0.0.0.0 --port 8082
```

---

## 14. zshrc 최종 상태 참고

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-20.0.2.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH
export PATH="$HOME/develop/flutter/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
```

---

## 카카오 로그인 (옵션)

카카오 디벨로퍼스에서 앱 등록 필요:
- `https://developers.kakao.com`
- 현재 키는 `application.properties`의 `kakao.rest-api-key` 참고
- 새 기기에서 테스트 시 카카오 앱 설정 → 플랫폼 → iOS 번들 ID 추가 필요
