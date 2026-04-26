import psycopg2
import psycopg2.extras
from rapidfuzz import fuzz

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "pokemon_card_db",
    "user": "nightfury",
    "password": "",
}


def normalize_ocr_text(text):
    if not text:
        return ""
    # 공백은 살려두어 토큰 단위 fuzzy 매칭이 가능하게 함
    return str(text).lower().strip()


def vec_to_pgvector_str(vec: list[float]) -> str:
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


class DBMatcher:
    def __init__(self):
        self.conn = psycopg2.connect(**DB_CONFIG)
        self.cards_cache = []
        self._load_cards()

    def _load_cards(self):
        """전체 카드를 메모리에 로드 (텍스트 퍼지 매칭용)"""
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT card_id, official_card_code, name, collection_number, local_image_path
                FROM cards
            """)
            self.cards_cache = cur.fetchall()
            print(f"[DBMatcher] 카드 {len(self.cards_cache):,}장 로드 완료")

    def search_by_number_exact(self, ocr_number: str) -> dict | None:
        """
        번호로 정확히 1개 카드를 확정.
        예: '084/069' → collection_number가 정확히 일치하는 카드 반환.
        여러 장이면 None (동명이인 방지).
        """
        norm = ocr_number.strip().lower()
        matches = []
        for card in self.cards_cache:
            c_num = normalize_ocr_text(card.get('collection_number'))
            if not c_num:
                continue
            # 정확히 같거나, 앞부분 숫자 일치 (084 == 084/069)
            if c_num == norm or c_num.split('/')[0] == norm.split('/')[0]:
                matches.append(card)

        if len(matches) == 1:
            card = matches[0]
            return {
                "card_id": card['card_id'],
                "name": card['name'],
                "number": card['collection_number'],
                "local_image_path": card['local_image_path'],
            }
        return None  # 0개 또는 여러 장 → 애매하므로 None

    def search_by_text(self, ocr_name: str, ocr_number: str, top_k: int = 5) -> list[dict]:
        """
        OCR로 추출한 이름/번호로 퍼지 매칭.
        번호(Max 60점) + 이름(Max 40점) 합산.
        """
        norm_name = normalize_ocr_text(ocr_name)
        norm_num = normalize_ocr_text(ocr_number)

        candidates = []
        for card in self.cards_cache:
            score = 0
            c_name = normalize_ocr_text(card.get('name'))
            c_num = normalize_ocr_text(card.get('collection_number'))

            # 번호 점수 (Max 60점) — 번호는 거의 유일한 식별자
            if norm_num and c_num:
                ratio = fuzz.token_set_ratio(norm_num, c_num)
                if ratio > 80:
                    score += (ratio / 100.0) * 60

            # 이름 점수 (Max 40점)
            if norm_name and c_name:
                ratio = fuzz.token_set_ratio(norm_name, c_name)
                if ratio >= 40:
                    score += (ratio / 100.0) * 40

            if score > 0:
                candidates.append({
                    "card_id": card['card_id'],
                    "code": card['official_card_code'],
                    "name": card['name'],
                    "number": card['collection_number'],
                    "local_image_path": card['local_image_path'],
                    "text_score": round(score, 1),
                })

        candidates.sort(key=lambda x: x['text_score'], reverse=True)
        return candidates[:top_k]

    def search_by_image(self, image_vec: list[float], top_k: int = 5) -> list[dict]:
        """
        DINOv2 벡터로 pgvector 코사인 유사도 검색 (HNSW 인덱스).
        이미지가 흐릿하거나 홀로그램 반사가 심해도 동작.
        """
        vec_str = vec_to_pgvector_str(image_vec)
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT card_id, official_card_code, name, collection_number, local_image_path,
                       1 - (image_feature_vector <=> %s::vector) AS similarity
                FROM cards
                WHERE image_feature_vector IS NOT NULL
                ORDER BY image_feature_vector <=> %s::vector
                LIMIT %s
            """, (vec_str, vec_str, top_k))
            rows = cur.fetchall()

        return [
            {
                "card_id": row['card_id'],
                "code": row['official_card_code'],
                "name": row['name'],
                "number": row['collection_number'],
                "local_image_path": row['local_image_path'],
                "image_score": round(float(row['similarity']), 4),
            }
            for row in rows
        ]

    def merge_candidates(
        self,
        text_candidates: list[dict],
        image_candidates: list[dict],
        top_k: int = 3,
    ) -> list[dict]:
        """
        텍스트 후보 + 이미지 후보를 합산해 최종 후보 반환.

        스코어 정규화:
          - 텍스트: 0~100점 → 0.0~1.0
          - 이미지: 코사인 유사도 0.0~1.0
        가중치: 텍스트 40% + 이미지 60% (이미지 신호가 더 풍부)
        """
        merged: dict[str, dict] = {}

        for c in text_candidates:
            cid = c['card_id']
            merged[cid] = {**c, "final_score": (c['text_score'] / 100.0) * 0.4}

        for c in image_candidates:
            cid = c['card_id']
            if cid in merged:
                merged[cid]['image_score'] = c['image_score']
                merged[cid]['final_score'] += c['image_score'] * 0.6
            else:
                merged[cid] = {**c, "text_score": 0.0, "final_score": c['image_score'] * 0.6}

        result = sorted(merged.values(), key=lambda x: x['final_score'], reverse=True)
        return result[:top_k]

    # 하위 호환용 (기존 run_camera_scan.py에서 사용 중)
    def search_candidates(self, ocr_name: str, ocr_number: str, top_k: int = 3) -> list[dict]:
        return self.search_by_text(ocr_name, ocr_number, top_k)
