"""
SNKRDUNK 프로모 카드 **검수용 HTML** 생성 (DB 넣기 전 눈으로 확인).

★스캐너 env python 으로 실행 (PIL 이미지 정규화 필요):
    /Users/fury/miniconda3/envs/scanner_v2/bin/python gen_snkrdunk_promo_review.py --apparel 618447 --slug fukuoka_pikachu

prod/DB/S3 전부 무접속. 로컬 파일만 생성:
  - review_snkrdunk_<slug>.html
  - original_downloaded_<slug>.<ext>   (SNK 원본 다운로드)
  - normalized_<slug>.<ext>            (카드 bbox crop 정규화 — 앱 상세용)
  - review_data_<slug>.json

검증: SNK detail/sales HTTP 200, title/set/number 일치, 이미지 실물(크기/용량/ctype/dims),
A/PSA10/PSA9 실체결 집계, **KRW 환산 실체결일별 차트**, DB 예정값(+S3 이미지 경로),
ladder 비정상 경고, 데스크톱+모바일(390/430) 앱 미리보기,
"차트 백엔드 수정 없이 (등록/이미지/RAW가) 보일 화면" vs "차트 백엔드 수정 후 화면" 구분.
"""

import os
import re
import csv
import json
import html
import argparse
import statistics
from collections import defaultdict
from datetime import datetime, timedelta

import requests

HEADERS = {"accept": "application/json", "user-agent": "Mozilla/5.0"}
DETAIL = "https://snkrdunk.com/v1/apparels/{aid}"
SALES = "https://snkrdunk.com/v1/apparels/{aid}/sales-history?size_id=0&page={p}&per_page=50"
OUTDIR = os.path.expanduser("~/Downloads/snkrdunk_promo_20260702")
GRADE_MAP = {"A": ("RAW", None, None), "PSA10": ("GRADED", "PSA", "10"), "PSA9": ("GRADED", "PSA", "9")}
# 앱 이미지 S3 경로 (memory: prod 카드이미지=S3 직접, cardCdnBase 기본=.../cards/v1). card_id 는 importer apply 시 확정.
S3_BASE = "https://pokefolio-assets.s3.ap-northeast-2.amazonaws.com/cards/v1"
FALLBACK_FX = 9.54
now = datetime.now()


def log(*a): print(*a, flush=True)


def parse_date(s):
    s = (s or "").strip()
    for pat, u in ((r"(\d+)分前", "m"), (r"(\d+)時間前", "h"), (r"(\d+)日前", "d")):
        m = re.match(pat, s)
        if m:
            n = int(m.group(1))
            return (now - timedelta(**{"m": {"minutes": n}, "h": {"hours": n}, "d": {"days": n}}[u])).date()
    m = re.match(r"(\d{4})/(\d{2})/(\d{2})", s)
    return datetime(*map(int, m.groups())).date() if m else None


def fetch_fx():
    try:
        r = requests.get("https://open.er-api.com/v6/latest/JPY", timeout=10)
        k = r.json().get("rates", {}).get("KRW")
        if k and k > 0:
            return float(k), "open.er-api.com JPY→KRW"
    except Exception:
        pass
    return FALLBACK_FX, "fallback 9.54"


def normalize_image(path, slug, ext):
    """카드 bbox crop + 3% 여백 → 정규화(앱 상세용). (norm_filename, orig_dims, norm_dims)."""
    try:
        from PIL import Image, ImageChops
        im = Image.open(path).convert("RGBA")
        odim = im.size
        bbox = im.split()[-1].getbbox()
        if not bbox:
            bg = Image.new("RGB", im.size, (255, 255, 255))
            bbox = ImageChops.difference(im.convert("RGB"), bg).getbbox()
        x0, y0, x1, y1 = bbox
        mx = int((x1 - x0) * 0.03); my = int((y1 - y0) * 0.03)
        crop = im.crop((max(0, x0 - mx), max(0, y0 - my), min(im.width, x1 + mx), min(im.height, y1 + my)))
        nf = f"normalized_{slug}{ext}"
        crop.save(os.path.join(OUTDIR, nf), "WEBP", quality=92)
        return nf, odim, crop.size
    except Exception as e:
        log(f"  [WARN] 정규화 실패({e}) → 원본 사용")
        return f"original_downloaded_{slug}{ext}", None, None


def svg_chart(series, title):
    """series: {label:(color,[(date,KRW)])}. 실체결일별 KRW 라인."""
    W, H, pad = 820, 240, 62
    all_pts = [(d, p) for _, pts in series.values() for d, p in pts]
    if len(all_pts) < 2:
        return f"<div class='chart'><b>{html.escape(title)}</b><p class='muted'>데이터 부족</p></div>"
    xs = [d.toordinal() for d, _ in all_pts]; ys = [p for _, p in all_pts]
    xmin, xmax = min(xs), max(xs); ymin, ymax = min(ys), max(ys)
    def X(x): return pad + (x - xmin) / (xmax - xmin or 1) * (W - 2 * pad)
    def Y(y): return H - pad - (y - ymin) / (ymax - ymin or 1) * (H - pad - 24)
    body = []
    for i in range(5):
        yy = ymin + (ymax - ymin) * i / 4; py = Y(yy)
        body.append(f"<line x1='{pad}' y1='{py:.0f}' x2='{W-14}' y2='{py:.0f}' stroke='#2a2f3a'/>")
        body.append(f"<text x='4' y='{py+4:.0f}' fill='#8b93a7' font-size='10'>₩{int(yy):,}</text>")
    for label, (color, pts) in series.items():
        if len(pts) < 2: continue
        poly = " ".join(f"{X(d.toordinal()):.1f},{Y(p):.1f}" for d, p in pts)
        body.append(f"<polyline fill='none' stroke='{color}' stroke-width='2' points='{poly}'/>")
        d, p = pts[-1]
        body.append(f"<circle cx='{X(d.toordinal()):.1f}' cy='{Y(p):.1f}' r='3' fill='{color}'/>")
    dmin = min(d for d, _ in all_pts); dmax = max(d for d, _ in all_pts)
    body.append(f"<text x='{pad}' y='{H-6}' fill='#8b93a7' font-size='10'>{dmin}</text>")
    body.append(f"<text x='{W-90}' y='{H-6}' fill='#8b93a7' font-size='10'>{dmax}</text>")
    legend = " ".join(f"<span style='color:{c}'>● {html.escape(l)}</span>" for l, (c, _) in series.items())
    return (f"<div class='chart'><b>{html.escape(title)}</b> <span class='legend'>{legend}</span>"
            f"<svg viewBox='0 0 {W} {H}' width='100%'>{''.join(body)}</svg></div>")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apparel", default="618447")
    ap.add_argument("--slug", default="fukuoka_pikachu")
    ap.add_argument("--candidates", default="snkrdunk_missing_promo_candidates.csv")
    ap.add_argument("--import-list", default="snkrdunk_import_list.csv")
    args = ap.parse_args()
    aid = args.apparel
    os.makedirs(OUTDIR, exist_ok=True)

    curated = {r["apparel_id"].strip(): r for r in csv.DictReader(open(args.import_list, encoding="utf-8"))}.get(aid, {})
    cand = {r["snkrdunk_apparel_id"].strip(): r for r in csv.DictReader(open(args.candidates, encoding="utf-8")) if r.get("snkrdunk_apparel_id")}.get(aid, {})

    checks = {}
    dr = requests.get(DETAIL.format(aid=aid), headers=HEADERS, timeout=15)
    checks["detail_http"] = dr.status_code
    detail = dr.json() if dr.status_code == 200 else {}
    by = {g: defaultdict(list) for g in GRADE_MAP}
    total = 0; sales_http = None
    for p in range(1, 61):
        sr = requests.get(SALES.format(aid=aid, p=p), headers=HEADERS, timeout=15)
        sales_http = sales_http or sr.status_code
        if sr.status_code != 200: break
        h = sr.json().get("history", [])
        if not h: break
        total += len(h)
        for x in h:
            c = x.get("condition"); d = parse_date(x.get("date", ""))
            if c in by and d and x.get("price"):
                by[c][d].append(int(x["price"]))
    checks["sales_http"] = sales_http; checks["sales_total"] = total

    img_url = detail.get("primaryMedia", {}).get("imageUrl") or cand.get("snkrdunk_image_url", "")
    ir = requests.get(img_url, headers={"user-agent": "Mozilla/5.0"}, timeout=20)
    ctype = ir.headers.get("content-type", "")
    ext = ".webp" if "webp" in ctype or img_url.endswith(".webp") else (os.path.splitext(img_url)[1] or ".img")
    orig_file = f"original_downloaded_{args.slug}{ext}"
    open(os.path.join(OUTDIR, orig_file), "wb").write(ir.content)
    norm_file, odim, ndim = normalize_image(os.path.join(OUTDIR, orig_file), args.slug, ext)
    checks.update(image_http=ir.status_code, image_ctype=ctype, image_bytes=len(ir.content),
                  image_dims=odim, norm_dims=ndim)

    fx, fx_src = fetch_fx()
    def r10(v): return int(round(v / 10) * 10)

    daily_krw = {}; latest_jpy = {}
    for g in GRADE_MAP:
        pts = sorted((d, statistics.median(v)) for d, v in by[g].items())   # JPY
        latest_jpy[g] = pts[-1][1] if pts else None
        daily_krw[g] = [(d, r10(p * fx)) for d, p in pts]                    # KRW (차트/저장 기준)

    set_norm = cand.get("set_norm", ""); number = cand.get("number", "")
    official = f"{set_norm}{int(number):0>9}" if number else ""
    ko_name = curated.get("ko_name", ""); product = curated.get("product_ko_name", "")
    rarity = curated.get("rarity_code", "PR"); ptype = curated.get("promo_type", "")
    raw_krw = daily_krw["A"][-1][1] if daily_krw["A"] else None
    p10_krw = daily_krw["PSA10"][-1][1] if daily_krw["PSA10"] else None
    p9_krw = daily_krw["PSA9"][-1][1] if daily_krw["PSA9"] else None
    lname = detail.get("localizedName", ""); ename = detail.get("name", "")
    # 제목·번호 일치 — 후보 CSV의 number로 검증(파일럿 때 289/フクオカ 하드코딩이던 것 파라미터화, 2026-07-03)
    title_ok = bool(number) and (number.lstrip("0") in (lname + ename))
    ladder_bad = raw_krw and p9_krw and raw_krw > p9_krw
    s3_path = f"{S3_BASE}/{{card_id}}{ext}"

    json.dump({"apparel_id": aid, "checks": {k: str(v) for k, v in checks.items()}, "official_code": official,
               "ko_name": ko_name, "product": product, "fx": fx, "fx_src": fx_src,
               "latest_jpy": latest_jpy, "latest_krw": {"RAW": raw_krw, "PSA10": p10_krw, "PSA9": p9_krw},
               "grade_days": {g: len(by[g]) for g in GRADE_MAP}, "image_url": img_url,
               "orig_dims": odim, "norm_dims": ndim, "s3_path": s3_path},
              open(os.path.join(OUTDIR, f"review_data_{args.slug}.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2, default=str)

    def chk(v, ok): return f"<span class='{'ok' if ok else 'bad'}'>{'✅' if ok else '⚠️'} {html.escape(str(v))}</span>"
    charts = svg_chart({"RAW": ("#4ea1ff", daily_krw["A"]), "PSA10": ("#ff6b6b", daily_krw["PSA10"]),
                        "PSA9": ("#ffd166", daily_krw["PSA9"])}, "RAW / PSA10 / PSA9 (KRW · 실체결일별 median)")

    def pcard(lbl, jpy, krw, color):
        return (f"<div class='pcard' style='border-color:{color}'><div class='plbl'>{lbl}</div>"
                f"<div class='pval'>{'₩'+format(krw,',') if krw else '—'}</div>"
                f"<div class='muted'>{'검수용 원가 ¥'+format(int(jpy),',') if jpy else '—'}</div></div>")

    def app_body(mini_chart=""):
        return f"""
<img class=cardimg src="{norm_file}">
<div style='font-size:19px;font-weight:700;margin-top:8px'>{html.escape(ko_name)}</div>
<div class=muted>{html.escape(lname)} · {html.escape(ename)}</div>
<div class=krow><span class=kk>세트</span><span>{html.escape(product)}</span></div>
<div class=krow><span class=kk>번호 / 레어도</span><span>SV-P {number} · {rarity}</span></div>
<div class=krow><span class=kk>구분</span><span>해외 프로모 카드</span></div>
<div class=hprice><span class=chip style='color:#9db4ff;border-color:#3a4568'>해외 참고가</span> <b>{'₩'+format(raw_krw,',') if raw_krw else '—'}</b> <span class=muted>(RAW)</span></div>
<div class=muted style='margin-top:4px'>※ 앱 기존 라벨 그대로: is_promo_exclusive → OVERSEAS_REF → "해외 참고가" (price_label.dart, 메타몽 등과 동일). 자동 부여 · 코드 변경 불필요 · OVERSEAS_REF는 별도 안내문 없이 칩만 표시.</div>
<div class=prow>
  <span class=chip style='color:#ff6b6b'>PSA10 ₩{format(p10_krw,',') if p10_krw else '—'}</span>
  <span class=chip style='color:#ffd166'>PSA9 ₩{format(p9_krw,',') if p9_krw else '—'}</span>
</div>{mini_chart}"""

    H = f"""<!doctype html><html lang=ko><meta charset=utf-8>
<title>검수 · {html.escape(ko_name)} (SV-P {number})</title>
<style>
body{{background:#0e1116;color:#e6e9ef;font-family:-apple-system,system-ui,sans-serif;margin:0;padding:24px;max-width:1040px;margin:auto}}
h1{{font-size:22px}} h2{{font-size:16px;border-bottom:1px solid #2a2f3a;padding-bottom:6px;margin-top:28px}}
.muted{{color:#8b93a7;font-size:12px}} .ok{{color:#5fd08a}} .bad{{color:#ff8f6b;font-weight:600}}
.row{{display:flex;gap:20px;flex-wrap:wrap;align-items:flex-start}}
.card{{background:#161a22;border:1px solid #2a2f3a;border-radius:12px;padding:16px}}
img.cardimg{{width:100%;max-width:300px;border-radius:12px;background:#20242e;display:block}}
table{{border-collapse:collapse;width:100%;font-size:13px}} td,th{{border:1px solid #2a2f3a;padding:6px 10px;text-align:left}}
.pcard{{background:#161a22;border:2px solid;border-radius:10px;padding:12px 16px;min-width:150px}}
.plbl{{font-size:12px;color:#8b93a7}} .pval{{font-size:22px;font-weight:700}}
.chart{{background:#161a22;border:1px solid #2a2f3a;border-radius:12px;padding:14px;margin-top:12px}}
.legend span{{margin-left:12px;font-size:12px}}
.warn{{background:#3a2318;border:1px solid #ff8f6b;border-radius:10px;padding:12px;margin-top:12px}}
.badge{{display:inline-block;background:#26304a;color:#9db4ff;border-radius:6px;padding:2px 8px;font-size:12px;margin-left:6px}}
.phone{{width:390px;background:#0b0d12;border:8px solid #262b36;border-radius:32px;padding:14px}}
.phone.android{{width:430px}}
.krow{{display:flex;justify-content:space-between;border-top:1px solid #21262f;padding:6px 0;font-size:13px}} .kk{{color:#8b93a7}}
.hprice{{margin-top:10px;font-size:15px}} .hprice b{{font-size:20px}}
.prow{{margin-top:8px}} .chip{{display:inline-block;border:1px solid #2a2f3a;border-radius:8px;padding:3px 8px;font-size:12px;margin-right:6px}}
.imgcap{{font-size:11px;color:#8b93a7;margin-top:6px}}
</style>
<h1>검수 · {html.escape(ko_name)} <span class=badge>해외 프로모</span> <span class=badge>SV-P {number}</span></h1>
<p class=muted><b>DB/S3/prod 넣기 전 검수용.</b> 모두 로컬 파일. 승인 후에만 등록.</p>

<h2>1. SNK 원본 검증 (apparel_id {aid})</h2>
<table>
<tr><td>detail API</td><td>{chk(checks['detail_http'],checks['detail_http']==200)}</td></tr>
<tr><td>sales-history / 수집</td><td>{chk(checks['sales_http'],checks['sales_http']==200)} · {checks['sales_total']}건</td></tr>
<tr><td>SNK 원제(JP/EN)</td><td>{html.escape(lname)} · {html.escape(ename)}</td></tr>
<tr><td>제목·번호 일치({html.escape(number)})</td><td>{chk('일치' if title_ok else '불일치', title_ok)}</td></tr>
<tr><td>이미지 HTTP / ctype</td><td>{chk(checks['image_http'],checks['image_http']==200)} · {html.escape(ctype)}</td></tr>
<tr><td>이미지 용량 / 원본 dims / 정규화 dims</td><td>{checks['image_bytes']:,} bytes · {odim} · {ndim}</td></tr>
</table>

<h2>2. 이미지 — 원본 vs 정규화 (S3 넣기 전)</h2>
<div class=row>
<div class=card><img class=cardimg src="{orig_file}"><div class=imgcap>원본 {orig_file}<br>{odim} · 투명여백 큼(앱서 작게 보임)</div></div>
<div class=card><img class=cardimg src="{norm_file}"><div class=imgcap>✅ 정규화 {norm_file}<br>{ndim} · 카드 bbox crop → 앱 상세용</div></div>
<div class=card><p class=muted>· SNK 이미지 = 배경투명(bg_removed) 카드 앞면.<br>· 앱/S3 에는 <b>정규화본</b> 사용 예정.<br>· hotlink 아님(다운로드본).</p></div>
</div>

<h2>A. 카드 DB 등록 + S3 이미지 반영 + RAW 가격 반영 후 (차트 백엔드 수정 없이) 보일 화면</h2>
<p class=muted>※ 지금 자동 노출이 아니라, 아래(등록·이미지 미러·RAW 예상가)까지 반영되면 차트 백엔드 수정 없이 보이는 화면.</p>
<div class=row>
<div class=phone><div class=muted style='text-align:center'>iPhone 390</div>{app_body()}</div>
<div class="phone android"><div class=muted style='text-align:center'>Android 430</div>{app_body()}</div>
<div class=card style='flex:1;min-width:260px'>
<b>가격 요약</b> <span class=muted>(fx {fx:.2f} · {html.escape(fx_src)})</span>
<div class=row style='margin-top:10px'>{pcard('RAW',latest_jpy['A'],raw_krw,'#4ea1ff')}{pcard('PSA10',latest_jpy['PSA10'],p10_krw,'#ff6b6b')}{pcard('PSA9',latest_jpy['PSA9'],p9_krw,'#ffd166')}</div>
{"<div class=warn>⚠️ <b>ladder 비정상</b>: RAW(₩"+format(raw_krw,',')+") &gt; PSA9(₩"+format(p9_krw,',')+"). 미감정 선호 프로모 — 실측 그대로 저장, ladder 강제 금지.</div>" if ladder_bad else ""}
</div></div>

<h2>B. 차트 백엔드 수정 후 보일 화면 (KRW 차트)</h2>
<p class=muted>NO_EN/NO_JP 프로모 상세차트는 현재 <b>source='KREAM' 하드코딩</b> → SNKRDUNK 차트는 <b>후속 백엔드(source IN 확장)</b> 후 노출. 아래는 backfill 데이터(KRW) 기준:</p>
{charts}
<p class=muted>RAW {len(by['A'])}일 · PSA10 {len(by['PSA10'])}일 · PSA9 {len(by['PSA9'])}일 (실제 체결일)</p>

<h2>3. DB 예정값 (미적용) + 이미지 경로</h2>
<table>
<tr><td>products</td><td>name='{html.escape(product)}' · KO (없으면 신규)</td></tr>
<tr><td>cards</td><td>official_card_code=<b>{official}</b> · name='{html.escape(ko_name)}' · {rarity} · is_promo_exclusive=TRUE · {html.escape(ptype)} · NO_JP/NO_EN</td></tr>
<tr><td>cards.image_url (S3 예정)</td><td>{html.escape(s3_path)}<br><span class=bad>※ card_id는 importer apply 후 확정 · 확정 전 S3 업로드 금지 (정규화본 업로드)</span></td></tr>
<tr><td>card_external_refs</td><td>source='SNKRDUNK' · external_id={aid} · is_active=TRUE</td></tr>
<tr><td>price_snapshots (backfill)</td><td>SNKRDUNK RAW {len(by['A'])} · PSA10 {len(by['PSA10'])} · PSA9 {len(by['PSA9'])} · KO_ESTIMATED(RAW) {len(by['A'])} 행 · traded_at=실제 체결일</td></tr>
</table>

<h2>4. 위험 / 후속</h2>
<div class=warn>· scrydex 없음(svp_ja-289=404) → 소스=SNKRDUNK(내부), v6/ladder/sanity 미사용<br>
· 이미지: 정규화본 S3 미러 → cards.image_url 반영 → FAISS 벡터 재생성 → 실기기 스캔<br>
· PSA10/PSA9 차트 노출 = 백엔드 source IN('KREAM','SNKRDUNK') 후속 배포 필요<br>
· <b>사용자 노출 라벨 = "해외 참고가"</b> (앱 기존 OVERSEAS_REF 매핑 · price_label.dart:26). is_promo_exclusive→자동 부여, 코드 변경 불필요. 소스='SNKRDUNK'·KO_ESTIMATED 는 내부용.<br>
· language='KO' 는 카탈로그 내부 표기(메타몽 동일, 한국 발매 아님) → 앱 노출 구분은 '해외 프로모 카드'로.</div>
<p class=muted>로컬 전용 · prod write 0 · {now:%Y-%m-%d %H:%M}</p>
</html>"""
    out = os.path.join(OUTDIR, f"review_snkrdunk_{args.slug}.html")
    open(out, "w", encoding="utf-8").write(H)
    log(f"✅ {out}")
    log(f"   이미지 원본 {odim} → 정규화 {ndim} · {orig_file} / {norm_file}")
    log(f"   차트=KRW · RAW ₩{raw_krw:,} · PSA10 ₩{p10_krw:,} · PSA9 ₩{p9_krw:,} · ladder_bad={ladder_bad}")
    log(f"   검증 detail {checks['detail_http']} sales {checks['sales_http']}/{total} image {checks['image_http']} 제목일치 {title_ok}")


if __name__ == "__main__":
    main()
