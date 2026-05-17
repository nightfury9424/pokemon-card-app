#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "▶ 기존 서비스 종료..."
lsof -ti:8080,8081,8082 | xargs kill -9 2>/dev/null || true
sleep 1

echo "▶ 백엔드 (8080) 시작..."
cd "$ROOT/back"
./gradlew bootRun > /tmp/back.log 2>&1 &

echo "▶ 그레이딩 (8081) 시작..."
cd "$ROOT/grading"
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8081 > /tmp/grading.log 2>&1 &

echo "▶ 스캐너 (8082) 시작..."
cd "$ROOT/scanner"
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app --host 0.0.0.0 --port 8082 > /tmp/scanner.log 2>&1 &

echo "▶ 서비스 대기 중..."
until grep -q "Started BackApplication" /tmp/back.log 2>/dev/null; do sleep 2; done
echo "  백엔드 8080 ✅"

until grep -q "Application startup complete" /tmp/grading.log 2>/dev/null; do sleep 1; done
echo "  그레이딩 8081 ✅"

until curl -s http://localhost:8082/health 2>/dev/null | grep -q '"status":"ok"'; do sleep 2; done
echo "  스캐너 8082 ✅"

echo ""
echo "✅ 전체 서비스 준비 완료"
