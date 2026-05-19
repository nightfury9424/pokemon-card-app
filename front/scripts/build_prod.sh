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

flutter build "$TARGET" --dart-define=BASE_URL="$BASE_URL" --release

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
