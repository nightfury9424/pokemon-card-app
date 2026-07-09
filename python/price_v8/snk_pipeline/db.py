#!/usr/bin/env python3
"""SNKRDUNK_JP 파이프라인 로컬 SQLite 스키마 (dry-run 저장소).

3개 테이블:
  approved_mapping  — working→approved 승인게이트
  snk_snapshot      — SNK 일일 수집 스냅샷 (★ 미래 prod price_snapshots source='SNKRDUNK_JP' 미러)
  review_queue      — 이상치 디텍터 출력 → 사람 검수 대기

prod DB 와 무관. 운영 반영(별도 세션) 때 snk_snapshot 스키마를 price_snapshots
source='SNKRDUNK_JP' 행으로 옮기고, approved_mapping 은 override lookup 으로 쓴다.
"""
import sqlite3
from . import config

SCHEMA = """
-- ① 승인게이트: working(미승인) → approved(운영-확정) 매핑
CREATE TABLE IF NOT EXISTS approved_mapping (
    card_id              TEXT PRIMARY KEY,
    our_name             TEXT,
    our_jp_ref           TEXT,
    our_rarity           TEXT,
    snkrdunk_apparel_id  INTEGER NOT NULL,
    snk_product_number   TEXT,
    mapping_status       TEXT NOT NULL DEFAULT 'WORKING',  -- WORKING | APPROVED | REJECTED
    mapping_confidence   TEXT,
    approved_by          TEXT,
    approved_at          TEXT,
    notes                TEXT,
    source_decided_at    TEXT,
    loaded_at            TEXT
);

-- ② SNK 일일 수집 스냅샷 (price_snapshots source='SNKRDUNK_JP' 미러)
--    scrydex 행 절대 불변. tier/range/basis 차원으로 raw 보존.
CREATE TABLE IF NOT EXISTS snk_snapshot (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id              TEXT NOT NULL,
    snkrdunk_apparel_id  INTEGER NOT NULL,
    source               TEXT NOT NULL DEFAULT 'SNKRDUNK_JP',
    tier                 TEXT NOT NULL,          -- A | PSA10 | PSA9
    range_label          TEXT NOT NULL,          -- 1m | 3m
    basis                TEXT NOT NULL,          -- median | latest
    points_count         INTEGER NOT NULL DEFAULT 0,   -- n (거래 관측수)
    price_jpy            INTEGER NOT NULL DEFAULT 0,
    price_krw            INTEGER NOT NULL DEFAULT 0,
    used_min_price_jpy   INTEGER DEFAULT 0,      -- ASK 보조 (실거래 아님)
    used_listing_count   INTEGER DEFAULT 0,
    exchange_rate_jpy    REAL NOT NULL,          -- 환산에 쓴 환율 (감사용)
    data_quality         TEXT,                   -- A_1M_OK | A_3M_FB | PSA_ONLY | A_NO_PTS
    collected_at         TEXT NOT NULL,
    run_id               TEXT NOT NULL,
    UNIQUE(card_id, tier, range_label, basis, run_id)
);
CREATE INDEX IF NOT EXISTS idx_snap_card ON snk_snapshot(card_id);
CREATE INDEX IF NOT EXISTS idx_snap_run  ON snk_snapshot(run_id);

-- ③ 이상치 검수 큐 (디텍터 출력 → 사람 승인. 자동 적용 0)
CREATE TABLE IF NOT EXISTS review_queue (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id                      TEXT NOT NULL,
    card_id                     TEXT NOT NULL,
    card_name                   TEXT,
    rarity                      TEXT,
    collection_number           TEXT,
    snkrdunk_apparel_id         INTEGER,
    scrydex_raw_krw             INTEGER,
    scrydex_psa10_krw           INTEGER,
    scrydex_psa9_krw            INTEGER,
    snk_A_krw                   INTEGER,
    snk_A_basis                 TEXT,
    snk_A_n                     INTEGER,   -- ★ basis 윈도우 거래수 (값과 동일 윈도우)
    snk_A_n_3m                  INTEGER,   -- 3개월 거래수 (참고·robustness)
    scrydex_raw_to_snk_A_ratio  REAL,
    ladder_violation            TEXT,
    action_status               TEXT,   -- REPLACE_WITH_SNK_A | REVIEW_SNK_THIN | MAPPING_REVIEW | KEEP_SCRYDEX
    replacement_confidence      TEXT,   -- STRONG_REPLACE | REVIEW_REPLACE | LADDER_INFO_ONLY | MAPPING_REVIEW | KEEP
    priority                    TEXT,   -- HIGH (하향·저위험) | LOW (상향·고위험) | NONE
    floor_suspect               TEXT,
    review_status               TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
        -- PENDING_REVIEW | APPROVED_REPLACE_WITH_SNK | REJECTED_KEEP_SCRYDEX | HOLD | MAPPING_REVIEW
    reviewed_by                 TEXT,
    reviewed_at                 TEXT,
    review_note                 TEXT,
    detected_at                 TEXT NOT NULL,
    UNIQUE(card_id, run_id)
);
CREATE INDEX IF NOT EXISTS idx_rq_status ON review_queue(review_status);
CREATE INDEX IF NOT EXISTS idx_rq_prio   ON review_queue(priority);
"""


def connect(path: str = None) -> sqlite3.Connection:
    conn = sqlite3.connect(path or config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init(path: str = None) -> sqlite3.Connection:
    conn = connect(path)
    conn.executescript(SCHEMA)
    # 기존 DB(컬럼 추가 전 생성분) 멱등 마이그레이션
    have = {r[1] for r in conn.execute("PRAGMA table_info(review_queue)")}
    for col in ("reviewed_by", "reviewed_at", "review_note"):
        if col not in have:
            conn.execute(f"ALTER TABLE review_queue ADD COLUMN {col} TEXT")
    if "snk_A_n_3m" not in have:
        conn.execute("ALTER TABLE review_queue ADD COLUMN snk_A_n_3m INTEGER")
    conn.commit()
    return conn


if __name__ == "__main__":
    c = init()
    tabs = [r[0] for r in c.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    print(f"[db] init OK → {config.DB_PATH}")
    print(f"[db] tables: {tabs}")
