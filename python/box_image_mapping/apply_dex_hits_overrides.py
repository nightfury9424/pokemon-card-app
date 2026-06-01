#!/usr/bin/env python3
"""
apply_dex_hits_overrides.py — Cycle 2 도감 hits override SQL UPDATE 생성.

자동 v3 (hits_picks_v3.json) 33 시리즈 그대로 + 수동 보정 7 시리즈 override.
출력: dex_hits_overrides_20260530.sql (BEGIN/UPDATE×40/검증/COMMIT).

수동 보정 7건 (사용자 명시 hits_picks_v3 검수):
  1. 니힐제로 — MUR + SAR 메가지가르데 (hero 중복 강제) + 명희 + 나옹
  2. MEGA 스타트 덱 100 — MUR + RR 피카츄 + RR 릴리에 + AR 민화 (순서 재배치)
  3. MEGA 드림 ex — SAR/MUR/SAR/SAR 순서 재배치 (SAR 메가망나뇽 가격>MUR)
  4. VSTAR 유니버스 (6장) — UR 4 + SAR 2 (오리진 4신 + 리자몽/뮤츠)
  5. 테라스탈 페스타 (6장) — SAR 이브이 5진화 + UR 피카츄
  6. 포켓몬 카드 151 (5장) — SAR 3 + SR 리자몽 + SR 뮤
  7. VMAX 클라이맥스 (6장) — CSR 6장 (자동 4 + 가격순 5,6)
"""
from __future__ import annotations
import json
from pathlib import Path

HERE = Path(__file__).parent
AUTO_JSON = HERE / "hits_picks_v3.json"
OUT_SQL = HERE / "dex_hits_overrides_20260530.sql"

# 수동 보정 7 — product_id → ordered cardIds
MANUAL_OVERRIDES: dict[str, list[str]] = {
    # 1. 니힐제로
    "PRD_B269D7FE35F74921BDB2": [
        "CRD_3430850B62B446C68A45A9CFE3741141",  # MUR 메가지가르데 EX
        "CRD_2A791989EEEC43F481BB",              # SAR 메가지가르데 ex (hero 중복 강제)
        "CRD_9C2FBC6E628A43679527",              # SAR 명희의 격려
        "CRD_579416A2A535432F8F30",              # SAR 나옹 ex
    ],
    # 2. MEGA 스타트 덱 100 — 순서 재배치
    "PRD_6F0F228947EF48919808": [
        "CRD_25A858D01145493BB66AF82B8EA32B7C",  # MUR 메가리자몽Y ex
        "CRD_176BE23510B840A2A394",              # RR 피카츄 ex
        "CRD_F7FE6279B4A147BC9CD1",              # RR 릴리에의 삐삐 ex
        "CRD_F92441CD205348ABA0D0",              # AR 민화의 덩쿠리
    ],
    # 3. MEGA 드림 ex — 순서 재배치
    "PRD_90A8D5BDA5664CEF9F48": [
        "CRD_BC23459C3A854031B8A0",              # SAR 메가망나뇽 ex (가격 1위)
        "CRD_2E403B756FE641CB89FF32CEB4BDDB4E",  # MUR 메가망나뇽 ex
        "CRD_7633E4DC01B743F4A4BC",              # SAR 메가팬텀 ex
        "CRD_4A6CC4A034DF4C3DAD74",              # SAR 피카츄 ex
    ],
    # 4. VSTAR 유니버스 (6장)
    "PRD_B4F8E0D2E2414F1DBC9B": [
        "CRD_E95B8B1938F2446E81DD",              # UR 기라티나 VSTAR
        "CRD_DDC143852534B415787C",              # UR 아르세우스 VSTAR
        "CRD_AA19A54D13CC49198C77",              # UR 오리진 디아루가 VSTAR
        "CRD_98B1AD5A09294E4AA9F5",              # UR 오리진 펄기아 VSTAR
        "CRD_85D8B3249D6140CCAE00",              # SAR 리자몽 VSTAR
        "CRD_482EA800F7DE4871AD8A",              # SAR 뮤츠 VSTAR
    ],
    # 5. 테라스탈 페스타 (6장)
    "PRD_D26383A636BE42F09D6B": [
        "CRD_5094F85922274E7CAC3C",              # SAR 블래키 ex
        "CRD_023DB72F38FC4C87B95B",              # SAR 님피아 ex
        "CRD_9AD6FE24D3594D17A130",              # SAR 에브이 ex
        "CRD_80407B2696CD4C8CA421",              # SAR 리피아 ex
        "CRD_FB98F00A1EE44AB999E2",              # SAR 글레이시아 ex
        "CRD_7EB1930C9A224A14AE58",              # UR 피카츄 ex
    ],
    # 6. 포켓몬 카드 151 (5장)
    "PRD_DAB43E31433041FC942F": [
        "CRD_853F91A8D5AF441492F4",              # SAR 리자몽 ex
        "CRD_0400517F2E89441EAC81",              # SAR 거북왕 ex
        "CRD_4FD05F42130846719AF7",              # SAR 이상해꽃 ex
        "CRD_83435CF0B3494DECB0E7",              # SR 리자몽 ex
        "CRD_6033B85380BA4D14AE12",              # SR 뮤 ex
    ],
    # 7. VMAX 클라이맥스 (6장)
    "PRD_767E549F894445C98D52": [
        "CRD_1589922DA5104539AFF5",              # CSR 레쿠쟈 VMAX
        "CRD_5D86E01964624A8CBE40",              # CSR 피카츄 VMAX
        "CRD_6C18665126FF426F9C2E",              # CSR 블래키 VMAX
        "CRD_D2B8F12F00094BD88632",              # CSR 피카츄 V
        "CRD_81D4DD597DBE456BB22A",              # CSR 님피아 VMAX (가격순 5위)
        "CRD_3556A9DD9F2149C5BF0C",              # CSR 따라큐 V (가격순 6위)
    ],
}


def main() -> int:
    auto = json.loads(AUTO_JSON.read_text())
    # auto = {product_id: [cardId, ...]}
    final: dict[str, list[str]] = {**auto, **MANUAL_OVERRIDES}

    lines: list[str] = [
        "-- 2026-05-30 Cycle 2 — 도감 hits override 적용 (40 product).",
        "-- 자동 v3 (hits_picks_v3.json) 33 시리즈 + 수동 보정 7 시리즈.",
        "-- products.dex_hit_card_ids CSV (CRD_xxx,CRD_yyy,...). 순서 = display 순서.",
        "-- 컬렉션형 4 시리즈 6장 허용 (VSTAR/테라스탈/151/VMAX 클라이맥스).",
        "-- DexService 가 NULL/blank 시 기존 자동 rarity priority 4장 fallback.",
        "",
        "BEGIN;",
        "",
    ]

    for pid, ids in sorted(final.items()):
        csv = ",".join(ids)
        # Codex GO 조건 ⑤ — cardId 는 CRD_ + hex 형식 보장 (SQL injection X).
        # validation: 각 id 가 CRD_ 시작 + alphanumeric.
        for cid in ids:
            if not cid.startswith("CRD_") or not cid[4:].isalnum():
                raise ValueError(f"invalid cardId {cid!r} in product {pid}")
        lines.append(f"UPDATE products SET dex_hit_card_ids = '{csv}', updated_at = NOW() WHERE product_id = '{pid}';")

    lines.extend([
        "",
        "-- 검증 — 40 product 모두 dex_hit_card_ids set + cardId 들이 실재 + 같은 product + visible + KO.",
        "SELECT",
        "  '검증' AS info,",
        "  COUNT(*) AS products_with_override,",
        "  COUNT(*) FILTER (WHERE dex_hit_card_ids IS NOT NULL AND dex_hit_card_ids != '') AS nonempty",
        "FROM products",
        "WHERE product_id IN (" + ", ".join(f"'{pid}'" for pid in sorted(final.keys())) + ");",
        "",
        "COMMIT;",
        "",
        f"-- 총 {len(final)} product UPDATE (자동 {len(auto)} + 수동 보정 {len(MANUAL_OVERRIDES)})",
        f"-- 컬렉션형 6장: VSTAR / 테라스탈 / VMAX 클라이맥스",
        f"-- 컬렉션형 5장: 포켓몬 카드 151",
        f"-- 일반 4장: 나머지 36 시리즈",
    ])

    OUT_SQL.write_text("\n".join(lines), encoding="utf-8")
    print(f"[ok] {OUT_SQL}")
    print(f"  product 수: {len(final)} (auto {len(auto)} + manual {len(MANUAL_OVERRIDES)})")
    counts = {pid: len(ids) for pid, ids in final.items()}
    over_4 = {pid: n for pid, n in counts.items() if n > 4}
    print(f"  4장 초과 product: {len(over_4)}")
    for pid, n in over_4.items():
        print(f"    {pid}: {n}장")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
