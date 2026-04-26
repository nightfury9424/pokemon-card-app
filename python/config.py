"""
공통 설정 (API 키, DB 설정)
"""

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "pokemon_card_db",
    "user": "nightfury",
    "password": "",
}

NAVER_CLIENT_ID = "1pqe3fIxLlN0nEH17rHm"
NAVER_CLIENT_SECRET = "mxxa608bPK"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    )
}

# 가격 수집 대상 희귀도 (시세 의미있는 카드들만)
TARGET_RARITIES = ["SAR", "SSR", "CSR", "CHR", "ACE", "UR", "AR", "SR", "RR", "HR", "H"]
