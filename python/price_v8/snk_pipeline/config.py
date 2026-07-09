#!/usr/bin/env python3
"""SNKRDUNK_JP 가격 파이프라인 공통 설정 (dry-run · 로컬 전용).

★ 절대 원칙 (docs/SNK_PRICE_PIPELINE_DESIGN.md)
- scrydex 데이터 절대 덮어쓰지 않음. SNK는 source='SNKRDUNK_JP' 별도.
- approved override만 사용. working mapping ≠ approved.
- 이 패키지는 전부 dry-run/로컬 SQLite. prod DB write 0 · 가격 반영 0.
"""
import os

# ── 경로 ──────────────────────────────────────────────────────────
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))  # repo root
PV8 = os.path.join(ROOT, "python", "price_v8")

# 입력 (분석 단계 산출물 — 읽기 전용, 절대 덮어쓰지 않음)
WORKING_MAPPING_CSV = os.path.join(PV8, "snkrdunk_working_mapping.csv")
SCRYDEX_LADDER_CSV = os.path.join(PV8, "scrydex_jp_ladder_prod.csv")  # card_id,tier,latest,med30,n30 (KRW)
CATALOG_CSV = os.path.join(ROOT, "python", "catalog_gapfill", "prod_cards_full_20260620.csv")
DOWN_FIRST_CSV = os.path.join(PV8, "scrydex_jp_snk_replace_candidates_down_first.csv")  # HIGH 10

# 로컬 파이프라인 DB (dry-run 저장소 — prod 아님)
DB_PATH = os.path.join(os.path.dirname(__file__), "snk_pipeline.sqlite")

# ── 환율 ──────────────────────────────────────────────────────────
# prod price_snapshots SYSTEM 행의 exchange_rate_usd / _jpy ÷ 100.
# (2026-06-29 실측) — 운영 수집기로 승격 시 SYSTEM 행에서 라이브로 읽어야 함.
USD_KRW = 1536.48
JPY_KRW = 9.50
RATE_AS_OF = "2026-06-29"

# ── SNK API ───────────────────────────────────────────────────────
SNK_BASE = "https://snkrdunk.com/v1/apparels/{}"
OPT_A = 18      # raw (used)  — 주력
OPT_PSA10 = 22
OPT_PSA9 = 23
# all(-1) 은 18/22/23 혼합이라 절대 미수집.

# ── 이상치 임계 (분석 단계에서 검증된 값 그대로) ───────────────────
# 정상 ladder = PSA10 > PSA9 > RAW (데이터 84%).
TH_GRADED_INVERSION = 0.9    # PSA10 < PSA9 * 0.9
TH_RAW_OVER_PSA10 = 1.1      # RAW > PSA10 * 1.1
TH_RAW_OVER_PSA9 = 1.2       # RAW > PSA9 * 1.2
TH_PSA10_STALE = 10          # PSA10 / RAW >= 10  (graded premium라 약함·후순위)
TH_PSA9_STALE = 5            # PSA9 / RAW >= 5
TH_SNK_DIV_HIGH = 2.0        # scrydex_RAW / SNK_A >= 2  → scrydex 과대 (하향, 저위험, HIGH)
TH_SNK_DIV_LOW = 0.5         # scrydex_RAW / SNK_A <= 0.5 → scrydex 과소 (상향, 고위험, LOW)
TH_MAPPING_REVIEW = 3.0      # ratio >= 3 또는 <= 1/3 → 매핑 의심
SNK_FLOOR_KRW = 9500         # ¥1,000 × 9.5 = SNK 최저 floor 의심
MIN_N_REPLACE = 5            # A 거래 관측수 n >= 5 만 STRONG 후보
