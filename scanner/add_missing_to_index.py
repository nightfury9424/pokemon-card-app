#!/usr/bin/env python3
"""
add_missing_to_index.py — 5/6 이후 인덱스 누락 visible 카드(63장)를 기존 FAISS 인덱스에 증분 추가.
- 서버 현재 인덱스 = 맥 로컬과 동일(5/6) 확인됨 → 맥에서 add 후 prod로 swap.
- get_embedding = main.py/train_agent 와 동일 (CLS+patch_mean concat 1536, L2 정규화).
- 카탈로그 이미지(scrydex CDN medium)를 그대로 임베딩(이미 clean 카드 → warp 불필요).
- 카드당 1벡터(기존 ~14벡터/장 대비 적지만 매칭엔 충분, robustness는 후속).
실행:
  KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/python scanner/add_missing_to_index.py
"""
import json, time, shutil
from pathlib import Path
import numpy as np, cv2, faiss, requests, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

BASE_DIR = Path(__file__).parent
DB_DIR = BASE_DIR / "db"
FAISS_PATH = DB_DIR / "card_db.faiss"
META_PATH = DB_DIR / "card_meta.json"
_FINETUNED = BASE_DIR / "model" / "dinov2_finetuned"
BASE_MODEL = "facebook/dinov2-base"
MODEL_NAME = str(_FINETUNED) if _FINETUNED.exists() else BASE_MODEL
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
SCRYDEX_CDN_FMT = "https://images.scrydex.com/pokemon/{ref}/medium"
UA = "PokefolioBatchMirror/1.0"

print(f"model={MODEL_NAME} device={DEVICE}")
proc = AutoImageProcessor.from_pretrained(BASE_MODEL)
model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)
model.eval()


def embed(img_bgr):
    rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    inp = proc(images=Image.fromarray(rgb), return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = model(**inp)
    cls = out.last_hidden_state[:, 0, :]
    pm = out.last_hidden_state[:, 1:, :].mean(dim=1)
    e = torch.cat([cls, pm], dim=-1).cpu().numpy()[0]
    return (e / (np.linalg.norm(e) + 1e-8)).astype(np.float32)


def dl(ref):
    try:
        r = requests.get(SCRYDEX_CDN_FMT.format(ref=ref), headers={"User-Agent": UA}, timeout=20)
        return r.content if r.status_code == 200 else None
    except Exception as e:
        print("  dl err", ref, e)
        return None


def main():
    missing = json.load(open("/tmp/missing_cards.json"))
    print(f"대상 {len(missing)}장")
    index = faiss.read_index(str(FAISS_PATH))
    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    bn, bc = index.ntotal, len(meta["cards"])
    print(f"base: {bn} vectors / {bc} cards")
    shutil.copy(str(FAISS_PATH), str(FAISS_PATH) + ".bak_pre_add63")
    shutil.copy(str(META_PATH), str(META_PATH) + ".bak_pre_add63")
    print("backup → .bak_pre_add63")

    embs, ids, skip = [], [], []
    for i, m in enumerate(missing, 1):
        cid, ref = m["cardId"], m["ref"]
        if cid in meta["cards"]:
            continue
        d = dl(ref)
        if not d:
            skip.append((cid, ref, "dl")); continue
        img = cv2.imdecode(np.frombuffer(d, np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            skip.append((cid, ref, "decode")); continue
        try:
            e = embed(img)
        except Exception as ex:
            skip.append((cid, ref, str(ex)[:40])); continue
        embs.append(e); ids.append(cid)
        meta["cards"][cid] = {
            "name": m["name"], "rarity": m["rarity"],
            "officialCode": m["officialCode"], "scrydexRef": ref,
        }
        if i % 10 == 0:
            print(f"  {i}/{len(missing)} added={len(ids)}")
        time.sleep(0.05)

    if embs:
        index.add(np.vstack(embs).astype(np.float32))
        meta["vectors"].extend(ids)
    faiss.write_index(index, str(FAISS_PATH))
    META_PATH.write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    print(f"DONE added={len(ids)}  vectors {bn}→{index.ntotal}  cards {bc}→{len(meta['cards'])}")
    if skip:
        print("SKIPPED:", skip)


if __name__ == "__main__":
    main()
