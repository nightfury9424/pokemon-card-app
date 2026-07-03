"""
신규 카탈로그 카드 → FAISS 벡터 추가 (augment10 = 10벡터/카드).

★기존에 신규 카드용 커밋된 add 스크립트가 없어서 신규 작성(2026-07-02).
main.py 와 동일한 모델/get_embedding 으로 임베딩(일관성), realshot_experiment.augment10 재사용.

동작:
  정규화 카드이미지 1장 → augment10(원본+밝기±55/±28+회전±7/±14+4%크롭=10) → 각 DINOv2 임베딩
  → index.add(10) + meta['vectors'].extend([card_id]*10) + meta['cards'][card_id]=메타
  → index.ntotal == len(meta['vectors']) 검증

★안전장치:
  - **원본 인덱스(db/card_db.faiss) 절대 덮어쓰지 않음.** --apply 시에도 --out 스테이징에만 write.
  - 멱등: card_id 가 이미 meta['vectors'] 에 있으면 add 스킵.
  - 기본 DRY-RUN: 원본을 메모리에 읽어 +10 시뮬레이션 후 ntotal/meta 검증만 출력, 파일 write 0.
  - prod 반영은 이 스크립트가 안 함 → 스테이징 산출물을 S3 업로드 + admin '업데이트하기' 무중단 스왑.

    conda activate scanner_v2
    python add_catalog_card_vector.py --card-id CRD_xxx --image /path/normalized.webp \
        --name "후쿠오카의 피카츄" --rarity PR --official SVP000000289          # dry-run
    python add_catalog_card_vector.py ... --apply --out db/staging_local/CRD_xxx  # 스테이징 write
"""

import os
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import sys
import json
import shutil
import argparse
from pathlib import Path

import numpy as np
import cv2
import torch
import faiss
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

BASE_DIR = Path(__file__).parent
DB_DIR = BASE_DIR / "db"
BASE_MODEL = "facebook/dinov2-base"
_FINETUNED = BASE_DIR / "model" / "dinov2_finetuned"
MODEL_NAME = str(_FINETUNED) if _FINETUNED.exists() else BASE_MODEL
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"

_proc = None
_model = None


def _load_model():
    global _proc, _model
    print(f"DINOv2 로딩: {MODEL_NAME} ({DEVICE})...", flush=True)
    _proc = AutoImageProcessor.from_pretrained(BASE_MODEL)
    _model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)
    _model.eval()


def get_embedding(img_bgr):
    """main.py get_embedding 과 동일: cls + patch_mean concat, L2 정규화."""
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    pil = Image.fromarray(img_rgb)
    inputs = _proc(images=pil, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = _model(**inputs)
    cls = out.last_hidden_state[:, 0, :]
    patch_mean = out.last_hidden_state[:, 1:, :].mean(dim=1)
    emb = torch.cat([cls, patch_mean], dim=-1).cpu().numpy()[0]
    return (emb / (np.linalg.norm(emb) + 1e-8)).astype(np.float32)


def augment10(bgr):
    """realshot_experiment.augment10 동일: 원본+밝기4+회전4+크롭1 = 10."""
    h, w = bgr.shape[:2]
    out = [bgr]
    for b in (55, -55, 28, -28):
        out.append(cv2.convertScaleAbs(bgr, alpha=1.0, beta=b))
    for d in (7, -7, 14, -14):
        M = cv2.getRotationMatrix2D((w / 2, h / 2), d, 1.0)
        out.append(cv2.warpAffine(bgr, M, (w, h), borderMode=cv2.BORDER_REPLICATE))
    m = int(min(h, w) * 0.04)
    out.append(cv2.resize(bgr[m:h - m, m:w - m], (w, h)))
    return out


def load_bgr_on_white(path):
    """RGBA(투명배경) → 흰 배경 합성 후 BGR (참조카드 톤 일치)."""
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    comp = Image.alpha_composite(bg, im).convert("RGB")
    return cv2.cvtColor(np.array(comp), cv2.COLOR_RGB2BGR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--card-id", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--name", default="")
    ap.add_argument("--rarity", default="")
    ap.add_argument("--official", default="")
    ap.add_argument("--scrydex-ref", default=None)
    ap.add_argument("--src-index", default=str(DB_DIR / "card_db.faiss"))
    ap.add_argument("--src-meta", default=str(DB_DIR / "card_meta.json"))
    ap.add_argument("--apply", action="store_true", help="스테이징 write (원본은 절대 안 건드림)")
    ap.add_argument("--out", default=None, help="스테이징 출력 디렉토리 (--apply 시)")
    args = ap.parse_args()

    src_faiss = Path(args.src_index)
    if src_faiss.resolve() == (DB_DIR / "card_db.faiss").resolve() and args.apply and args.out is None:
        print("ERROR: --apply 는 --out 스테이징 필수 (원본 인덱스 덮어쓰기 금지)"); sys.exit(1)

    index = faiss.read_index(str(src_faiss))
    meta = json.loads(Path(args.src_meta).read_text(encoding="utf-8"))
    vectors, cards = meta["vectors"], meta["cards"]
    n0 = index.ntotal
    print(f"base index: {n0} vectors / {len(cards)} cards · sync {n0==len(vectors)}")

    # 멱등
    if args.card_id in vectors:
        print(f"[SKIP] {args.card_id} 이미 인덱스에 존재 (벡터 {vectors.count(args.card_id)}개) → 중복 add 안 함")
        return

    bgr = load_bgr_on_white(args.image)
    variants = augment10(bgr)
    _load_model()
    embs = [get_embedding(v) for v in variants]
    print(f"augment10 → {len(embs)} 임베딩 (dim {embs[0].shape[0]})")

    # 메모리상 +10 (원본 파일 불변)
    index.add(np.vstack(embs).astype(np.float32))
    vectors.extend([args.card_id] * len(embs))
    cards[args.card_id] = {"name": args.name, "rarity": args.rarity,
                           "officialCode": args.official, "scrydexRef": args.scrydex_ref}
    n1 = index.ntotal
    ok = (n1 == len(vectors)) and (n1 == n0 + 10) and (vectors.count(args.card_id) == 10)
    print(f"after: {n1} vectors ({n1-n0:+d}) · meta vectors {len(vectors)} · "
          f"{args.card_id} count {vectors.count(args.card_id)} · 검증 {'OK ✅' if ok else 'FAIL ⚠️'}")
    if not ok:
        print("ERROR: 검증 실패 — write 안 함"); sys.exit(1)

    if not args.apply:
        print("=== DRY-RUN: 파일 write 0 (원본 불변). --apply --out 로 스테이징 생성 ===")
        return

    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    faiss.write_index(index, str(out / "card_db.faiss"))
    (out / "card_meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    print(f"=== 스테이징 write → {out}/ (원본 db/card_db.faiss 불변) ===")
    print("   다음: 이 스테이징을 S3 업로드 → admin '업데이트하기' 무중단 스왑")


if __name__ == "__main__":
    main()
