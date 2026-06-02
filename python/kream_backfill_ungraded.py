#!/usr/bin/env python3
"""메타몽 KREAM Ungraded 공백 백필 (2026-06-03 일회성).

cron 이 2026-05-13 에 멈춰 05-14~06-02 Ungraded 데이터 공백.
사용자가 KREAM 화면에서 복사한 raw 거래내역(등급 섞임)에서 Ungraded 만 추출 →
기존 MAX(2026-05-13) 이후 날짜만 INSERT SQL 생성. (PSA/BRG/PSA8 제외)

실행: python3 kream_backfill_ungraded.py > backfill.sql
그 후: ssh prod 'docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db' < backfill.sql
"""
import re
import datetime
import uuid

CARD_ID = "CRD_205C20056CBF48F8B08D"
CUTOFF = datetime.date(2026, 5, 13)        # 기존 Ungraded MAX — 이 날짜 "초과"만 INSERT
NOW = datetime.datetime(2026, 6, 3, 2, 0)  # 상대시간("N시간 전") 기준점

RAW = """PSA 10 (Card Ver.)
535,000원
1시간 전
Ungraded
190,000원
13시간 전
Ungraded
189,000원
13시간 전
Ungraded
189,000원
13시간 전
PSA 10 (Card Ver.)
506,000원
17시간 전
Ungraded
188,000원
26/06/02
PSA 10 (Card Ver.)
537,000원
26/06/02
Ungraded
205,000원
빠른배송
26/06/01
PSA 10 (Card Ver.)
510,000원
26/06/01
PSA 10 (Card Ver.)
547,000원
빠른배송
26/06/01
PSA 10 (Card Ver.)
515,000원
26/06/01
Ungraded
179,000원
26/06/01
PSA 9 (Card Ver.)
242,000원
26/06/01
PSA 9 (Card Ver.)
237,000원
26/06/01
PSA 9 (Card Ver.)
233,000원
26/06/01
BRG 9 한글
180,000원
26/06/01
PSA 9 (Card Ver.)
232,000원
26/06/01
Ungraded
178,000원
26/06/01
Ungraded
179,000원
26/06/01
Ungraded
180,000원
26/06/01
Ungraded
179,000원
26/05/31
PSA 10 (Card Ver.)
507,000원
26/05/31
PSA 10 (Card Ver.)
510,000원
26/05/31
PSA 10 (Card Ver.)
510,000원
26/05/31
PSA 10 (Card Ver.)
510,000원
26/05/31
PSA 9 (Card Ver.)
299,000원
빠른배송
26/05/31
Ungraded
179,000원
26/05/31
Ungraded
207,000원
빠른배송
26/05/31
PSA 10 (Card Ver.)
538,000원
26/05/30
PSA 10 (Card Ver.)
537,000원
26/05/30
Ungraded
179,000원
26/05/30
Ungraded
183,000원
26/05/30
PSA 10 (Card Ver.)
520,000원
26/05/30
PSA 9 (Card Ver.)
225,000원
26/05/30
PSA 10 (Card Ver.)
530,000원
26/05/30
PSA 10 (Card Ver.)
510,000원
26/05/29
Ungraded
192,000원
26/05/29
PSA 10 (Card Ver.)
540,000원
26/05/29
Ungraded
192,000원
26/05/29
Ungraded
184,000원
26/05/29
Ungraded
192,000원
26/05/29
Ungraded
220,000원
빠른배송
26/05/29
PSA 10 (Card Ver.)
548,000원
26/05/29
PSA 10 (Card Ver.)
500,000원
26/05/28
PSA 10 (Card Ver.)
501,000원
26/05/28
Ungraded
220,000원
빠른배송
26/05/28
Ungraded
190,000원
26/05/28
PSA 10 (Card Ver.)
564,000원
빠른배송
26/05/28
PSA 10 (Card Ver.)
563,000원
빠른배송
26/05/28
Ungraded
182,000원
26/05/28
Ungraded
182,000원
26/05/28
Ungraded
193,000원
26/05/27
PSA 10 (Card Ver.)
495,000원
26/05/27
PSA 10 (Card Ver.)
535,000원
26/05/27
PSA 10 (Card Ver.)
534,000원
26/05/27
Ungraded
193,000원
26/05/27
Ungraded
209,000원
빠른배송
26/05/27
Ungraded
193,000원
26/05/27
PSA 10 (Card Ver.)
550,000원
빠른배송
26/05/27
PSA 10 (Card Ver.)
536,000원
26/05/26
PSA 10 (Card Ver.)
520,000원
26/05/26
Ungraded
214,000원
빠른배송
26/05/26
PSA 10 (Card Ver.)
492,000원
26/05/26
BRG 10 영문
390,000원
26/05/26
PSA 10 (Card Ver.)
543,000원
빠른배송
26/05/26
Ungraded
210,000원
빠른배송
26/05/26
Ungraded
190,000원
26/05/26
PSA 10 (Card Ver.)
519,000원
26/05/26
Ungraded
193,000원
26/05/26
Ungraded
184,000원
26/05/26
Ungraded
190,000원
26/05/25
Ungraded
189,000원
26/05/25
BRG 10 영문
350,000원
26/05/25
PSA 10 (Card Ver.)
539,000원
26/05/25
Ungraded
183,000원
26/05/25
PSA 10 (Card Ver.)
540,000원
빠른배송
26/05/25
PSA 10 (Card Ver.)
535,000원
26/05/25
PSA 10 (Card Ver.)
538,000원
빠른배송
26/05/25
PSA 10 (Card Ver.)
535,000원
빠른배송
26/05/24
Ungraded
182,000원
26/05/24
Ungraded
209,000원
빠른배송
26/05/24
Ungraded
182,000원
26/05/24
Ungraded
182,000원
26/05/24
Ungraded
183,000원
26/05/24
PSA 10 (Card Ver.)
530,000원
26/05/24
PSA 10 (Card Ver.)
525,000원
26/05/24
PSA 10 (Card Ver.)
520,000원
26/05/24
PSA 10 (Card Ver.)
519,000원
26/05/24
PSA 10 (Card Ver.)
518,000원
26/05/24
PSA 9 (Card Ver.)
234,000원
26/05/24
PSA 10 (Card Ver.)
537,000원
빠른배송
26/05/24
PSA 10 (Card Ver.)
518,000원
26/05/23
Ungraded
190,000원
26/05/23
PSA 10 (Card Ver.)
495,000원
26/05/23
Ungraded
190,000원
26/05/23
Ungraded
199,000원
26/05/23
PSA 10 (Card Ver.)
510,000원
26/05/23
PSA 10 (Card Ver.)
529,000원
빠른배송
26/05/23
PSA 9 (Card Ver.)
239,000원
빠른배송
26/05/22
PSA 9 (Card Ver.)
238,000원
빠른배송
26/05/22
PSA 10 (Card Ver.)
510,000원
26/05/22
Ungraded
208,000원
빠른배송
26/05/22
Ungraded
208,000원
빠른배송
26/05/22
Ungraded
195,000원
26/05/22
PSA 10 (Card Ver.)
510,000원
26/05/22
Ungraded
190,000원
26/05/22
PSA 10 (Card Ver.)
515,000원
26/05/22
PSA 10 (Card Ver.)
543,000원
빠른배송
26/05/22
PSA 10 (Card Ver.)
516,000원
26/05/22
PSA 10 (Card Ver.)
544,000원
빠른배송
26/05/22
Ungraded
184,000원
26/05/21
Ungraded
183,000원
26/05/21
PSA 10 (Card Ver.)
539,000원
빠른배송
26/05/21
Ungraded
186,000원
26/05/21
PSA 10 (Card Ver.)
537,000원
26/05/21
PSA 10 (Card Ver.)
539,000원
빠른배송
26/05/21
Ungraded
186,000원
26/05/21
Ungraded
186,000원
26/05/21
PSA 10 (Card Ver.)
544,000원
26/05/20
Ungraded
195,000원
26/05/20
PSA 10 (Card Ver.)
539,000원
26/05/20
PSA 10 (Card Ver.)
546,000원
빠른배송
26/05/20
Ungraded
218,000원
빠른배송
26/05/20
Ungraded
209,000원
26/05/20
PSA 10 (Card Ver.)
539,000원
빠른배송
26/05/20
PSA 10 (Card Ver.)
530,000원
26/05/20
Ungraded
200,000원
26/05/20
PSA 10 (Card Ver.)
554,000원
빠른배송
26/05/20
PSA 10 (Card Ver.)
539,000원
26/05/19
Ungraded
184,000원
26/05/19
Ungraded
198,000원
26/05/19
PSA 10 (Card Ver.)
530,000원
26/05/19
PSA 10 (Card Ver.)
551,000원
26/05/19
PSA 10 (Card Ver.)
560,000원
26/05/19
PSA 10 (Card Ver.)
555,000원
26/05/19
PSA 9 (Card Ver.)
220,000원
26/05/19
Ungraded
200,000원
26/05/19
PSA 10 (Card Ver.)
556,000원
26/05/19
PSA 10 (Card Ver.)
570,000원
26/05/18
PSA 10 (Card Ver.)
575,000원
빠른배송
26/05/18
PSA 10 (Card Ver.)
557,000원
26/05/18
PSA 10 (Card Ver.)
558,000원
26/05/18
Ungraded
223,000원
빠른배송
26/05/18
PSA 10 (Card Ver.)
565,000원
26/05/18
PSA 10 (Card Ver.)
575,000원
26/05/18
Ungraded
222,000원
빠른배송
26/05/18
PSA 10 (Card Ver.)
575,000원
26/05/18
Ungraded
221,000원
빠른배송
26/05/18
PSA 10 (Card Ver.)
575,000원
26/05/18
Ungraded
220,000원
빠른배송
26/05/17
Ungraded
210,000원
26/05/17
PSA 10 (Card Ver.)
575,000원
26/05/17
PSA 10 (Card Ver.)
575,000원
26/05/17
PSA 10 (Card Ver.)
578,000원
26/05/17
PSA 10 (Card Ver.)
592,000원
빠른배송
26/05/17
PSA 10 (Card Ver.)
591,000원
빠른배송
26/05/17
PSA 10 (Card Ver.)
579,000원
26/05/17
PSA 10 (Card Ver.)
574,000원
26/05/17
PSA 10 (Card Ver.)
569,000원
26/05/16
Ungraded
201,000원
26/05/16
PSA 10 (Card Ver.)
574,000원
26/05/16
Ungraded
228,000원
빠른배송
26/05/16
Ungraded
228,000원
빠른배송
26/05/16
PSA 8 (Card Ver.)
170,000원
26/05/16
Ungraded
207,000원
26/05/16
PSA 10 (Card Ver.)
579,000원
26/05/16
PSA 10 (Card Ver.)
578,000원
26/05/16
PSA 10 (Card Ver.)
556,000원
26/05/15
Ungraded
221,000원
26/05/15
Ungraded
219,000원
26/05/15
Ungraded
219,000원
26/05/15
PSA 10 (Card Ver.)
579,000원
26/05/15
PSA 10 (Card Ver.)
580,000원
26/05/15
Ungraded
218,000원
26/05/15
PSA 10 (Card Ver.)
580,000원
26/05/15
PSA 9 (Card Ver.)
239,000원
26/05/15
PSA 10 (Card Ver.)
579,000원
26/05/15
PSA 10 (Card Ver.)
578,000원
26/05/15
PSA 10 (Card Ver.)
570,000원
26/05/15
Ungraded
208,000원
26/05/14
Ungraded
210,000원
26/05/14
PSA 10 (Card Ver.)
579,000원
26/05/14
Ungraded
218,000원
26/05/14
Ungraded
217,000원
26/05/14
Ungraded
215,000원
26/05/14
PSA 10 (Card Ver.)
618,000원
빠른배송
26/05/14
Ungraded
210,000원
26/05/14
PSA 10 (Card Ver.)
580,000원
26/05/14
PSA 10 (Card Ver.)
580,000원
26/05/14
PSA 10 (Card Ver.)
580,000원
26/05/13
PSA 9 (Card Ver.)
210,000원
26/05/13
PSA 10 (Card Ver.)
578,000원
26/05/13
PSA 10 (Card Ver.)
574,000원
26/05/13
PSA 10 (Card Ver.)
594,000원
빠른배송
26/05/13
PSA 10 (Card Ver.)
580,000원
26/05/13
Ungraded
215,000원
26/05/13
Ungraded
215,000원
26/05/13
BRG 10 한글
351,000원
26/05/13
PSA 10 (Card Ver.)
580,000원
26/05/12
PSA 10 (Card Ver.)
579,000원
26/05/12
PSA 10 (Card Ver.)
578,000원
26/05/12
PSA 10 (Card Ver.)
577,000원
26/05/12
PSA 10 (Card Ver.)
590,000원
빠른배송
26/05/12
Ungraded
254,000원
빠른배송
26/05/12
Ungraded
219,000원
26/05/12
PSA 10 (Card Ver.)
589,000원
빠른배송
26/05/12
PSA 10 (Card Ver.)
578,000원
26/05/12
PSA 10 (Card Ver.)
575,000원
26/05/12
PSA 10 (Card Ver.)
574,000원
26/05/12
PSA 10 (Card Ver.)
551,000원
26/05/12
PSA 10 (Card Ver.)
571,000원
26/05/12
PSA 10 (Card Ver.)
580,000원
26/05/12
Ungraded
218,000원
26/05/12
Ungraded
254,000원
빠른배송
26/05/11
PSA 10 (Card Ver.)
589,000원
26/05/11
PSA 10 (Card Ver.)
589,000원
26/05/11
PSA 10 (Card Ver.)
590,000원
26/05/11
PSA 10 (Card Ver.)
593,000원
빠른배송
26/05/11
Ungraded
227,000원
26/05/11
Ungraded
229,000원
26/05/11
Ungraded
229,000원
26/05/11
Ungraded
223,000원
26/05/11
Ungraded
254,000원
빠른배송
26/05/11"""


def parse_date(s):
    s = s.strip()
    if "방금" in s or "분 전" in s or "시간 전" in s:
        m = re.search(r"(\d+)\s*시간", s)
        hrs = int(m.group(1)) if m else 0
        return (NOW - datetime.timedelta(hours=hrs)).date()
    m = re.match(r"(\d{2})/(\d{2})/(\d{2})", s)
    if m:
        return datetime.date(2000 + int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return None


def main():
    lines = [l.strip() for l in RAW.strip().splitlines() if l.strip()]
    entries = []  # (grade, price, date)
    i = 0
    while i < len(lines):
        g = lines[i]
        if not (g.startswith("Ungraded") or g.startswith("PSA") or g.startswith("BRG")):
            i += 1
            continue
        if i + 1 >= len(lines):
            break
        pm = re.search(r"([\d,]+)\s*원", lines[i + 1])
        price = int(pm.group(1).replace(",", "")) if pm else None
        j = i + 2
        if j < len(lines) and lines[j] == "빠른배송":
            j += 1
        date = parse_date(lines[j]) if j < len(lines) else None
        entries.append((g, price, date))
        i = j + 1

    ung = [(p, d) for (g, p, d) in entries
           if g.startswith("Ungraded") and p and d and d > CUTOFF]
    ung.sort(key=lambda x: x[1])  # 날짜 오름차순

    import sys
    print(f"-- 메타몽 KREAM Ungraded 백필: {len(ung)}건 (>{CUTOFF}), "
          f"전체파싱 {len(entries)}건", file=sys.stderr)
    print("BEGIN;")
    for p, d in ung:
        ts = datetime.datetime.combine(d, datetime.time(12, 0, 0))
        sid = "PS_" + uuid.uuid4().hex[:20].upper()
        print(
            "INSERT INTO price_snapshots "
            "(price_snapshot_id, card_id, source, price, card_status, title, "
            "traded_at, collected_at, created_at, raw_price, raw_currency) VALUES "
            f"('{sid}', '{CARD_ID}', 'KREAM', {p}, 'RAW', 'Ungraded', "
            f"'{ts}', NOW(), NOW(), {p}, 'KRW');"
        )
    print("COMMIT;")


if __name__ == "__main__":
    main()
