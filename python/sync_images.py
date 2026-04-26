"""
카드 이미지 다운로드 + DINOv2 특징 벡터 추출 → pgvector 저장

설치:
    pip install torch torchvision requests psycopg2-binary Pillow

실행:
    python sync_images.py
"""

import io
import psycopg2
import psycopg2.extras
import requests
import torch
import torchvision.transforms as T
from pathlib import Path
from PIL import Image

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "pokemon_card_db",
    "user": "nightfury",
    "password": "",
}

IMAGE_DIR = Path(__file__).parent.parent / "scanner" / "data" / "cards"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    )
}

# DINOv2 ViT-B/14 — 768차원, 이미지 retrieval 특화
# 최초 실행 시 모델 자동 다운로드 (~330MB)
print("DINOv2 모델 로드 중... (최초 1회 다운로드)")
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = torch.hub.load("facebookresearch/dinov2", "dinov2_vitb14")
model.eval()
model.to(device)
print(f"DINOv2 로드 완료 (device: {device})")

# DINOv2 권장 전처리
transform = T.Compose([
    T.Resize(256, interpolation=T.InterpolationMode.BICUBIC),
    T.CenterCrop(224),
    T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


def download_image(url: str, save_path: Path) -> bool:
    try:
        resp = requests.get(url, timeout=10, headers=HEADERS)
        if resp.status_code == 200 and len(resp.content) > 1000:
            save_path.write_bytes(resp.content)
            return True
        print(f"    [SKIP] status={resp.status_code}")
    except Exception as e:
        print(f"    [DOWNLOAD ERROR] {e}")
    return False


def extract_dinov2_vector(image_path: Path) -> list[float] | None:
    """
    DINOv2로 이미지 특징 벡터(768-dim) 추출.
    홀로그램/반사에 강한 semantic embedding 반환.
    """
    try:
        img = Image.open(image_path).convert("RGB")
        tensor = transform(img).unsqueeze(0).to(device)
        with torch.no_grad():
            vec = model(tensor).squeeze(0).cpu().numpy()
        return vec.tolist()
    except Exception as e:
        print(f"    [DINO ERROR] {e}")
        return None


def vec_to_pgvector_str(vec: list[float]) -> str:
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


def sync_images():
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)

    conn = psycopg2.connect(**DB_CONFIG)

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT card_id, image_url
            FROM cards
            WHERE image_url IS NOT NULL AND image_url != ''
              AND (local_image_path IS NULL OR image_feature_vector IS NULL)
            ORDER BY card_id
        """)
        cards = cur.fetchall()

    total = len(cards)
    print(f"\n처리 대상: {total}장")

    if total == 0:
        print("모든 카드가 이미 처리되어 있습니다.")
        conn.close()
        return

    success = 0
    failed = 0

    for i, card in enumerate(cards, 1):
        card_id = card['card_id']
        image_url = card['image_url']
        save_path = IMAGE_DIR / f"{card_id}.jpg"

        print(f"[{i}/{total}] {card_id}", end=" ... ")

        # 1. 이미지 다운로드
        if not save_path.exists():
            if not download_image(image_url, save_path):
                print("다운로드 실패")
                failed += 1
                continue

        # 2. DINOv2 벡터 추출
        vec = extract_dinov2_vector(save_path)
        if vec is None:
            print("벡터 추출 실패")
            failed += 1
            continue

        # 3. DB 저장
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE cards
                    SET local_image_path = %s,
                        image_feature_vector = %s::vector,
                        updated_at = NOW()
                    WHERE card_id = %s
                """, (str(save_path), vec_to_pgvector_str(vec), card_id))
            conn.commit()
            success += 1
            print("완료")
        except Exception as e:
            conn.rollback()
            print(f"DB 저장 실패: {e}")
            failed += 1

        if i % 500 == 0:
            print(f"\n--- {i}/{total} | 성공: {success}, 실패: {failed} ---\n")

    print(f"\n완료 | 총: {total}, 성공: {success}, 실패: {failed}")
    conn.close()


if __name__ == "__main__":
    sync_images()
