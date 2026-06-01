import os
import re

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.responses import FileResponse
from models import AnalysisResult
from analyzer import GradingAnalyzer, DEBUG_ROOT
import numpy as np
import cv2

app = FastAPI()
analyzer = GradingAnalyzer()

# P0-C: evidence layer = 사용자 친화 라벨로 backend image file 매핑.
# 기술명 (CLAHE / HSV / mask) 은 frontend 노출 X — 라벨만.
_EVIDENCE_LAYER_MAP = {
    "front_original":   "warped_front.jpg",          # 원본 보기
    "back_original":    "warped_back.jpg",
    "front_surface":    "surface_clahe_front.jpg",   # 표면 후보 강조 보기
    "back_surface":     "surface_clahe_back.jpg",
    "front_whitening":  "whitening_mask_front.jpg",  # 백화 후보 강조 보기
    "back_whitening":   "whitening_mask_back.jpg",
}
_SAFE_SESSION_RE = re.compile(r"^[A-Za-z0-9_-]+$")


@app.post("/analyze", response_model=AnalysisResult)
async def analyze(
    front_image: UploadFile = File(...),
    back_image: UploadFile = File(...),
    frame_x: float | None = Form(None),
    frame_y: float | None = Form(None),
    frame_w: float | None = Form(None),
    frame_h: float | None = Form(None),
    debug: bool = Form(False),
):
    async def read_image(upload: UploadFile):
        data = await upload.read()
        arr = np.frombuffer(data, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            raise HTTPException(status_code=400, detail=f"Invalid image: {upload.filename}")
        return img

    front_img = await read_image(front_image)
    back_img = await read_image(back_image)

    frame_hint = None
    if all(v is not None for v in (frame_x, frame_y, frame_w, frame_h)):
        frame_hint = (
            max(0.0, min(1.0, frame_x)),
            max(0.0, min(1.0, frame_y)),
            max(0.0, min(1.0, frame_w)),
            max(0.0, min(1.0, frame_h)),
        )

    return analyzer.analyze(front_img, back_img, frame_hint=frame_hint, debug=debug)


@app.post("/precheck")
async def precheck(
    image: UploadFile = File(...),
    side: str = Form("front"),
    frame_x: float | None = Form(None),
    frame_y: float | None = Form(None),
    frame_w: float | None = Form(None),
    frame_h: float | None = Form(None),
):
    data = await image.read()
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail=f"Invalid image: {image.filename}")

    frame_hint = None
    if all(v is not None for v in (frame_x, frame_y, frame_w, frame_h)):
        frame_hint = (
            max(0.0, min(1.0, frame_x)),
            max(0.0, min(1.0, frame_y)),
            max(0.0, min(1.0, frame_w)),
            max(0.0, min(1.0, frame_h)),
        )

    side_norm = side if side in ("front", "back") else "front"
    return analyzer.precheck(img, side=side_norm, frame_hint=frame_hint)


@app.get("/evidence/{session_id}/{layer}")
def evidence(session_id: str, layer: str):
    """P0-C: surface/whitening evidence 시각화 이미지 lazy fetch.
    Flutter 결과 상세 sheet 의 토글 view 가 호출.
    layer = front_original/back_original/front_surface/back_surface/front_whitening/back_whitening
    """
    if not _SAFE_SESSION_RE.match(session_id):
        raise HTTPException(status_code=400, detail="invalid session_id")
    filename = _EVIDENCE_LAYER_MAP.get(layer)
    if filename is None:
        raise HTTPException(status_code=400, detail=f"unknown layer: {layer}")
    path = os.path.join(DEBUG_ROOT, session_id, filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="evidence not found or expired")
    return FileResponse(path, media_type="image/jpeg")


@app.get("/health")
def health():
    return {"status": "ok"}
