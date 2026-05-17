"""
DINOv2 파인튜닝 — Contrastive Learning (NT-Xent)
사용법:
  conda activate scanner_v2
  python finetune.py --data data/crawl_raw/crawl_results.json --epochs 10
"""
import os
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"

import json, argparse, random
from pathlib import Path
from collections import defaultdict
import psycopg2

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
import cv2
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
from tqdm import tqdm
from app.detector import CardDetector

_detector = CardDetector()

BASE_DIR   = Path(__file__).parent
MODEL_NAME = "facebook/dinov2-base"
DEVICE     = "mps" if torch.backends.mps.is_available() else "cpu"
SAVE_PATH  = BASE_DIR / "model" / "dinov2_finetuned.pt"
SAVE_PATH.parent.mkdir(exist_ok=True)


# ── 데이터셋 ─────────────────────────────────────────────────────────────────

class CardPairDataset(Dataset):
    """같은 card_id 이미지를 positive pair로, 다른 card_id를 negative로"""

    def __init__(self, data_path: str, processor, min_images: int = 2):
        raw = json.loads(Path(data_path).read_text(encoding="utf-8"))

        # DB에서 유효한 card_id 목록 (C/U/R 삭제 후 남은 카드만)
        valid_ids = self._load_valid_ids()
        print(f"DB 유효 카드: {len(valid_ids)}종")

        # card_id별 이미지 경로 그룹핑 (라벨 확정된 것만)
        groups: dict[str, list[str]] = defaultdict(list)
        root = Path(data_path).parent.parent  # scanner/data/
        for item in raw:
            label = item.get("label")
            if not label or label == "NONE":
                continue
            if valid_ids and label not in valid_ids:
                continue
            img_path = root / item["image_path"]
            if img_path.exists():
                groups[label].append(str(img_path))

        # DB reference 이미지 추가 (DB에 존재하는 카드만, C/U/R 제외)
        cards_dir = BASE_DIR / "data" / "cards"
        ref_added = 0
        for suffix in ("_ko.png", "_jp.png", "_en.png"):
            for img_file in cards_dir.glob(f"CRD_*{suffix}"):
                card_id = img_file.stem.rsplit("_", 1)[0]
                if not valid_ids or card_id in valid_ids:
                    groups[card_id].append(str(img_file))
                    ref_added += 1
        print(f"공식 이미지 추가: {ref_added}장")

        # 이미지 2장 이상인 카드만
        self.groups = {k: v for k, v in groups.items() if len(v) >= min_images}
        self.card_ids = list(self.groups.keys())
        self.processor = processor

        print(f"카드 종류: {len(self.card_ids)}종, 총 이미지: {sum(len(v) for v in self.groups.values())}장")

    @staticmethod
    def _load_valid_ids() -> set[str]:
        """DB에 남아있는 KO 카드 전체 (C/U/R은 이미 DB에서 삭제됨)"""
        try:
            conn = psycopg2.connect(host="localhost", port=5432,
                                    dbname="pokemon_card_db", user="nightfury")
            cur  = conn.cursor()
            cur.execute("SELECT card_id FROM cards WHERE language = 'KO'")
            ids  = {r[0] for r in cur.fetchall()}
            conn.close()
            return ids
        except Exception as e:
            print(f"  [DB 연결 실패] {e} — DB 필터링 없이 진행")
            return set()

    def __len__(self):
        return len(self.card_ids) * 4  # 카드당 4쌍 생성

    def __getitem__(self, idx):
        card_id = self.card_ids[idx % len(self.card_ids)]
        imgs    = self.groups[card_id]

        # 같은 카드에서 2장 (positive pair)
        a_path, b_path = random.sample(imgs, 2) if len(imgs) >= 2 else (imgs[0], imgs[0])
        img_a = self._load(a_path)
        img_b = self._load(b_path)

        return img_a, img_b, card_id

    def _load(self, path: str):
        arr = cv2.imread(path)
        if arr is None:
            arr = np.zeros((224, 224, 3), dtype=np.uint8)
        warped, _ = _detector.find_and_warp_card(arr)
        if warped is not None:
            arr = warped
        arr = cv2.cvtColor(arr, cv2.COLOR_BGR2RGB)
        pil = Image.fromarray(arr)
        # 랜덤 증강 (색상 지터 + 좌우반전)
        aug = transforms.Compose([
            transforms.RandomHorizontalFlip(),
            transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2),
            transforms.RandomRotation(10),
        ])
        pil = aug(pil)
        return self.processor(images=pil, return_tensors="pt")["pixel_values"][0]


# ── NT-Xent Loss ──────────────────────────────────────────────────────────────

def nt_xent_loss(z_a: torch.Tensor, z_b: torch.Tensor, temp: float = 0.07):
    """SimCLR NT-Xent: z_a[i]와 z_b[i]가 positive pair"""
    z_a = F.normalize(z_a, dim=1)
    z_b = F.normalize(z_b, dim=1)
    N   = z_a.size(0)

    z   = torch.cat([z_a, z_b], dim=0)          # [2N, D]
    sim = torch.mm(z, z.T) / temp               # [2N, 2N]

    # 자기 자신 제외 마스크
    mask = torch.eye(2 * N, dtype=torch.bool, device=z.device)
    sim.masked_fill_(mask, -1e9)

    # positive 인덱스: i ↔ i+N
    labels = torch.cat([torch.arange(N, 2*N), torch.arange(N)]).to(z.device)
    loss   = F.cross_entropy(sim, labels)
    return loss


# ── 파인튜닝 메인 ─────────────────────────────────────────────────────────────

def train(args):
    print(f"모델 로딩: {MODEL_NAME} ({DEVICE})")
    processor = AutoImageProcessor.from_pretrained(MODEL_NAME)
    model     = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE)

    # 마지막 2개 블록 + head만 학습 (나머지 freeze)
    for param in model.parameters():
        param.requires_grad = False
    for block in model.encoder.layer[-2:]:
        for param in block.parameters():
            param.requires_grad = True
    for param in model.layernorm.parameters():
        param.requires_grad = True

    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total     = sum(p.numel() for p in model.parameters())
    print(f"학습 파라미터: {trainable:,} / {total:,} ({trainable/total*100:.1f}%)")

    dataset = CardPairDataset(args.data, processor, min_images=2)
    if len(dataset.card_ids) < 10:
        print("카드 종류가 너무 적음. 라벨링 먼저 진행하세요.")
        return

    loader = DataLoader(dataset, batch_size=args.batch, shuffle=True,
                        num_workers=0, drop_last=True)

    optimizer = torch.optim.AdamW(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=args.lr, weight_decay=0.01
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=args.epochs * len(loader)
    )

    best_loss = float("inf")
    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0

        for img_a, img_b, _ in tqdm(loader, desc=f"Epoch {epoch}/{args.epochs}"):
            img_a, img_b = img_a.to(DEVICE), img_b.to(DEVICE)

            with torch.set_grad_enabled(True):
                out_a = model(pixel_values=img_a).last_hidden_state
                out_b = model(pixel_values=img_b).last_hidden_state
                z_a = torch.cat([out_a[:, 0, :], out_a[:, 1:, :].mean(dim=1)], dim=-1)
                z_b = torch.cat([out_b[:, 0, :], out_b[:, 1:, :].mean(dim=1)], dim=-1)
                loss = nt_xent_loss(z_a, z_b, temp=args.temp)

            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()
            total_loss += loss.item()

        avg = total_loss / len(loader)
        print(f"  Epoch {epoch}: loss={avg:.4f}")

        if avg < best_loss:
            best_loss = avg
            model.save_pretrained(str(SAVE_PATH.parent / "dinov2_finetuned"))
            print(f"  → 저장: {SAVE_PATH.parent / 'dinov2_finetuned'}")

    print(f"\n파인튜닝 완료! best_loss={best_loss:.4f}")
    print("다음 단계: python db/build_db.py --model model/dinov2_finetuned")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--data",   default="data/crawl_raw/training_data.json")
    p.add_argument("--epochs", type=int,   default=10)
    p.add_argument("--batch",  type=int,   default=16)
    p.add_argument("--lr",     type=float, default=1e-4)
    p.add_argument("--temp",   type=float, default=0.07)
    train(p.parse_args())
