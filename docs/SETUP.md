# 새 맥 세팅 가이드

## 환경 스펙 (M4 Pro MacBook Pro 기준)

| 항목 | 버전 |
|------|------|
| macOS | Sequoia 15.x (arm64) |
| Java | JDK 20.0.2 (Oracle) |
| Spring Boot | 4.0.4 |
| Flutter | 3.41.4 (stable) |
| Xcode | 16.x |
| CocoaPods | 1.16.2 |
| PostgreSQL | 14.x (Homebrew) |
| Miniconda | 최신 (Python 3.11, scanner_v2 env) |

---

## 1. 기본 도구

```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

## 2. Java 20

Oracle 공식에서 macOS ARM64 DMG 설치 후 `~/.zshrc`에 추가:
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-20.0.2.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH
```

## 3. PostgreSQL 14

```bash
brew install postgresql@14
brew services start postgresql@14
echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

psql postgres
# CREATE USER nightfury WITH SUPERUSER;
# CREATE DATABASE pokemon_card_db OWNER nightfury;

# 스키마 + 데이터 복원
psql -U nightfury -d pokemon_card_db -f db/schema.sql
gunzip -c db/seed_data.sql.gz | psql -U nightfury -d pokemon_card_db
gunzip -c db/seed_price_snapshots.sql.gz | psql -U nightfury -d pokemon_card_db
# → cards 9,728장 (C/U/R 제외), price_snapshots ~149,000건
```

## 4. Flutter 3.41.4

```bash
mkdir -p ~/develop && cd ~/develop
curl -L -o flutter.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.4-stable.zip
unzip flutter.zip && rm flutter.zip
echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Rosetta (iproxy 필요)
sudo softwareupdate --install-rosetta --agree-to-license
```

## 5. Xcode + CocoaPods

```bash
# App Store에서 Xcode 16 설치 후
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo gem install cocoapods -v 1.16.2
```

## 6. Miniconda (스캐너 ML 환경)

```bash
# Miniconda 설치 후
conda tos accept
conda create -n scanner_v2 python=3.11
conda activate scanner_v2
pip install torch torchvision transformers faiss-cpu opencv-python pillow \
            fastapi uvicorn python-multipart tqdm psycopg2-binary
```

## 7. 코드 클론 + 설정

```bash
git clone https://github.com/nightfury9424/pokemon-card-app.git
```

**back/src/main/resources/application.properties** 수정:
```properties
card.image.dir=/Users/<유저명>/pokemon-card-app/scanner/data/cards
trade.image.dir=/Users/<유저명>/pokemon-card-app/trade_images
```

**front/lib/core/constants/api_constants.dart** 수정:
```dart
static const String baseUrl = 'http://<맥IP>:8080';
```
IP 확인: `ipconfig getifaddr en0`

## 8. iOS 앱 설정

```bash
cd front && flutter pub get && cd ios && pod install
open ios/Runner.xcworkspace
# Runner → Signing & Capabilities → Team 선택
```

## 9. 카드 이미지 다운로드 (선택)

scrydex에서 EN/JP 이미지 다운로드 (~8,450장):
```bash
cd scanner/data
python download_scrydex.py   # scrydex_refs.csv 필요
```

## zshrc 최종 참고

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
