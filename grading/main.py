from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from models import AnalysisResult
from analyzer import GradingAnalyzer
import numpy as np
import cv2

app = FastAPI()
analyzer = GradingAnalyzer()


@app.post("/analyze", response_model=AnalysisResult)
async def analyze(
    front_image: UploadFile = File(...),
    back_image: UploadFile = File(...),
    frame_x: float | None = Form(None),
    frame_y: float | None = Form(None),
    frame_w: float | None = Form(None),
    frame_h: float | None = Form(None),
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

    return analyzer.analyze(front_img, back_img, frame_hint=frame_hint)


@app.get("/health")
def health():
    return {"status": "ok"}
