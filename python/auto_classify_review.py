"""price_review_queue 자동 분류 — DINOv2 top-3 후보 + 제목 정밀화.

- raw image → DINOv2 embedding → cards 전체와 cos sim top-3
- 제목 regex → lang (KO/JP/EN), grade, bundle 정밀화
- DB update: auto_candidates (정확한 score 포함), auto_lang, auto_grade_*, auto_is_bundle
"""
from __future__ import annotations
import json
import re
import time
from io import BytesIO
from pathlib import Path

import numpy as np
import psycopg2
import torch
import torchvision.transforms as T
from PIL import Image

DEVICE = "cpu"
DATA_DIR = Path("/Users/fury/pokemon-card-app/scanner/data")
DB = {"dbname": "pokemon_card_db", "user": "nightfury"}

# ───── DINOv2 ─────
print("Loading DINOv2...", flush=True)
model = torch.hub.load("facebookresearch/dinov2", "dinov2_vits14")
model.eval().to(DEVICE)
tx = T.Compose([
    T.Resize(244), T.CenterCrop(224), T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


def emb_from_path(p: Path) -> np.ndarray | None:
    try:
        img = Image.open(p).convert("RGB")
        x = tx(img).unsqueeze(0).to(DEVICE)
        with torch.no_grad():
            f = model(x)
        v = f[0].cpu().numpy().astype(np.float32)
        n = np.linalg.norm(v)
        return v / n if n > 1e-9 else None
    except Exception:
        return None


# ───── 제목 분류 regex ─────
LANG_JP = re.compile(r"일판|일본판|일어판|JP|jp판", re.I)
LANG_EN = re.compile(r"북미판|영문판|영판|미판|EN|영어판", re.I)
LANG_KO = re.compile(r"한국판|한판|한글판|KO|국내판", re.I)
GRADE = re.compile(r"\b(PSA|BGS|BRG|CGC|SGC)\s*([\d.]+)\b", re.I)
BUNDLE = re.compile(
    r"(\d+\s*장(?!\s*카드$))|일괄|뭉치|싱글\s*\d+|싱글총|묶음|벌크|대량|"
    r"세트|전판|컬렉션|덱|박스|팩|수십|수백"
)


def classify_title(title: str):
    title = title or ""
    # lang
    if LANG_JP.search(title): lang = "JP"
    elif LANG_EN.search(title): lang = "EN"
    elif LANG_KO.search(title): lang = "KO"
    else: lang = None
    # grade
    g = GRADE.search(title)
    gc = gv = None
    if g:
        gc = g.group(1).upper()
        gv = g.group(2)
        if gc == "BGS":
            # BGS는 우리 시스템에선 사용 X. BRG로 간주 X — 그대로
            pass
    # bundle
    bundle = bool(BUNDLE.search(title))
    return lang, gc, gv, bundle


# ───── KO 카드 임베딩 캐시 (큰 메모리 1회 로드) ─────
print("Loading KO card embeddings...", flush=True)
conn = psycopg2.connect(**DB)
cur = conn.cursor()
cur.execute("""
    SELECT card_id, name, rarity_code, collection_number, official_card_code
    FROM cards WHERE language='KO' AND image_url IS NOT NULL AND image_url != ''
""")
ko_cards = cur.fetchall()
print(f"KO cards with image: {len(ko_cards)}", flush=True)

card_meta: list[dict] = []
card_embs: list[np.ndarray] = []
for cid, name, rar, num, code in ko_cards:
    p = DATA_DIR / "cards" / f"{cid}_ko.png"
    if not p.exists():
        continue
    e = emb_from_path(p)
    if e is None:
        continue
    card_meta.append({"card_id": cid, "name": name, "rarity": rar,
                      "collection_number": num, "official_card_code": code})
    card_embs.append(e)
ko_matrix = np.stack(card_embs) if card_embs else None
print(f"KO embeddings ready: {len(card_embs)}", flush=True)

# ───── review_queue 분류 ─────
cur.execute("""
    SELECT id, raw_title, image_path
    FROM price_review_queue
    WHERE status='pending'
    ORDER BY created_at
""")
items = cur.fetchall()
print(f"queue items: {len(items)}", flush=True)

t0 = time.time()
ok = no_img = err = 0
for i, (rid, title, image_path) in enumerate(items):
    # 제목 분류
    lang, gc, gv, bundle = classify_title(title)

    # 이미지 임베딩 + top-3
    candidates: list[dict] = []
    if image_path:
        p = DATA_DIR / image_path if not image_path.startswith("/") else Path(image_path)
        if p.exists() and ko_matrix is not None:
            e = emb_from_path(p)
            if e is not None:
                sims = ko_matrix @ e  # cos sim (normalized)
                top_idx = np.argsort(-sims)[:5]
                for ti in top_idx:
                    m = card_meta[int(ti)]
                    candidates.append({
                        "card_id": m["card_id"],
                        "name": m["name"],
                        "rarity": m["rarity"],
                        "collection_number": m["collection_number"],
                        "similarity": float(round(sims[int(ti)], 4)),
                    })
                ok += 1
            else:
                no_img += 1
        else:
            no_img += 1
    else:
        no_img += 1

    try:
        cur.execute("""
            UPDATE price_review_queue SET
              auto_candidates = COALESCE(%s::jsonb, auto_candidates),
              auto_lang = COALESCE(%s, auto_lang),
              auto_grade_company = COALESCE(%s, auto_grade_company),
              auto_grade_value = COALESCE(%s, auto_grade_value),
              auto_is_bundle = (%s OR auto_is_bundle)
            WHERE id = %s
        """, (
            json.dumps(candidates, ensure_ascii=False) if candidates else None,
            lang, gc, gv, bundle, rid,
        ))
    except Exception as e:
        err += 1
        print(f"err {rid}: {e}", flush=True)

    if (i + 1) % 50 == 0:
        conn.commit()
        el = time.time() - t0
        eta = (len(items) - i - 1) * el / (i + 1)
        print(f"  {i+1}/{len(items)} ok={ok} no_img={no_img} ({el:.0f}s, eta {eta:.0f}s)", flush=True)

conn.commit()
conn.close()
print(f"DONE: ok={ok} no_img={no_img} err={err}", flush=True)
