"""
python/config.py 템플릿.

운영/베타 서버:
  1) 이 파일을 그대로 두면 환경변수에서 값을 읽음 (os.getenv).
  2) 또는 cp python/config.example.py python/config.py 후 값 직접 입력.
     단 config.py는 .gitignore되어 있으니 절대 커밋되지 않음.

NEVER commit python/config.py with real values.
"""

import os

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "pokemon_card_db"),
    "user": os.getenv("DB_USER", "nightfury"),
    "password": os.getenv("DB_PASSWORD", ""),
}

NAVER_CLIENT_ID = os.getenv("NAVER_CLIENT_ID", "")
NAVER_CLIENT_SECRET = os.getenv("NAVER_CLIENT_SECRET", "")

EBAY_APP_ID = os.getenv("EBAY_APP_ID", "")
EBAY_DEV_ID = os.getenv("EBAY_DEV_ID", "")
EBAY_CERT_ID = os.getenv("EBAY_CERT_ID", "")

HEADERS = {
    "User-Agent": os.getenv(
        "USER_AGENT",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    ),
}

TARGET_RARITIES = os.getenv(
    "TARGET_RARITIES",
    "SR,SAR,AR,UR,CHR,CSR,HR",
).split(",")


# Phase 1-4: psycopg2 DSN 문자열 생성 — env 기반.
# 기존 hardcoded "host=localhost port=5432 dbname=pokemon_card_db user=nightfury" 대체.
def get_db_dsn() -> str:
    """DB_CONFIG → psycopg2 DSN 문자열. password는 비어있으면 생략."""
    c = DB_CONFIG
    parts = [f"host={c['host']}", f"port={c['port']}",
             f"dbname={c['dbname']}", f"user={c['user']}"]
    if c["password"]:
        parts.append(f"password={c['password']}")
    return " ".join(parts)
