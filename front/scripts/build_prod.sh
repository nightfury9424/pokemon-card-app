#!/usr/bin/env bash
# Phase 1-5: Flutter prod 빌드 가드.
# BASE_URL env 미설정/localhost/non-HTTPS면 fail. dart-define 누락 방지.
#
# 사용:
#   BASE_URL=https://api.pokefolio.kr ./scripts/build_prod.sh ipa
#   BASE_URL=https://api.pokefolio.kr ./scripts/build_prod.sh apk
#   BASE_URL=https://api.pokefolio.kr ./scripts/build_prod.sh appbundle
set -euo pipefail

TARGET="${1:-ipa}"   # ipa(default) | apk | appbundle

if [ -z "${BASE_URL:-}" ]; then
    echo "ERROR: BASE_URL env required." >&2
    echo "  e.g., BASE_URL=https://api.pokefolio.kr ./scripts/build_prod.sh" >&2
    exit 1
fi

if [[ "$BASE_URL" == *localhost* ]] || [[ "$BASE_URL" == *127.0.0.1* ]] || [[ "$BASE_URL" == *0.0.0.0* ]]; then
    echo "ERROR: BASE_URL contains loopback ($BASE_URL). Prod build must use a public URL." >&2
    exit 1
fi

if [[ "$BASE_URL" != https://* ]]; then
    echo "ERROR: BASE_URL must be HTTPS for prod (got: $BASE_URL)." >&2
    echo "  iOS App Transport Security blocks non-HTTPS in release mode." >&2
    exit 1
fi

case "$TARGET" in
    ipa|apk|appbundle) ;;
    *)
        echo "ERROR: unknown target '$TARGET' (use: ipa | apk | appbundle)" >&2
        exit 1
        ;;
esac

cd "$(dirname "$0")/.."
echo "════════════════════════════════════════════════════════"
echo "Flutter prod build"
echo "  TARGET   : $TARGET"
echo "  BASE_URL : $BASE_URL"
echo "════════════════════════════════════════════════════════"

# ── 플랫폼 분리(2026-07-20): 릴리즈는 반드시 플랫폼 진입점으로 빌드 ──
#   ipa            → lib/main_ios.dart     (iOS 셸: Apple 로그인 노출 등)
#   apk/appbundle  → lib/main_android.dart (Android 셸: Apple 로그인 숨김 등)
# 기본 lib/main.dart 는 flutter run/테스트용 폴백 — 릴리즈에 쓰지 않는다.
case "$TARGET" in
    ipa)            ENTRY="lib/main_ios.dart" ;;
    apk|appbundle)  ENTRY="lib/main_android.dart" ;;
esac

# ── 빌드 번호 분리 ──
# pubspec version(1.0.9+9)의 +9 는 Android versionCode 로 쓰인다.
# iOS 는 ASC 관행대로 타임스탬프 빌드 번호를 오버라이드(직전 빌드보다 커야 수락).
# → 두 스토어의 빌드 번호가 pubspec 한 줄에 묶이지 않는다.
EXTRA_ARGS=()
if [ "$TARGET" = "ipa" ]; then
    IOS_BUILD_NUMBER="${IOS_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
    EXTRA_ARGS+=(--build-number="$IOS_BUILD_NUMBER")
    echo "  iOS build number : $IOS_BUILD_NUMBER (타임스탬프, IOS_BUILD_NUMBER env 로 오버라이드 가능)"
fi

# CARD_CDN_BASE — 릴리즈는 CloudFront CDN 주입 필수(SESSION_HANDOFF "dart-define 2종").
# env 미설정이면 코드 기본값(S3 직결)으로 빌드되므로 경고를 남긴다.
if [ -n "${CARD_CDN_BASE:-}" ]; then
    EXTRA_ARGS+=(--dart-define=CARD_CDN_BASE="$CARD_CDN_BASE")
    echo "  CARD_CDN_BASE  : $CARD_CDN_BASE"
else
    echo "  WARNING: CARD_CDN_BASE 미설정 — 코드 기본값(S3 직결)으로 빌드됨. 정식 릴리즈면 CloudFront 값 주입 필요." >&2
fi

flutter build "$TARGET" -t "$ENTRY" --dart-define=BASE_URL="$BASE_URL" --release "${EXTRA_ARGS[@]}"

echo ""
echo "✓ Build complete."
case "$TARGET" in
    ipa)
        echo "  Output: build/ios/ipa/ (TestFlight 업로드 또는 Xcode Organizer)"
        ;;
    apk)
        echo "  Output: build/app/outputs/flutter-apk/app-release.apk"
        ;;
    appbundle)
        echo "  Output: build/app/outputs/bundle/release/app-release.aab"
        ;;
esac
