"""Continuous classify daemon — BFS가 새 매물 ins할 때마다 즉시 분류.

DINOv2 1회 load + KO 임베딩 cache + loop:
  - SELECT pending AND auto_candidates IS NULL
  - 있으면 batch 처리, 다 처리되면 30s sleep
  - BFS 진행 중에도 새 매물 즉시 분류 → 사용자 검수 항상 가능
"""
from __future__ import annotations
import json
import re
import sys
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
HEADERS = {"User-Agent": "Mozilla/5.0 PokeFolio"}
LOG = Path("/tmp/classify_daemon.log")

print("Loading DINOv2...", flush=True)
model = torch.hub.load("facebookresearch/dinov2", "dinov2_vits14")
model.eval().to(DEVICE)
tx = T.Compose([
    T.Resize(244), T.CenterCrop(224), T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


def emb_bytes(data: bytes):
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


def dl(url: str):
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.read()
    except Exception:
        return None


# ── KO 카드 임베딩 1회 load ──
print("Loading KO embeddings (ko>jp>en fallback)...", flush=True)
conn = psycopg2.connect(**DB)
cur = conn.cursor()
cur.execute("SELECT card_id, name, rarity_code, collection_number FROM cards WHERE language='KO'")
ko_cards = cur.fetchall()

card_meta = []
card_embs = []
src_stats = {"ko": 0, "jp": 0, "en": 0, "none": 0}
for cid, name, rar, num in ko_cards:
    data, src = None, None
    for suffix in ("_ko.png", "_jp.png", "_en.png"):
        p = DATA / f"{cid}{suffix}"
        if p.exists():
            data, src = p.read_bytes(), suffix[1:3]
            break
    if not data:
        src_stats["none"] += 1; continue
    e = emb_bytes(data)
    if e is None:
        src_stats["none"] += 1; continue
    src_stats[src] += 1
    card_meta.append({"card_id": cid, "name": name, "rarity": rar, "collection_number": num})
    card_embs.append(e)
ko_matrix = np.stack(card_embs)
print(f"KO emb: {len(card_meta)} | src={src_stats}", flush=True)

# 이름 매칭 helper
TOKEN_RE = re.compile(r"[가-힣]+|[A-Za-z]{2,}")
STOP_WORDS = {"포켓몬","포켓","카드","팝니다","판매","합니다","가격","원본","관련","꺼주세요","직거래","단일",
              "ex","EX","V","VMAX","VSTAR","GX","TAG","TEAM","SAR","SSR","SR","HR","RR","RRR","UR","AR",
              "CHR","CSR","BWR","ACE","MA","MUR"}
RARITY_RE = re.compile(r'\b(MUR|SAR|SSR|UR|HR|CHR|CSR|BWR|MA|SR|RRR|RR|AR|ACE)\b', re.I)


def normalize(s):
    return (s or "").lower().replace(" ", "")


card_name_norms = [normalize(m["name"]) for m in card_meta]
card_tokens = [[t for t in TOKEN_RE.findall(m["name"] or "") if t not in STOP_WORDS] for m in card_meta]
card_rarities = [(m["rarity"] or "").upper() for m in card_meta]


def name_score(title, idx):
    title_n = normalize(title)
    cn_n = card_name_norms[idx]
    if not cn_n: return 0.0
    if len(cn_n) >= 2 and cn_n in title_n:
        return 1.0
    cn_toks = card_tokens[idx]
    if not cn_toks: return 0.0
    matched = sum(1 for t in cn_toks if normalize(t) in title_n)
    return matched / len(cn_toks)


# ── Continuous loop ──
print("Daemon started. Looping...", flush=True)
log = LOG.open("w")
iteration = 0
while True:
    iteration += 1
    try:
        conn = psycopg2.connect(**DB)
        cur = conn.cursor()
        cur.execute("""
            SELECT id, raw_title, image_path FROM price_review_queue
            WHERE source='DAANGN' AND status='pending'
              AND (auto_candidates IS NULL OR auto_candidates = '[]'::jsonb)
        """)
        items = cur.fetchall()
        if not items:
            conn.close()
            time.sleep(5)
            continue
        print(f"[iter {iteration}] processing {len(items)} items", flush=True)
        t0 = time.time()
        ok = 0
        for rid, title, image_path in items:
            if not image_path:
                continue
            img_data = dl(image_path) if image_path.startswith("http") else (DATA.parent / image_path).read_bytes()
            if not img_data:
                continue
            raw_emb = emb_bytes(img_data)
            if raw_emb is None:
                continue
            img_sims = ko_matrix @ raw_emb
            ns = np.array([name_score(title, j) for j in range(len(card_meta))], dtype=np.float32)
            title_rar = set(t.upper() for t in RARITY_RE.findall(title or ""))
            rs = np.array([1.0 if r in title_rar else 0.0 for r in card_rarities], dtype=np.float32)
            combined = img_sims * 0.35 + ns * 0.45 + rs * 0.2
            top_idx = np.argsort(-combined)[:10]
            candidates = []
            for ti in top_idx:
                m = card_meta[int(ti)]
                candidates.append({
                    "card_id": m["card_id"], "name": m["name"],
                    "rarity": m["rarity"], "collection_number": m["collection_number"],
                    "similarity": float(round(img_sims[int(ti)], 4)),
                    "name_score": float(round(ns[int(ti)], 3)),
                })
            cur.execute("UPDATE price_review_queue SET auto_candidates=%s::jsonb WHERE id=%s",
                        (json.dumps(candidates, ensure_ascii=False), rid))
            ok += 1
            if ok % 20 == 0:
                conn.commit()
        conn.commit()
        conn.close()
        el = time.time() - t0
        log.write(f"iter {iteration}: {ok} processed in {el:.0f}s\n"); log.flush()
        print(f"  done {ok} in {el:.0f}s", flush=True)
        time.sleep(5)
    except KeyboardInterrupt:
        break
    except Exception as e:
        print(f"[iter {iteration}] error: {e}", flush=True)
        log.write(f"iter {iteration}: error {e}\n")
        time.sleep(15)
