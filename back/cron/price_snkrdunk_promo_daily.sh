#!/bin/bash
# SNKRDUNK-only 프로모 KO 시세 일일 동기화 (scrydex 동기화와 나란히).
# 대상: is_promo_exclusive=TRUE + card_external_refs(source='SNKRDUNK') 매핑 카드.
# v6 / scrydex sync / sanity cap 경로를 타지 않는 별도 레인. (스크립트 상단 주석 참조)
#
# crontab 등록 예 (KST 23:58 — 백엔드 KO 갱신 23:45 이후, 안전하게 뒤):
#   58 23 * * * /opt/pokefolio/scripts/cron/price_snkrdunk_promo_daily.sh
set -e
LOG=/opt/pokefolio/data/logs/snkrdunk_promo_$(date +%Y%m%d).log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) snkrdunk_promo start ==="

SCRIPT=/opt/pokefolio/scripts/sync_snkrdunk_promo_prices.py
CONFIG=/opt/pokefolio/scripts/config.py
for f in "$SCRIPT" "$CONFIG"; do
  if [ ! -f "$f" ]; then
    echo "ABORT: required file missing: $f"
    exit 1
  fi
done

docker cp "$SCRIPT" pokefolio-back:/tmp/sync_snkrdunk_promo_prices.py
docker cp "$CONFIG" pokefolio-back:/tmp/config.py
# ★--apply 로 실제 반영. 최초 배포/의심 시 --apply 빼고 dry-run 로 먼저 검증.
docker exec -w /tmp pokefolio-back /usr/bin/python3 /tmp/sync_snkrdunk_promo_prices.py --apply
echo "=== $(date -Iseconds) snkrdunk_promo done ==="
