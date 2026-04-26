from fastapi import FastAPI, File, UploadFile
from models import AnalysisResult
from analyzer import GradingAnalyzer
import numpy as np
import cv2

app = FastAPI()
analyzer = GradingAnalyzer()

@app.post("/analyze", response_model=AnalysisResult)
async def analyze(
    front: UploadFile = File(...),
    back: UploadFile = File(...),
    corner_front_tl: UploadFile = File(...),
    corner_front_tr: UploadFile = File(...),
    corner_front_bl: UploadFile = File(...),
    corner_front_br: UploadFile = File(...),
    corner_back_tl: UploadFile = File(...),
    corner_back_tr: UploadFile = File(...),
    corner_back_bl: UploadFile = File(...),
    corner_back_br: UploadFile = File(...),
):
    async def read_image(upload: UploadFile):
        data = await upload.read()
        arr = np.frombuffer(data, np.uint8)
        return cv2.imdecode(arr, cv2.IMREAD_COLOR)

    front_img = await read_image(front)
    back_img = await read_image(back)
    corners = [
        await read_image(corner_front_tl),
        await read_image(corner_front_tr),
        await read_image(corner_front_bl),
        await read_image(corner_front_br),
        await read_image(corner_back_tl),
        await read_image(corner_back_tr),
        await read_image(corner_back_bl),
        await read_image(corner_back_br),
    ]

    return analyzer.analyze(front_img, back_img, corners)

@app.get("/health")
def health():
    return {"status": "ok"}
