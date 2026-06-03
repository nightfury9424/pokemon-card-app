"""
스캔 모델 재학습 agent — 맥북 전용 (메타몽 kream-agent 패턴).

흐름 (admin '학습하기' → REQUESTED job 생성 → 이 스크립트가 맥에서 폴링/처리):
  1. GET  /api/scanner-agent/claim   → REQUESTED job 을 TRAINING 으로 전이 + jobId 획득
  2. GET  /api/scanner-agent/samples → 미인덱스 캡처 [{captureId, cardId, s3Key}]
  3. 로컬 base 인덱스(scanner/db/card_db.faiss)에 새 캡처 벡터를 append
     (전체 재빌드 X — 카탈로그 ref 벡터는 유지하고 유저 실사진 ref 를 보강 = multi-ref)
  4. staging 인덱스를 S3 uploads/scan-index/staging/{jobId}/ 에 업로드
  5. POST /api/scanner-agent/trained → TRAINED 전이 (admin '업데이트하기' 시 prod 무중단 스왑)

비용: 서버에서 안 돌림. 임베딩(DINOv2)은 이 맥에서. 메타몽 수집과 동일 철학.

환경변수:
  POKE_API_BASE        백엔드 base url (예: https://52.78.3.120.nip.io)
  SCANNER_AGENT_TOKEN  X-Scanner-Agent-Token (백엔드 app.scanner.agent-token 과 일치)
  AWS_S3_BUCKET        캡처/스테이징 버킷 (백엔드 aws.s3.bucket 과 동일)
  AWS_REGION / AWS_*   boto3 표준 자격증명 체인
  POKE_VERIFY_SSL      "0" 이면 TLS 검증 끔 (기본 검증)

실행:
  python train_agent.py            # 1회: 대기 job 있으면 처리 후 종료
  python train_agent.py --loop 30  # 30초 간격 폴링 (Ctrl-C 종료)
"""
import os
os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import sys
import json
import time
import tempfile
import argparse
from pathlib import Path

import numpy as np
import cv2
import faiss
import torch
torch.set_num_threads(1)
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
import boto3
import requests

# ── config ──
API_BASE   = os.environ.get("POKE_API_BASE", "http://localhost:8080").rstrip("/")
AGENT_TOKEN = os.environ.get("SCANNER_AGENT_TOKEN", "")
BUCKET     = os.environ.get("AWS_S3_BUCKET", "")
VERIFY_SSL = os.environ.get("POKE_VERIFY_SSL", "1") != "0"

DB_DIR     = Path(__file__).parent / "db"
FAISS_PATH = DB_DIR / "card_db.faiss"
META_PATH  = DB_DIR / "card_meta.json"

BASE_DIR   = Path(__file__).parent
_FINETUNED = BASE_DIR / "model" / "dinov2_finetuned"
BASE_MODEL = "facebook/dinov2-base"
MODEL_NAME = str(_FINETUNED) if _FINETUNED.exists() else BASE_MODEL
DEVICE     = "mps" if torch.backends.mps.is_available() else "cpu"

HEADERS = {"X-Scanner-Agent-Token": AGENT_TOKEN}

_model = None
_processor = None


def _log(msg: str):
    print(f"[train_agent] {msg}", flush=True)


def _load_model():
    """DINOv2 — main.py 와 동일 모델/디바이스. 무거우니 1회만 로드."""
    global _model, _processor
    if _model is None:
        _log(f"loading model {MODEL_NAME} on {DEVICE} …")
        _processor = AutoImageProcessor.from_pretrained(BASE_MODEL)
        _model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)
        _model.eval()


def get_embedding(img_bgr: np.ndarray) -> np.ndarray:
    """main.py get_embedding 과 완전 동일 — CLS+patch_mean concat(1536) L2 정규화."""
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    inputs  = _processor(images=pil_img, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = _model(**inputs)
    cls        = out.last_hidden_state[:, 0, :]
    patch_mean = out.last_hidden_state[:, 1:, :].mean(dim=1)
    emb = torch.cat([cls, patch_mean], dim=-1).cpu().numpy()[0]
    emb = emb / (np.linalg.norm(emb) + 1e-8)
    return emb.astype(np.float32)


def _api_get(path: str) -> dict:
    r = requests.get(API_BASE + path, headers=HEADERS, timeout=30, verify=VERIFY_SSL)
    r.raise_for_status()
    return r.json()


def _api_post(path: str, body: dict) -> dict:
    r = requests.post(API_BASE + path, headers=HEADERS, json=body, timeout=30, verify=VERIFY_SSL)
    r.raise_for_status()
    return r.json()


def process_once(s3) -> bool:
    """대기 job 1건 처리. 처리했으면 True, 없으면 False."""
    claim = _api_get("/api/scanner-agent/claim")
    if not claim.get("claim"):
        return False
    job_id = claim["jobId"]
    _log(f"claimed job {job_id}")

    try:
        samples = _api_get("/api/scanner-agent/samples").get("samples", [])
        _log(f"{len(samples)} unindexed captures")
        if not samples:
            # 처리할 게 없어도 정상 종결 — staging 없이 trained(0) 보고하면 deploy 무의미하니 실패 처리
            _api_post("/api/scanner-agent/trained",
                      {"jobId": job_id, "stagedIndexKey": None, "sampleCount": 0,
                       "error": "no unindexed captures"})
            return True

        _load_model()
        index = faiss.read_index(str(FAISS_PATH))
        meta = json.loads(META_PATH.read_text(encoding="utf-8"))
        vectors = meta["vectors"]
        cards = meta["cards"]
        base_n = index.ntotal
        _log(f"base index: {base_n} vectors / {len(cards)} cards")

        added = 0
        skipped = 0
        for i, s in enumerate(samples, 1):
            card_id = s["cardId"]
            if card_id not in cards:
                skipped += 1
                continue  # 알 수 없는 카드 — 카탈로그 오염 방지
            try:
                obj = s3.get_object(Bucket=BUCKET, Key=s["s3Key"])
                data = obj["Body"].read()
                arr = np.frombuffer(data, np.uint8)
                img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                if img is None:
                    skipped += 1
                    continue
                # 캡처는 이미 warp-crop(identify 가 저장) → 재검출 없이 그대로 임베딩
                emb = get_embedding(img)
                index.add(emb.reshape(1, -1))
                vectors.append(card_id)
                added += 1
            except Exception as e:
                _log(f"  sample {s.get('captureId')} 실패: {e}")
                skipped += 1
            if i % 50 == 0:
                _log(f"  {i}/{len(samples)} (added={added} skipped={skipped})")

        if added == 0:
            _api_post("/api/scanner-agent/trained",
                      {"jobId": job_id, "stagedIndexKey": None, "sampleCount": 0,
                       "error": f"embedded 0 (skipped {skipped})"})
            return True
        _log(f"appended {added} vectors → total {index.ntotal} (skipped {skipped})")

        # staging 인덱스 → S3 (백엔드 deploy 가 load(stagedKey + '/card_db.faiss'))
        staged_key = f"uploads/scan-index/staging/{job_id}"
        with tempfile.TemporaryDirectory(prefix="train_agent_") as td:
            tf = Path(td) / "card_db.faiss"
            tm = Path(td) / "card_meta.json"
            faiss.write_index(index, str(tf))
            meta["vectors"] = vectors  # cards 는 변동 없음
            tm.write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
            s3.put_object(Bucket=BUCKET, Key=f"{staged_key}/card_db.faiss",
                          Body=tf.read_bytes(), ContentType="application/octet-stream")
            s3.put_object(Bucket=BUCKET, Key=f"{staged_key}/card_meta.json",
                          Body=tm.read_bytes(), ContentType="application/json")
        _log(f"uploaded staging → s3://{BUCKET}/{staged_key}/")

        _api_post("/api/scanner-agent/trained",
                  {"jobId": job_id, "stagedIndexKey": staged_key,
                   "sampleCount": added, "error": None})
        _log(f"job {job_id} TRAINED — admin '업데이트하기' 누르면 prod 무중단 스왑")
        return True

    except Exception as e:
        _log(f"job {job_id} FAILED: {e}")
        try:
            _api_post("/api/scanner-agent/trained",
                      {"jobId": job_id, "stagedIndexKey": None, "sampleCount": 0,
                       "error": str(e)[:500]})
        except Exception:
            pass
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loop", type=int, default=0, help="폴링 간격(초). 0=1회 실행")
    args = ap.parse_args()

    if not AGENT_TOKEN:
        _log("SCANNER_AGENT_TOKEN 미설정 — 종료"); sys.exit(1)
    if not BUCKET:
        _log("AWS_S3_BUCKET 미설정 — 종료"); sys.exit(1)
    if not FAISS_PATH.exists():
        _log(f"base 인덱스 없음: {FAISS_PATH} — 종료"); sys.exit(1)

    s3 = boto3.client("s3")
    _log(f"API={API_BASE} bucket={BUCKET} device={DEVICE}")

    if args.loop <= 0:
        did = process_once(s3)
        _log("done" if did else "대기 job 없음")
        return
    _log(f"폴링 모드 — {args.loop}s 간격 (Ctrl-C 종료)")
    while True:
        try:
            if not process_once(s3):
                pass
        except Exception as e:
            _log(f"poll 오류: {e}")
        time.sleep(args.loop)


if __name__ == "__main__":
    main()
