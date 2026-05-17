from fastapi import FastAPI, File, UploadFile, HTTPException
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

    return analyzer.analyze(front_img, back_img)

@app.get("/health")
def health():
    return {"status": "ok"}
