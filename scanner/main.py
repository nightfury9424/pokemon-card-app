"""
스캐너 v2 FastAPI 서버 (port 8082)
DINOv2 + FAISS 기반 카드 인식
"""
import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

import json
import re
import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import faiss
import torch
torch.set_num_threads(1)
import cv2
from pathlib import Path
from PIL import Image
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from transformers import AutoImageProcessor, AutoModel
from app.detector import CardDetector

DB_DIR     = Path(__file__).parent / "db"
FAISS_PATH = DB_DIR / "card_db.faiss"
META_PATH  = DB_DIR / "card_meta.json"
BASE_DIR   = Path(__file__).parent
_FINETUNED = BASE_DIR / "model" / "dinov2_finetuned"
BASE_MODEL = "facebook/dinov2-base"
MODEL_NAME = str(_FINETUNED) if _FINETUNED.exists() else BASE_MODEL
DEVICE     = "mps" if torch.backends.mps.is_available() else "cpu"

state: dict = {}
_executor = ThreadPoolExecutor(max_workers=1)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"DINOv2 로딩: {MODEL_NAME} ({DEVICE})...")
    state["processor"] = AutoImageProcessor.from_pretrained(BASE_MODEL)
    state["model"]     = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)
    state["model"].eval()

    print("FAISS 인덱스 로딩...")
    state["index"] = faiss.read_index(str(FAISS_PATH))
    with open(META_PATH, encoding="utf-8") as f:
        meta = json.load(f)
    state["vectors"] = meta["vectors"]  # list[card_id], 벡터 순서대로
    state["cards"]   = meta["cards"]    # card_id → {name, rarity, officialCode}

    print("OCR 리더 로딩...")
    try:
        import easyocr
        state["ocr_reader"] = easyocr.Reader(["en"], gpu=False, verbose=False)
        print("OCR 준비 완료")
    except Exception as e:
        state["ocr_reader"] = None
        print(f"OCR 비활성 (EasyOCR 없음: {e})")

    print(f"준비 완료 — 벡터 {state['index'].ntotal}개, 카드 {len(state['cards'])}종")
    yield
    _executor.shutdown(wait=False)


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DATA_DIR = Path(__file__).parent / "data"
app.mount("/data", StaticFiles(directory=str(DATA_DIR)), name="data")

MAX_SIZE = 640
_detector = CardDetector()


def resize_if_needed(img_bgr: np.ndarray) -> np.ndarray:
    h, w = img_bgr.shape[:2]
    if max(h, w) <= MAX_SIZE:
        return img_bgr
    scale = MAX_SIZE / max(h, w)
    return cv2.resize(img_bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def detect_card(img_bgr: np.ndarray) -> np.ndarray:
    warped, _ = _detector.find_and_warp_card(img_bgr)
    return warped if warped is not None else img_bgr


def _detect_lenient(img: np.ndarray):
    """슬리브/토퍼로더 대응 — 면적·비율 임계값을 낮춰서 재시도"""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    h, w = img.shape[:2]
    frame_area = h * w

    for thresh_pair in [(30, 90), (20, 60), (10, 40)]:
        edged = cv2.Canny(blur, thresh_pair[0], thresh_pair[1])
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
        closed = cv2.morphologyEx(edged, cv2.MORPH_CLOSE, kernel)
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            continue
        c = max(contours, key=cv2.contourArea)
        if cv2.contourArea(c) < frame_area * 0.08:  # 8%
            continue
        rect = cv2.minAreaRect(c)
        _, (rw2, rh2), _ = rect
        if rw2 == 0 or rh2 == 0:
            continue
        ratio = max(rw2, rh2) / min(rw2, rh2)
        if 1.15 <= ratio <= 1.65:
            box = cv2.boxPoints(rect)
            return np.int32(box)
    return None


def _process_image_scan(data: bytes) -> tuple[np.ndarray, np.ndarray] | tuple[None, None]:
    """실시간 스캔용 — (embedding, warped_bgr) 반환.
    카드 감지 실패 시 전체 이미지로 폴백 (슬리브·토퍼로더 대응)."""
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("이미지 디코딩 실패")
    img = resize_if_needed(img)
    warped, _ = _detector.find_and_warp_card(img)
    if warped is None:
        warped = img  # 폴백: 전체 이미지로 임베딩
    return get_embedding(warped), warped


def ocr_card_number(warped_bgr: np.ndarray) -> str | None:
    """카드 하단 OCR → 카드번호(NNN) 추출"""
    reader = state.get("ocr_reader")
    if reader is None:
        return None
    try:
        h, w = warped_bgr.shape[:2]
        bottom = warped_bgr[int(h * 0.87):, :]
        bottom_up = cv2.resize(bottom, (w * 2, bottom.shape[0] * 2))
        results = reader.readtext(bottom_up, detail=0, allowlist="0123456789/")
        text = " ".join(results)
        m = re.search(r'(\d{3})\s*/\s*\d{3}', text)
        return m.group(1) if m else None
    except Exception:
        return None


def ocr_rerank(candidates: list[tuple[str, float]], card_num: str | None) -> list[tuple[str, float]]:
    """OCR 카드번호로 후보 재점수화 (±15% 범위 내 보정)"""
    if not card_num:
        return candidates
    reranked = []
    for card_id, score in candidates:
        official = state["cards"].get(card_id, {}).get("officialCode", "")
        bonus = 0.0
        if official and len(official) >= 3:
            if official[-3:].lstrip("0") == card_num.lstrip("0"):
                bonus = 0.12
            elif card_num in official:
                bonus = 0.04
        reranked.append((card_id, min(score + bonus, 1.0)))
    return sorted(reranked, key=lambda x: x[1], reverse=True)


def get_embedding(img_bgr: np.ndarray) -> np.ndarray:
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    inputs  = state["processor"](images=pil_img, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = state["model"](**inputs)
    cls        = out.last_hidden_state[:, 0, :]
    patch_mean = out.last_hidden_state[:, 1:, :].mean(dim=1)
    emb = torch.cat([cls, patch_mean], dim=-1).cpu().numpy()[0]
    emb = emb / (np.linalg.norm(emb) + 1e-8)
    return emb.astype(np.float32)


def _process_image(data: bytes):
    """모든 CPU 집약 작업을 단일 스레드에서 실행 (OpenMP 충돌 방지)"""
    arr  = np.frombuffer(data, np.uint8)
    img  = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("이미지 디코딩 실패")
    img      = resize_if_needed(img)
    card_roi = detect_card(img)
    return get_embedding(card_roi)


@app.post("/identify")
async def identify(image: UploadFile = File(...)):
    try:
        data = await image.read()
        loop = asyncio.get_event_loop()
        emb, warped = await loop.run_in_executor(_executor, _process_image_scan, data)
    except Exception as e:
        import traceback; traceback.print_exc()
        return {"status": "error", "message": str(e)}

    if emb is None:
        return {"status": "no_card", "data": None}

    # Top-20 검색 후 card_id별 최고 점수 집계
    scores, indices = state["index"].search(emb.reshape(1, -1), 20)
    best: dict[str, float] = {}
    for score, idx in zip(scores[0], indices[0]):
        if idx < 0:
            continue
        card_id = state["vectors"][idx]
        if card_id not in best or score > best[card_id]:
            best[card_id] = float(score)

    candidates = sorted(best.items(), key=lambda x: x[1], reverse=True)[:10]

    # OCR reranking
    card_num = ocr_card_number(warped) if warped is not None else None
    candidates = ocr_rerank(candidates, card_num)

    results = []
    for card_id, score in candidates[:5]:
        info = state["cards"].get(card_id, {})
        results.append({
            "cardId":       card_id,
            "name":         info.get("name", ""),
            "rarityCode":   info.get("rarity", ""),
            "officialCode": info.get("officialCode", ""),
            "scrydexRef":   info.get("scrydexRef", ""),
            "score":        round(score, 4),
        })

    if not results:
        return {"status": "not_found", "data": None}

    top = results[0]
    top1_score = top["score"]
    top2_score = results[1]["score"] if len(results) > 1 else 0.0
    gap = top1_score - top2_score

    if top1_score >= 0.75 and gap >= 0.04:
        status = "success"
    elif top1_score >= 0.62:
        status = "low_confidence"
    else:
        status = "not_found"

    return {
        "status": status,
        "data": {
            "topResult":  top,
            "candidates": results,
            "ocrNumber":  card_num,
        },
    }


@app.get("/identify_path")
async def identify_path(path: str = Query(...)):
    """로컬 파일 경로로 카드 식별 (label.html용)"""
    file_path = DATA_DIR / path
    if not file_path.exists():
        return {"status": "error", "message": f"파일 없음: {path}"}
    try:
        data = file_path.read_bytes()
        loop = asyncio.get_event_loop()
        emb  = await loop.run_in_executor(_executor, _process_image, data)
    except Exception as e:
        return {"status": "error", "message": str(e)}

    scores, indices = state["index"].search(emb.reshape(1, -1), 10)
    best: dict[str, float] = {}
    for score, idx in zip(scores[0], indices[0]):
        if idx < 0:
            continue
        card_id = state["vectors"][idx]
        if card_id not in best or score > best[card_id]:
            best[card_id] = float(score)

    candidates = sorted(best.items(), key=lambda x: x[1], reverse=True)[:5]
    results = []
    for card_id, score in candidates:
        info = state["cards"].get(card_id, {})
        results.append({
            "cardId":       card_id,
            "name":         info.get("name", ""),
            "rarityCode":   info.get("rarity", ""),
            "officialCode": info.get("officialCode", ""),
            "scrydexRef":   info.get("scrydexRef", ""),
            "score":        round(score, 4),
        })

    if not results:
        return {"status": "not_found", "data": None}

    top = results[0]
    status = "success" if top["score"] >= 0.75 else "low_confidence" if top["score"] >= 0.62 else "not_found"
    return {"status": status, "data": {"topResult": top, "candidates": results}}


@app.get("/health")
async def health():
    idx = state.get("index")
    return {"status": "ok", "vectors": idx.ntotal if idx else 0}


import re as _re
import urllib.request as _urlreq
import urllib.parse as _urlparse
import psycopg2 as _psycopg2
from concurrent.futures import ThreadPoolExecutor as _TPool

_DB_CFG = dict(host="localhost", port=5432, dbname="pokemon_card_db", user="nightfury")
_SCRYDEX_HEADERS = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
_dl_executor = _TPool(max_workers=8)  # 썸네일 병렬 다운로드용

@app.get("/scrydex/search")
async def scrydex_search(q: str = Query(...), page: int = Query(1), all: bool = Query(False)):
    """scrydex 검색 결과에서 카드 ref + 썸네일 추출.
    all=true면 전체 페이지 합쳐서 반환 (최대 20페이지 = 400건).
    """
    loop = asyncio.get_event_loop()

    if not all:
        # 단일 페이지 (기존 동작)
        try:
            results, total = await loop.run_in_executor(_dl_executor, _fetch_scrydex_page, q, page)
        except Exception as e:
            return {"error": str(e), "results": []}
        return {"query": q, "page": page, "total": total, "results": results}

    # 전체 페이지 병렬 fetch (run_in_executor) → 합쳐서 반환
    try:
        page1, total = await loop.run_in_executor(_dl_executor, _fetch_scrydex_page, q, 1)
    except Exception as e:
        return {"error": str(e), "results": []}

    total_pages = min(((total or 20) + 19) // 20, 20)
    all_results = list(page1)
    seen = {r["ref"] for r in page1}

    if total_pages > 1:
        async def _fetch(pg: int):
            try:
                return await loop.run_in_executor(_dl_executor, _fetch_scrydex_page, q, pg)
            except Exception:
                return ([], None)
        pages = await asyncio.gather(*(_fetch(pg) for pg in range(2, total_pages + 1)))
        for pg_results, _ in pages:
            for r in pg_results:
                if r["ref"] in seen:
                    continue
                seen.add(r["ref"])
                all_results.append(r)

    return {"query": q, "total": len(all_results), "results": all_results}


def _dl_image(url: str) -> bytes | None:
    try:
        req = _urlreq.Request(url, headers=_SCRYDEX_HEADERS)
        return _urlreq.urlopen(req, timeout=10).read()
    except Exception:
        return None


def _fetch_scrydex_page(q: str, page: int) -> list[dict]:
    """scrydex 1개 페이지 파싱 → ref 목록 반환"""
    url = f"https://scrydex.com/pokemon/search?q={_urlparse.quote(q)}&page={page}"
    req = _urlreq.Request(url, headers=_SCRYDEX_HEADERS)
    html = _urlreq.urlopen(req, timeout=15).read().decode("utf-8", errors="replace")
    pattern = r'/pokemon/cards/([^/]+)/([^?"]+)\?variant=([^"]+)'
    results = []
    seen = set()
    for m in _re.finditer(pattern, html):
        slug, ref, variant = m.group(1), m.group(2), m.group(3)
        if ref in seen:
            continue
        seen.add(ref)
        results.append({
            "ref": ref, "slug": slug, "variant": variant,
            "is_jp": "_ja-" in ref,
            "thumb": f"https://images.scrydex.com/pokemon/{ref}/medium",
            "similarity": 0.0,
        })
    # 첫 페이지에서 총 결과 수 추출
    total_m = _re.search(r'([\d,]+)\s+results?', html)
    total = int(total_m.group(1).replace(",", "")) if total_m else None
    return results, total


@app.get("/scrydex/ai_search")
async def scrydex_ai_search(q: str = Query(...), card_id: str = Query(...)):
    """scrydex 전체 결과를 DINOv2 유사도로 정렬해서 반환"""
    loop = asyncio.get_event_loop()

    # 0. 이미 다른 카드에 매핑된 ref 목록 (임베딩 건너뜀)
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        cur.execute("""
            SELECT jp_scrydex_ref FROM cards
              WHERE jp_scrydex_ref IS NOT NULL AND jp_scrydex_ref NOT LIKE 'NO_%%'
                AND card_id != %s
            UNION
            SELECT en_scrydex_ref FROM cards
              WHERE en_scrydex_ref IS NOT NULL AND en_scrydex_ref NOT LIKE 'NO_%%'
                AND card_id != %s
        """, (card_id, card_id))
        already_mapped: set[str] = {r[0] for r in cur.fetchall()}
        conn.close()
    except Exception:
        already_mapped = set()

    # 1. 1페이지 먼저 → 총 페이지 수 파악
    try:
        page1_results, total = await loop.run_in_executor(_dl_executor, _fetch_scrydex_page, q, 1)
    except Exception as e:
        return {"error": str(e), "results": []}

    total_pages = min(((total or 20) + 19) // 20, 20)  # 최대 20페이지

    # 2. KO 카드 임베딩 먼저
    ko_data = None
    for suffix in [f"{card_id}_ko.png", f"{card_id}_jp.png", f"{card_id}_en.png"]:
        p = DATA_DIR / "cards" / suffix
        if p.exists():
            ko_data = p.read_bytes()
            break
    if ko_data is None:
        try:
            conn = _psycopg2.connect(**_DB_CFG)
            cur = conn.cursor()
            cur.execute("SELECT image_url FROM cards WHERE card_id=%s", (card_id,))
            row = cur.fetchone()
            conn.close()
            if row and row[0]:
                ko_data = await loop.run_in_executor(_dl_executor, _dl_image, row[0])
        except Exception:
            pass

    if ko_data is None:
        return {"query": q, "total": total, "results": page1_results}

    try:
        ko_emb = await loop.run_in_executor(_executor, _process_image, ko_data)
        del ko_data
    except Exception:
        return {"query": q, "total": total, "results": page1_results}

    # 3. 페이지별 순차 처리: fetch → embed → 바이트 즉시 해제 (메모리 절약)
    all_results = []
    seen_refs: set[str] = set()

    async def _embed_page(page_results: list):
        for r in page_results:
            if r["ref"] in seen_refs:
                continue
            seen_refs.add(r["ref"])
            if r["ref"] in already_mapped:  # 이미 매핑됨 → 임베딩 건너뛰고 맨 뒤로
                r["similarity"] = -1.0
                all_results.append(r)
                continue
            td = await loop.run_in_executor(_dl_executor, _dl_image, r["thumb"])
            if td:
                try:
                    emb = await loop.run_in_executor(_executor, _process_image, td)
                    r["similarity"] = round(float(np.dot(ko_emb, emb)), 4)
                except Exception:
                    pass
                finally:
                    del td
            all_results.append(r)

    await _embed_page(page1_results)

    for pg in range(2, total_pages + 1):
        try:
            pg_results, _ = await loop.run_in_executor(_dl_executor, _fetch_scrydex_page, q, pg)
            await _embed_page(pg_results)
        except Exception:
            break

    all_results.sort(key=lambda x: -x["similarity"])
    return {"query": q, "total": len(all_results), "results": all_results}


@app.get("/scrydex/unmapped")
async def scrydex_unmapped(mode: str = "unmapped"):
    """jp/en scrydex ref가 NULL이거나 NO_ 처리된 고레어 KO 카드 목록
    mode=unmapped: 둘 다 NULL인 것만
    mode=skipped: NO_JP 또는 NO_EN 포함된 것
    """
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        if mode == "all":
            where = "1=1"
        elif mode == "any":
            # 한 쪽이라도 빈 칸인 카드 (NO_ 명시된 건 처리 완료라 제외).
            where = (
                "(((c.jp_scrydex_ref IS NULL OR c.jp_scrydex_ref = '') "
                "  AND COALESCE(c.en_scrydex_ref,'') NOT LIKE 'NO_%') "
                " OR ((c.en_scrydex_ref IS NULL OR c.en_scrydex_ref = '') "
                "     AND COALESCE(c.jp_scrydex_ref,'') NOT LIKE 'NO_%'))"
            )
        else:
            # 기본: JP, EN 둘 다 진짜 NULL인 것만 (NO_ 는 이미 확인된 것 → 제외)
            where = "(c.jp_scrydex_ref IS NULL AND c.en_scrydex_ref IS NULL)"
        cur.execute(f"""
            SELECT c.card_id, c.name, c.rarity_code, c.collection_number,
                   c.image_url, c.jp_scrydex_ref, c.en_scrydex_ref
            FROM cards c
            WHERE c.language = 'KO'
              AND c.rarity_code IN ('SSR','SAR','BWR','CSR','CHR','UR','SR','AR','HR','ACE','RRR','RR','PR','SM-P','MA','MUR')
              AND {where}
            ORDER BY c.rarity_code, c.name
        """)
        rows = cur.fetchall()
        conn.close()
        return {"count": len(rows), "cards": [
            {"card_id": r[0], "name": r[1], "rarity": r[2],
             "collection_number": r[3], "image_url": r[4],
             "jp_scrydex_ref": r[5], "en_scrydex_ref": r[6]}
            for r in rows
        ]}
    except Exception as e:
        return {"error": str(e)}


def _save_scrydex_image(ref: str, card_id: str, lang: str):
    """scrydex 이미지 다운로드 → cards/{card_id}_{lang}.png 저장"""
    dst = DATA_DIR / "cards" / f"{card_id}_{lang}.png"
    if dst.exists():
        return
    data = _dl_image(f"https://images.scrydex.com/pokemon/{ref}/medium")
    if data:
        arr = np.frombuffer(data, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is not None and img.shape[0] >= 100:
            cv2.imwrite(str(dst), img)


@app.post("/scrydex/save")
async def scrydex_save(payload: dict):
    """카드에 jp/en scrydex ref 저장 + 이미지 자동 다운로드"""
    card_id = payload.get("card_id")
    jp_ref  = payload.get("jp_ref")
    en_ref  = payload.get("en_ref")
    if not card_id:
        return {"error": "card_id required"}
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        if jp_ref is not None:
            cur.execute("UPDATE cards SET jp_scrydex_ref=%s, updated_at=NOW() WHERE card_id=%s", (jp_ref, card_id))
        if en_ref is not None:
            cur.execute("UPDATE cards SET en_scrydex_ref=%s, updated_at=NOW() WHERE card_id=%s", (en_ref, card_id))
        conn.commit()
        conn.close()
    except Exception as e:
        return {"error": str(e)}

    # 이미지 백그라운드 다운로드 (NO_ 스킵)
    loop = asyncio.get_event_loop()
    if jp_ref and not jp_ref.startswith("NO_"):
        loop.run_in_executor(_dl_executor, _save_scrydex_image, jp_ref, card_id, "jp")
    if en_ref and not en_ref.startswith("NO_"):
        loop.run_in_executor(_dl_executor, _save_scrydex_image, en_ref, card_id, "en")

    return {"ok": True, "card_id": card_id, "jp_ref": jp_ref, "en_ref": en_ref}


@app.get("/cards/list")
async def cards_list():
    """전체 KO 고레어 카드 목록 + 매핑 현황"""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        cur.execute("""
            SELECT card_id, name, rarity_code, collection_number,
                   image_url, jp_scrydex_ref, en_scrydex_ref
            FROM cards
            WHERE language = 'KO'
              AND rarity_code NOT IN ('C','U','R','TR','A')
            ORDER BY rarity_code, name
        """)
        rows = cur.fetchall()
        conn.close()
        cards = []
        for r in rows:
            card_id, name, rarity, col_num, image_url, jp_ref, en_ref = r
            jp_thumb = f"https://images.scrydex.com/pokemon/{jp_ref}/medium" if jp_ref and not jp_ref.startswith("NO_") else None
            en_thumb = f"https://images.scrydex.com/pokemon/{en_ref}/medium" if en_ref and not en_ref.startswith("NO_") else None
            thumb = jp_thumb or en_thumb or image_url or None
            cards.append({
                "card_id": card_id, "name": name, "rarity": rarity,
                "collection_number": col_num, "thumb": thumb,
                "jp_ref": jp_ref, "en_ref": en_ref,
            })
        return {"count": len(cards), "cards": cards}
    except Exception as e:
        return {"error": str(e)}


@app.delete("/cards/{card_id}")
async def delete_card(card_id: str):
    """카드 DB에서 삭제 — FK child(price_*) 먼저 정리."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        # FK child 먼저 삭제 (price_anomalies는 RESTRICT, 나머지는 안전상 같이)
        cur.execute("DELETE FROM price_anomalies WHERE card_id=%s", (card_id,))
        cur.execute("DELETE FROM price_snapshots WHERE card_id=%s", (card_id,))
        cur.execute("DELETE FROM card_market_prices WHERE card_id=%s", (card_id,))
        # 이제 카드 삭제
        cur.execute("DELETE FROM cards WHERE card_id=%s AND language='KO'", (card_id,))
        deleted = cur.rowcount
        conn.commit()
        conn.close()
        return {"ok": True, "deleted": deleted}
    except Exception as e:
        return {"error": str(e)}


# ─── 카드 매핑 검수용 admin endpoint ─────────────────────────────────────────

@app.get("/admin/cards/list")
async def admin_cards_list(
    lang: str = "KO",
    offset: int = 0,
    limit: int = 3,
    rarity: str = "",
):
    """전체 카드 페이징 — 매핑 검수용. rarity 빈칸이면 전체."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        where = "language=%s"
        params: list = [lang]
        if rarity:
            where += " AND rarity_code = %s"
            params.append(rarity)
        cur.execute(f"SELECT COUNT(*) FROM cards WHERE {where}", params)
        total = cur.fetchone()[0]
        cur.execute(f"""
            SELECT card_id, name, rarity_code, collection_number,
                   official_card_code, image_url,
                   jp_scrydex_ref, en_scrydex_ref
            FROM cards WHERE {where}
            ORDER BY official_card_code NULLS LAST, name
            LIMIT %s OFFSET %s
        """, params + [limit, offset])
        rows = cur.fetchall()
        conn.close()
        cards = [
            {"card_id": r[0], "name": r[1], "rarity_code": r[2],
             "collection_number": r[3], "official_card_code": r[4],
             "image_url": r[5], "jp_scrydex_ref": r[6], "en_scrydex_ref": r[7]}
            for r in rows
        ]
        return {"total": total, "offset": offset, "limit": limit, "cards": cards}
    except Exception as e:
        return {"error": str(e)}


def _redownload_ko_image(card_id: str, image_url: str) -> bool:
    """image_url에서 _ko.png 다시 받음. 성공 True."""
    dst = DATA_DIR / "cards" / f"{card_id}_ko.png"
    data = _dl_image(image_url)
    if not data:
        return False
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None or img.shape[0] < 50:
        return False
    if dst.exists():
        dst.unlink()
    cv2.imwrite(str(dst), img)
    return True


@app.post("/admin/cards/{card_id}/update")
async def admin_cards_update(card_id: str, payload: dict):
    """카드 필드 수정 — image_url 변경 시 _ko.png 자동 재다운로드."""
    fields = ("name", "rarity_code", "collection_number",
              "official_card_code", "image_url",
              "jp_scrydex_ref", "en_scrydex_ref")
    updates: list[str] = []
    params: list = []
    new_image_url = None
    for f in fields:
        if f in payload:
            val = payload[f]
            updates.append(f"{f}=%s")
            params.append(val)
            if f == "image_url":
                new_image_url = val
    if not updates:
        return {"error": "nothing to update"}
    params.append(card_id)
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        cur.execute(
            f"UPDATE cards SET {', '.join(updates)}, updated_at=NOW() WHERE card_id=%s",
            params,
        )
        conn.commit()
        conn.close()
    except Exception as e:
        return {"error": str(e)}

    # image_url 변경 시 _ko.png 즉시 재다운로드
    redownloaded = False
    if new_image_url:
        loop = asyncio.get_event_loop()
        redownloaded = await loop.run_in_executor(
            _dl_executor, _redownload_ko_image, card_id, new_image_url
        )
    return {"ok": True, "redownloaded_ko": redownloaded}


@app.get("/admin/cards/grouped")
async def admin_cards_grouped(lang: str = "KO"):
    """언어별 전체 카드 — product(셋트) 그룹화. final_check.html용."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        cur.execute("""
            SELECT c.card_id, c.name, c.rarity_code, c.collection_number,
                   c.official_card_code, c.image_url,
                   c.jp_scrydex_ref, c.en_scrydex_ref, c.mapping_status,
                   c.product_id, p.name, p.series_name, p.product_type
            FROM cards c
            LEFT JOIN products p ON p.product_id = c.product_id
            WHERE c.language = %s
            ORDER BY p.series_name NULLS LAST, p.name NULLS LAST,
                     c.official_card_code NULLS LAST, c.collection_number NULLS LAST
        """, (lang,))
        rows = cur.fetchall()
        conn.close()
        groups: dict[str, dict] = {}
        for r in rows:
            (cid, name, rarity, col_num, ocode, image_url,
             jp_ref, en_ref, mstatus,
             prod_id, prod_name, series, ptype) = r
            key = prod_id or "_unknown"
            if key not in groups:
                groups[key] = {
                    "product_id": prod_id,
                    "name": prod_name or "(셋트 정보 없음)",
                    "series_name": series or "",
                    "product_type": ptype or "",
                    "cards": [],
                }
            groups[key]["cards"].append({
                "card_id": cid, "name": name, "rarity_code": rarity,
                "collection_number": col_num, "official_card_code": ocode,
                "image_url": image_url,
                "jp_scrydex_ref": jp_ref, "en_scrydex_ref": en_ref,
                "mapping_status": mstatus,
            })
        return {
            "total": len(rows),
            "products": list(groups.values()),
        }
    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/cards/{card_id}/status")
async def admin_cards_status(card_id: str, payload: dict):
    """mapping_status 토글 — 'verified' / 'wrong' / null"""
    status = payload.get("status")
    if status not in (None, "verified", "wrong"):
        return {"error": "status must be verified/wrong/null"}
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        cur.execute(
            "UPDATE cards SET mapping_status=%s, updated_at=NOW() WHERE card_id=%s",
            (status, card_id),
        )
        conn.commit()
        conn.close()
        return {"ok": True, "card_id": card_id, "status": status}
    except Exception as e:
        return {"error": str(e)}


# ─── 시세 검수 큐 endpoints ──────────────────────────────────────────────

@app.get("/admin/review/list")
async def admin_review_list(
    status: str = "pending",
    source: str = "",
    bundle: str = "",
    graded: str = "",
    suspect: str = "",
    limit: int = 30,
    offset: int = 0,
):
    """검수 큐 목록 — auto_candidates의 card_id를 cards JOIN으로 enrich."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        where = ["status = %s"]
        params: list = [status]
        if source:
            where.append("source = %s"); params.append(source)
        if bundle == "1":
            where.append("auto_is_bundle = true")
        if bundle == "0":
            where.append("auto_is_bundle = false")
        if graded == "1":
            where.append("auto_grade_company IS NOT NULL")
        if suspect == "1":
            where.append("auto_price_suspect = true")
        where_sql = " AND ".join(where)

        cur.execute(f"SELECT COUNT(*) FROM price_review_queue WHERE {where_sql}", params)
        total = cur.fetchone()[0]

        cur.execute(f"""
            SELECT id, source, source_id, raw_title, raw_price, raw_url, image_path,
                   auto_candidates, auto_lang, auto_grade_company, auto_grade_value,
                   auto_is_bundle, auto_price_suspect, status, created_at
            FROM price_review_queue
            WHERE {where_sql}
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """, params + [limit, offset])
        rows = cur.fetchall()
        conn.close()
        items = []
        for r in rows:
            items.append({
                "id": str(r[0]), "source": r[1], "source_id": r[2],
                "raw_title": r[3], "raw_price": r[4], "raw_url": r[5],
                "image_path": r[6], "auto_candidates": r[7],
                "auto_lang": r[8], "auto_grade_company": r[9], "auto_grade_value": r[10],
                "auto_is_bundle": r[11], "auto_price_suspect": r[12],
                "status": r[13],
                "created_at": r[14].isoformat() if r[14] else None,
            })
        return {"total": total, "items": items, "offset": offset, "limit": limit}
    except Exception as e:
        return {"error": str(e)}


def _append_datachip(source, source_id, card_id, raw_title, raw_price, raw_url, image_path):
    """DAANGN 검수 verify 시 DINOv2 스캐너 학습 데이터칩으로 적재.

    - 이미지 외부 URL이면 로컬 다운로드
    - JSONL append (라인 단위 — concurrent verify 안전, append-only)
    - DAANGN 외 source는 적재 안 함 (NAVER 등 정책)
    """
    if source != 'DAANGN':
        return
    try:
        import json as _json, urllib.request as _urlreq
        from pathlib import Path as _Path
        from datetime import datetime as _dt
        BASE = _Path("/Users/fury/pokemon-card-app/scanner/training/data")
        IMG_DIR = BASE / "datachips_daangn_img"
        IMG_DIR.mkdir(parents=True, exist_ok=True)
        JSONL = BASE / "datachips_daangn.jsonl"

        img_local = None
        if image_path and image_path.startswith('http'):
            ext = 'webp' if '.webp' in image_path else 'jpg'
            local_path = IMG_DIR / f"{source_id}.{ext}"
            if not local_path.exists():
                req = _urlreq.Request(image_path, headers={'User-Agent': 'Mozilla/5.0'})
                with _urlreq.urlopen(req, timeout=15) as r:
                    local_path.write_bytes(r.read())
            img_local = str(local_path.relative_to(BASE))

        entry = {
            "image_path": img_local,
            "image_url": image_path,
            "card_id": card_id,
            "source": source,
            "source_id": source_id,
            "raw_title": raw_title,
            "raw_price": int(raw_price) if raw_price else None,
            "raw_url": raw_url,
            "labeled_at": _dt.now().isoformat(),
        }
        with open(JSONL, 'a', encoding='utf-8') as f:
            f.write(_json.dumps(entry, ensure_ascii=False) + '\n')
    except Exception as e:
        # 데이터칩 실패는 verify 자체를 막지 않게 — log만 출력
        print(f"[datachip] append failed for {source_id}: {e}", flush=True)


@app.post("/admin/review/{review_id}/verify")
async def admin_review_verify(review_id: str, payload: dict):
    """검수 통과 → price_snapshots insert + queue status='verified'"""
    card_id = payload.get("card_id")
    price = payload.get("price")
    currency = payload.get("currency") or "KRW"
    lang = payload.get("lang") or "KO"
    card_status = payload.get("card_status") or "RAW"
    grade_company = payload.get("grading_company")
    grade_value = payload.get("grade_value")
    if not card_id or not price:
        return {"error": "card_id and price required"}
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        # source/source_id/raw_url 등 큐에서 가져옴
        cur.execute("""
            SELECT source, source_id, raw_url, raw_title, image_path
            FROM price_review_queue WHERE id=%s
        """, (review_id,))
        row = cur.fetchone()
        if not row:
            conn.close()
            return {"error": "review not found"}
        source, source_id, raw_url, raw_title, _img = row

        # NAVER_CAFE: 수집 단계에서 이미 source_item_id로 적재된 PENDING row를 VALID로 UPDATE.
        # 그 외 source (DAANGN 등): 기존 동작 — 신규 INSERT.
        # 2026-05-19 보강: NAVER 중복 row 방지 (price_naver_cafe.py와 정합성).
        import uuid as _uuid
        sid = None
        if source == 'NAVER_CAFE':
            cur.execute("""
                UPDATE price_snapshots
                SET validation_status='VALID',
                    invalid_reason=NULL,
                    card_id=%s,
                    price=%s,
                    card_status=%s,
                    grading_company=%s,
                    grade_value=%s
                WHERE source='NAVER_CAFE' AND source_item_id=%s
                RETURNING price_snapshot_id
            """, (card_id, int(price), card_status, grade_company, grade_value, source_id))
            row2 = cur.fetchone()
            if row2:
                sid = row2[0]
            else:
                # 폴백 — 큐에는 있는데 snapshots에 없으면 신규 INSERT (race 또는 수동 큐 등록)
                sid = _uuid.uuid4().hex
                cur.execute("""
                    INSERT INTO price_snapshots
                      (price_snapshot_id, card_id, source, source_item_id, source_url,
                       price, raw_price, raw_currency, card_status,
                       grading_company, grade_value, traded_at, collected_at, title,
                       validation_status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), %s, 'VALID')
                """, (
                    sid, card_id, source, source_id, raw_url,
                    int(price), int(price), currency, card_status,
                    grade_company, grade_value, raw_title,
                ))
        else:
            sid = _uuid.uuid4().hex
            cur.execute("""
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, source_item_id, source_url,
                   price, raw_price, raw_currency, card_status,
                   grading_company, grade_value, traded_at, collected_at, title)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), %s)
            """, (
                sid, card_id, source, source_id, raw_url,
                int(price), int(price), currency, card_status,
                grade_company, grade_value, raw_title,
            ))
        # 큐 update
        cur.execute("""
            UPDATE price_review_queue SET
              status='verified', reviewed_at=NOW(),
              verified_card_id=%s, verified_price=%s, verified_currency=%s,
              verified_lang=%s, verified_card_status=%s,
              verified_grading_company=%s, verified_grade_value=%s
            WHERE id=%s
        """, (
            card_id, int(price), currency, lang, card_status,
            grade_company, grade_value, review_id,
        ))
        conn.commit()
        conn.close()
        # DAANGN 데이터칩 적재 — 검수 1회 = 시세 + 스캐너 학습 라벨 동시 확정
        _append_datachip(source, source_id, card_id, raw_title, int(price), raw_url, _img)
        return {"ok": True, "price_snapshot_id": sid}
    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/review/{review_id}/triage")
async def admin_review_triage(review_id: str):
    """Pass 1 triage — 단일 카드 OK 마크 (status='triage_ok')."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        cur.execute("""
            UPDATE price_review_queue SET status='triage_ok', reviewed_at=NOW()
            WHERE id=%s
        """, (review_id,))
        conn.commit()
        conn.close()
        return {"ok": True}
    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/review/{review_id}/single_auto")
async def admin_review_single_auto(review_id: str, payload: dict):
    """1차 triage 단일 — 선택된 card_id로 RAW 자동 매핑 + price_snapshots 저장.

    payload: { card_id?: 사용자가 선택. 없으면 auto_candidates[0] 자동.
              price?: 사용자 수정 가격. 없으면 raw_price }
    """
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        cur.execute("""
            SELECT source, source_id, raw_title, raw_price, raw_url,
                   image_path, traded_at, auto_candidates
            FROM price_review_queue WHERE id=%s
        """, (review_id,))
        row = cur.fetchone()
        if not row:
            conn.close()
            return {"error": "not found"}
        source, source_id, raw_title, raw_price, raw_url, image_path, traded_at, candidates = row

        # 카드 ID 결정: payload > auto_candidates[0]
        card_id = payload.get("card_id")
        if not card_id:
            if candidates and len(candidates) > 0:
                card_id = candidates[0].get("card_id")
        if not card_id:
            conn.close()
            return {"error": "no card_id available (no candidates)"}

        price = payload.get("price") or raw_price
        if not price:
            conn.close()
            return {"error": "no price"}

        # 2026-05-19 보강: NAVER_CAFE는 수집 단계에서 이미 source_item_id로 PENDING row 적재됨.
        # 기존 row UPDATE — 중복 row 방지 + price_snapshots.validation_status='VALID' 정합성.
        import uuid as _uuid
        sid = None
        if source == 'NAVER_CAFE':
            cur.execute("""
                UPDATE price_snapshots
                SET validation_status='VALID',
                    invalid_reason=NULL,
                    card_id=%s,
                    price=%s,
                    raw_price=%s,
                    card_status='RAW',
                    grading_company=NULL,
                    grade_value=NULL
                WHERE source='NAVER_CAFE' AND source_item_id=%s
                RETURNING price_snapshot_id
            """, (card_id, int(price), int(price), source_id))
            r2 = cur.fetchone()
            if r2:
                sid = r2[0]
            else:
                # 폴백 — 큐에는 있는데 snapshots에 없으면 신규 INSERT (race 케이스)
                sid = _uuid.uuid4().hex
                cur.execute("""
                    INSERT INTO price_snapshots
                      (price_snapshot_id, card_id, source, source_item_id, source_url,
                       price, raw_price, raw_currency, card_status,
                       grading_company, grade_value, traded_at, collected_at, title,
                       validation_status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, 'KRW', 'RAW',
                            NULL, NULL, %s, NOW(), %s, 'VALID')
                """, (sid, card_id, source, source_id, raw_url,
                      int(price), int(price), traded_at or _psycopg2.extensions.AsIs("NOW()"), raw_title))
        else:
            sid = _uuid.uuid4().hex
            cur.execute("""
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, source_item_id, source_url,
                   price, raw_price, raw_currency, card_status,
                   grading_company, grade_value, traded_at, collected_at, title)
                VALUES (%s, %s, %s, %s, %s, %s, %s, 'KRW', 'RAW',
                        NULL, NULL, %s, NOW(), %s)
            """, (sid, card_id, source, source_id, raw_url,
                  int(price), int(price), traded_at or _psycopg2.extensions.AsIs("NOW()"), raw_title))

        # 큐 verified
        cur.execute("""
            UPDATE price_review_queue SET
              status='verified', reviewed_at=NOW(),
              verified_card_id=%s, verified_price=%s,
              verified_currency='KRW', verified_lang='KO',
              verified_card_status='RAW'
            WHERE id=%s
        """, (card_id, int(price), review_id))
        conn.commit()
        conn.close()
        # DAANGN 데이터칩 적재 — 검수 1회 = 시세 + 스캐너 학습 라벨 동시 확정
        _append_datachip(source, source_id, card_id, raw_title, int(price), raw_url, image_path)
        return {"ok": True, "card_id": card_id, "price": int(price), "snapshot_id": sid}
    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/review/{review_id}/reject")
async def admin_review_reject(review_id: str, payload: dict):
    """검수 reject (묶음/굿즈/오인식 등).

    2026-05-19 보강 — NAVER_CAFE는 price_snapshots PENDING row도 INVALID로 같이 UPDATE.
    그래야 substrate(VALID only)에서 자동 제외되어 정합성 유지.
    """
    reason = payload.get("reason") or "unclear"
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        # source/source_id 조회 — NAVER_CAFE는 price_snapshots도 INVALID 처리
        cur.execute("SELECT source, source_id FROM price_review_queue WHERE id=%s", (review_id,))
        row = cur.fetchone()
        if row:
            src, sid = row
            if src == 'NAVER_CAFE':
                cur.execute("""
                    UPDATE price_snapshots
                    SET validation_status='INVALID',
                        invalid_reason=%s
                    WHERE source='NAVER_CAFE' AND source_item_id=%s
                """, (f'user-rejected:{reason}', sid))
        cur.execute("""
            UPDATE price_review_queue SET
              status='rejected', reviewed_at=NOW(), rejection_reason=%s
            WHERE id=%s
        """, (reason, review_id))
        conn.commit()
        conn.close()
        return {"ok": True}
    except Exception as e:
        return {"error": str(e)}


@app.get("/admin/cards/search")
async def admin_cards_search(q: str = "", lang: str = "KO", limit: int = 12):
    """검수 시 수동 카드 검색 (이름 부분 매칭)."""
    if not q:
        return {"results": []}
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        cur.execute("""
            SELECT card_id, name, rarity_code, collection_number, official_card_code
            FROM cards
            WHERE language=%s AND name ILIKE %s
            ORDER BY name LIMIT %s
        """, (lang, f"%{q}%", limit))
        rows = cur.fetchall()
        conn.close()
        return {"results": [
            {"card_id": r[0], "name": r[1], "rarity": r[2],
             "collection_number": r[3], "official_card_code": r[4]}
            for r in rows
        ]}
    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/cards/{card_id}/fill_from_url")
async def admin_fill_from_url(card_id: str, payload: dict):
    """pokemoncard.co.kr 카드 detail URL 받아서 official_card_code + image_url + _ko.png 일괄 채움."""
    url = (payload.get("url") or "").strip()
    if not url:
        return {"error": "url required"}
    m = _re.search(r"/cards/detail/([A-Za-z0-9_-]+)", url)
    if not m:
        return {"error": "official_card_code를 URL에서 찾을 수 없음"}
    code = m.group(1)

    # page fetch
    try:
        req = _urlreq.Request(url, headers={
            "User-Agent": "Mozilla/5.0 PokeFolio"
        })
        with _urlreq.urlopen(req, timeout=20) as r:
            html = r.read().decode("utf-8", errors="replace")
    except Exception as e:
        return {"error": f"page fetch fail: {e}"}

    # feature_image src 추출
    img_m = _re.search(
        r'<img[^>]*class="feature_image"[^>]*src="([^"]+)"', html, _re.I
    ) or _re.search(
        r'<img[^>]*src="([^"]+)"[^>]*class="feature_image"', html, _re.I
    )
    if not img_m:
        return {"error": "feature_image 태그 없음"}
    image_url = img_m.group(1)
    if image_url.startswith("//"):
        image_url = "https:" + image_url

    # DB update
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur = conn.cursor()
        cur.execute(
            "UPDATE cards SET official_card_code=%s, image_url=%s, updated_at=NOW() WHERE card_id=%s",
            (code, image_url, card_id),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        return {"error": f"DB update fail: {e}"}

    # _ko.png 다운로드
    loop = asyncio.get_event_loop()
    ok = await loop.run_in_executor(_dl_executor, _redownload_ko_image, card_id, image_url)

    return {"ok": True, "official_card_code": code, "image_url": image_url, "redownloaded_ko": ok}


@app.post("/admin/cards/{card_id}/redownload_ko")
async def admin_cards_redownload(card_id: str):
    """image_url 그대로 두고 _ko.png만 재다운로드."""
    try:
        conn = _psycopg2.connect(**_DB_CFG)
        cur  = conn.cursor()
        cur.execute("SELECT image_url FROM cards WHERE card_id=%s", (card_id,))
        row = cur.fetchone()
        conn.close()
    except Exception as e:
        return {"error": str(e)}
    if not row or not row[0]:
        return {"error": "image_url empty"}
    loop = asyncio.get_event_loop()
    ok = await loop.run_in_executor(_dl_executor, _redownload_ko_image, card_id, row[0])
    return {"ok": ok}
