"""DAANGN price_review_queue 매물 자동 분류 — DINOv2 + 카드명 텍스트 매칭.

각 매물:
1. raw 이미지 (외부 URL) → 다운로드 → DINOv2 임베딩
2. cards.name 텍스트 매칭 (raw_title 안 단어 vs name)
3. cards 전체 임베딩과 cos sim 계산
4. 이미지 sim + 이름 매칭 score 합성 → top-3 auto_candidates
"""
from __future__ import annotations
import json
import re
import time
import urllib.request
from io import BytesIO
from pathlib import Path

import numpy as np
import psycopg2
import torch
import torchvision.transforms as T
from PIL import Image

DEVICE = "cpu"
DATA = Path("/Users/fury/pokemon-card-app/scanner/data/cards")
DB = {"dbname": "pokemon_card_db", "user": "nightfury"}
LOG = Path("/tmp/auto_classify_daangn.log")
HEADERS = {"User-Agent": "Mozilla/5.0 PokeFolio"}

# ── DINOv2 ──
print("Loading DINOv2...", flush=True)
model = torch.hub.load("facebookresearch/dinov2", "dinov2_vits14")
model.eval().to(DEVICE)
tx = T.Compose([
    T.Resize(244), T.CenterCrop(224), T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


def emb_bytes(data: bytes) -> np.ndarray | None:
    try:
        img = Image.open(BytesIO(data)).convert("RGB")
        x = tx(img).unsqueeze(0).to(DEVICE)
        with torch.no_grad():
            f = model(x)
        v = f[0].cpu().numpy().astype(np.float32)
        n = np.linalg.norm(v)
        return v / n if n > 1e-9 else None
    except Exception:
        return None


def dl(url: str) -> bytes | None:
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=12) as r:
            return r.read()
    except Exception:
        return None


# ── KO cards 임베딩 일괄 로드 (KO 이미지 없으면 JP/EN fallback) ──
print("Loading KO card embeddings (KO > JP > EN fallback)...", flush=True)
conn = psycopg2.connect(**DB)
cur = conn.cursor()
cur.execute("""
    SELECT card_id, name, rarity_code, collection_number
    FROM cards WHERE language='KO'
""")
ko_cards = cur.fetchall()
print(f"  candidates (all KO): {len(ko_cards)}", flush=True)

card_meta: list[dict] = []
card_embs: list[np.ndarray] = []
src_stats = {"ko": 0, "jp": 0, "en": 0, "none": 0}
for cid, name, rar, num in ko_cards:
    img_data = None
    src = None
    # 우선순위: KO > JP > EN
    for suffix in ("_ko.png", "_jp.png", "_en.png"):
        p = DATA / f"{cid}{suffix}"
        if p.exists():
            img_data = p.read_bytes()
            src = suffix[1:3]
            break
    if img_data is None:
        src_stats["none"] += 1
        continue
    e = emb_bytes(img_data)
    if e is None:
        src_stats["none"] += 1
        continue
    src_stats[src] += 1
    card_meta.append({"card_id": cid, "name": name, "rarity": rar,
                      "collection_number": num, "img_src": src})
    card_embs.append(e)
ko_matrix = np.stack(card_embs)
print(f"  embeddings ready: {len(card_embs)} | src={src_stats}", flush=True)


# ── 텍스트 매칭 helper ──
# 한글 1자도 포함 (예: "뮤", "유" 같은 카드명)
TOKEN_RE = re.compile(r"[가-힣]+|[A-Za-z]{2,}")
STOP_WORDS = {"포켓몬", "포켓", "카드", "팝니다", "판매", "합니다", "가격", "원본", "관련",
              "꺼주세요", "직거래", "단일", "ex", "EX", "V", "VMAX", "VSTAR", "GX", "TAG", "TEAM",
              "SAR", "SSR", "SR", "HR", "RR", "RRR", "UR", "AR", "CHR", "CSR", "BWR", "ACE", "MA", "MUR"}


def normalize(s: str) -> str:
    return (s or "").lower().replace(" ", "")


def title_tokens(title: str) -> list[str]:
    toks = TOKEN_RE.findall(title or "")
    return [t for t in toks if t not in STOP_WORDS]


# cards 이름 token + lowercase normalized
card_name_norms: list[str] = []
card_tokens: list[list[str]] = []
for m in card_meta:
    card_name_norms.append(normalize(m["name"]))
    card_tokens.append(title_tokens(m["name"]))


def name_score(title: str, idx: int) -> float:
    """카드명 매칭 score.
    - 카드명 전체가 매물 제목에 substring → 1.0
    - 카드명 token 모두 매물 제목에 들어있음 → 0.9
    - 일부 token 매칭 → 비율
    """
    title_norm = normalize(title)
    cn_norm = card_name_norms[idx]
    if not cn_norm:
        return 0.0
    if len(cn_norm) >= 2 and cn_norm in title_norm:
        return 1.0
    cn_toks = card_tokens[idx]
    if not cn_toks:
        return 0.0
    matched = sum(1 for t in cn_toks if normalize(t) in title_norm)
    return matched / len(cn_toks)


# ── 검수 큐 처리 ──
cur.execute("""
    SELECT id, raw_title, image_path
    FROM price_review_queue
    WHERE source='DAANGN' AND status='pending'
      AND (auto_candidates IS NULL OR auto_candidates = '[]'::jsonb)
""")
items = cur.fetchall()
print(f"queue items: {len(items)}", flush=True)

stats = {"ok": 0, "no_img": 0, "no_dl": 0, "err": 0}
t0 = time.time()
log = LOG.open("w")
for i, (rid, title, image_path) in enumerate(items):
    if not image_path:
        stats["no_img"] += 1
        continue
    img_data = dl(image_path) if image_path.startswith("http") else (DATA.parent / image_path).read_bytes()
    if not img_data:
        stats["no_dl"] += 1
        log.write(f"  dl fail {rid}\n"); continue
    raw_emb = emb_bytes(img_data)
    if raw_emb is None:
        stats["no_img"] += 1; continue

    # 이미지 sim
    img_sims = ko_matrix @ raw_emb  # (N,) cos sim
    # 카드명 매칭 score (제목 substring 또는 token overlap)
    name_scores = np.array([name_score(title, j) for j in range(len(card_meta))], dtype=np.float32)
    # 등급 매칭 — 매물 제목의 등급 토큰과 카드 rarity 일치
    title_rarities = set(t.upper() for t in re.findall(
        r'\b(MUR|SAR|SSR|UR|HR|CHR|CSR|BWR|MA|SR|RRR|RR|AR|ACE)\b', title or "", re.I))
    rarity_scores = np.array([
        1.0 if (m["rarity"] and m["rarity"].upper() in title_rarities) else 0.0
        for m in card_meta
    ], dtype=np.float32)
    # 합성: 이름 0.45 + 이미지 0.35 + 등급 0.2
    combined = img_sims * 0.35 + name_scores * 0.45 + rarity_scores * 0.2
    top_idx = np.argsort(-combined)[:10]
    candidates = []
    for ti in top_idx:
        m = card_meta[int(ti)]
        candidates.append({
            "card_id": m["card_id"],
            "name": m["name"],
            "rarity": m["rarity"],
            "collection_number": m["collection_number"],
            "similarity": float(round(img_sims[int(ti)], 4)),
            "name_score": float(round(name_scores[int(ti)], 3)),
        })

    try:
        cur.execute("""
            UPDATE price_review_queue
            SET auto_candidates = %s::jsonb
            WHERE id = %s
        """, (json.dumps(candidates, ensure_ascii=False), rid))
        stats["ok"] += 1
    except Exception as e:
        stats["err"] += 1
        log.write(f"  err {rid}: {e}\n")

    if (i + 1) % 5 == 0:
        conn.commit()
        el = time.time() - t0
        eta = (len(items) - i - 1) * el / (i + 1)
        print(f"  {i+1}/{len(items)} {stats} ({el:.0f}s, eta {eta:.0f}s)", flush=True)

conn.commit()
conn.close()
print(f"DONE: {stats}", flush=True)
log.close()
