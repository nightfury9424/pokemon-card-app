#!/bin/bash
set -e
LOG=/opt/pokefolio/data/logs/v6_apply_$(date +%Y%m%d).log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) v6_apply start ==="
SCRIPT=/opt/pokefolio/scripts/v6_apply.py
PCJSON=/opt/pokefolio/scripts/all_cards.json
for f in "$SCRIPT" "$PCJSON"; do
  if [ ! -f "$f" ]; then
    echo "ABORT: required file missing: $f"
    exit 1
  fi
done
docker cp "$SCRIPT" pokefolio-back:/tmp/v6_apply.py
docker cp "$PCJSON" pokefolio-back:/tmp/all_cards.json
docker exec pokefolio-back /usr/bin/python3 /tmp/v6_apply.py
echo "=== $(date -Iseconds) v6_apply done ==="
