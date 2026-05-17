"""SM-P 프로모 메타 보강 검수 UI.

data/promo_staging.json 로드 → 카드별 current DB vs scraped diff 보여주고
사용자가 승인한 카드만 일괄 UPDATE.

실행:
  cd scanner/training
  /Users/fury/miniconda3/envs/scanner_v2/bin/python review_promo_server.py
브라우저: http://localhost:8084
"""

from __future__ import annotations
import json
import os
import sys
from pathlib import Path
from typing import List

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import psycopg2
import uvicorn

ROOT = Path(__file__).parent
STAGING = ROOT / "data" / "promo_staging.json"
LOCAL_CARDS_DIR = ROOT.parent / "data" / "cards"  # scanner/data/cards

app = FastAPI()
# 로컬 카드 이미지 mount — pokemonkorea.co.kr 직접 사용 금지 정책 준수.
if LOCAL_CARDS_DIR.exists():
    app.mount("/local/cards", StaticFiles(directory=str(LOCAL_CARDS_DIR)), name="local-cards")


def db_connect():
    return psycopg2.connect(
        host="localhost",
        user="nightfury",
        dbname="pokemon_card_db",
        password=os.environ.get("DB_PASSWORD", ""),
    )


class ApplyPayload(BaseModel):
    card_ids: List[str]


@app.get("/list")
def list_data() -> JSONResponse:
    """staging JSON + DB 현재 상태 합쳐서 반환.

    staging은 크롤링 시점 snapshot이라 stale. 적용 후 화면 새로고침에서 진짜 변화를
    보려면 DB 현재 값으로 staging의 'current' 필드 덮어쓰고 diff를 재계산해야 한다.
    """
    if not STAGING.exists():
        raise HTTPException(404, f"staging 없음: {STAGING}")
    data = json.loads(STAGING.read_text())
    if not data:
        return JSONResponse(data)
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT card_id, COALESCE(collection_number,''), COALESCE(illustrator,'')
                     FROM cards WHERE card_id = ANY(%s)""",
                ([r["card_id"] for r in data],),
            )
            current = {row[0]: {"collection_number": row[1], "illustrator": row[2]}
                       for row in cur.fetchall()}
    finally:
        conn.close()
    for r in data:
        c = current.get(r["card_id"])
        if c:
            r["collection_number"] = c["collection_number"]
            r["illustrator"] = c["illustrator"]
        s = r.get("scraped") or {}
        diff = {}
        for key in ("collection_number", "illustrator"):
            cur_v = (r.get(key) or "").strip()
            new_v = (s.get(key) or "").strip()
            if new_v and new_v != cur_v:
                diff[key] = {"current": cur_v, "new": new_v}
        r["diff"] = diff
    return JSONResponse(data)


class UpdateRefPayload(BaseModel):
    card_id: str
    jp_scrydex_ref: str | None = None
    en_scrydex_ref: str | None = None


@app.get("/missing-refs")
def list_missing_refs(q: str = "", prefix: str = "") -> JSONResponse:
    """결측 ref 카드 목록 — jp/en ref 한 쪽이라도 빈 칸.

    NO_JP / NO_EN은 "발매 없음" 명시 → 결측 아님. 사용자가 매핑 불가능한 카드에
    NO_JP / NO_EN 입력하면 자동으로 목록에서 빠짐.

    q: name 또는 official_card_code 검색 (LIKE).
    prefix: official_card_code prefix 필터 (예: 'SMP', 'BS2017'). 빈 칸이면 전체.
    """
    filters = [
        "language = 'KO'",
        "((jp_scrydex_ref IS NULL OR jp_scrydex_ref = '')"
        " OR (en_scrydex_ref IS NULL OR en_scrydex_ref = ''))",
    ]
    params: list = []
    if prefix:
        filters.append("official_card_code LIKE %s")
        params.append(f"{prefix}%")
    if q:
        filters.append("(name ILIKE %s OR official_card_code ILIKE %s)")
        params.extend([f"%{q}%", f"%{q}%"])
    where = " AND ".join(filters)
    sql = f"""
        SELECT card_id, name, official_card_code,
               COALESCE(collection_number, '') AS collection_number,
               COALESCE(jp_scrydex_ref, '') AS jp_scrydex_ref,
               COALESCE(en_scrydex_ref, '') AS en_scrydex_ref
          FROM cards
         WHERE {where}
         ORDER BY official_card_code
         LIMIT 200
    """
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            cols = [d[0] for d in cur.description]
            rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    finally:
        conn.close()
    return JSONResponse(rows)


def _normalize_ref(s: str | None) -> str:
    """입력에서 진짜 ref만 추출.

    허용 입력 예:
      'smp_ja-86'                           → smp_ja-86
      '/smp_ja-86?variant=normal'           → smp_ja-86
      'https://scrydex.com/pokemon/cards/_/smp_ja-86?variant=normal' → smp_ja-86
      'NO_JP' / 'NO_EN'                     → NO_JP / NO_EN (그대로)
    """
    if not s:
        return ""
    s = s.strip()
    if not s:
        return ""
    # URL이거나 / 로 시작하면 마지막 path segment만
    if s.startswith("http://") or s.startswith("https://") or s.startswith("/"):
        s = s.rstrip("/")
        s = s.rsplit("/", 1)[-1]
    # 쿼리 파라미터 제거
    if "?" in s:
        s = s.split("?", 1)[0]
    if "#" in s:
        s = s.split("#", 1)[0]
    return s.strip()


@app.post("/update-ref")
def update_ref(payload: UpdateRefPayload) -> JSONResponse:
    """jp_scrydex_ref / en_scrydex_ref 단건 업데이트. URL 붙여넣어도 자동 추출."""
    jp = _normalize_ref(payload.jp_scrydex_ref)
    en = _normalize_ref(payload.en_scrydex_ref)
    sets = []
    vals: list[str] = []
    if jp:
        sets.append("jp_scrydex_ref = %s")
        vals.append(jp)
    if en:
        sets.append("en_scrydex_ref = %s")
        vals.append(en)
    if not sets:
        raise HTTPException(400, "변경할 필드 없음")
    vals.append(payload.card_id)
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE cards SET {', '.join(sets)} WHERE card_id = %s", vals,
            )
            updated = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return JSONResponse({"updated": updated, "saved_jp": jp, "saved_en": en})


@app.post("/apply")
def apply_updates(payload: ApplyPayload) -> JSONResponse:
    """선택된 card_id 들에 대해 scraped 값으로 UPDATE."""
    data = json.loads(STAGING.read_text())
    by_id = {r["card_id"]: r for r in data}
    approved = [by_id[cid] for cid in payload.card_ids if cid in by_id]

    updated_count = 0
    sql = "UPDATE cards SET "
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            for r in approved:
                scraped = r.get("scraped") or {}
                sets = []
                vals = []
                if scraped.get("collection_number"):
                    sets.append("collection_number = %s")
                    vals.append(scraped["collection_number"].strip())
                if scraped.get("illustrator"):
                    sets.append("illustrator = %s")
                    vals.append(scraped["illustrator"].strip())
                if not sets:
                    continue
                vals.append(r["card_id"])
                cur.execute(
                    f"UPDATE cards SET {', '.join(sets)} WHERE card_id = %s",
                    vals,
                )
                updated_count += cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return JSONResponse({"updated": updated_count})


HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>SM-P 프로모 검수</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; background: #0a0e16; color: #fff; font-family: -apple-system, sans-serif; }
  header {
    position: sticky; top: 0; z-index: 10;
    background: #0a0e16; border-bottom: 1px solid #1a2638;
    padding: 12px 20px; display: flex; gap: 16px; align-items: center;
  }
  header h1 { margin: 0; font-size: 16px; font-weight: 700; }
  .count { color: #7a93b0; font-size: 13px; }
  .btn {
    padding: 8px 14px; border-radius: 8px; border: none;
    font-size: 13px; font-weight: 600; cursor: pointer;
  }
  .btn-primary { background: #2563eb; color: #fff; }
  .btn-secondary { background: #1a2638; color: #fff; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #1a2638; font-size: 13px; vertical-align: middle; }
  th { background: #0d1520; position: sticky; top: 56px; font-size: 11px; text-transform: uppercase; color: #7a93b0; }
  tr.approved { background: #0d2515; }
  .code { font-family: monospace; font-size: 11px; color: #7a93b0; }
  .name { font-weight: 700; }
  .diff-cell { font-family: monospace; font-size: 12px; }
  .old { color: #7a93b0; text-decoration: line-through; }
  .new { color: #05c072; font-weight: 700; }
  .arrow { color: #4d8fea; margin: 0 4px; }
  img.thumb { width: 100px; height: 140px; object-fit: cover; border-radius: 6px; display: block; background: #1a2638; }
  .img-cell { display: flex; gap: 6px; }
  .img-cell .col { display: flex; flex-direction: column; align-items: center; gap: 2px; }
  .img-cell .col small { color: #7a93b0; font-size: 10px; font-weight: 700; }
  .img-cell .none { width: 100px; height: 140px; background: #0d1520; border-radius: 6px;
    display: flex; align-items: center; justify-content: center; color: #3a5470; font-size: 10px; }
  input[type=checkbox] { width: 18px; height: 18px; cursor: pointer; }
  #status { padding: 16px 20px; color: #05c072; font-weight: 600; }
</style>
</head>
<body>
<header>
  <h1>SM-P 프로모 메타 보강</h1>
  <span class="count" id="count">로딩...</span>
  <button class="btn btn-secondary" id="check-all">전부 승인</button>
  <button class="btn btn-secondary" id="uncheck-all">전부 해제</button>
  <button class="btn btn-primary" id="apply-btn" disabled>승인된 N장 DB에 반영</button>
  <a class="btn btn-secondary" href="/missing" style="text-decoration:none;display:inline-block;">결측 ref 채우기 →</a>
</header>
<table id="t">
  <thead>
    <tr>
      <th width="40">승인</th>
      <th width="330">이미지 (KO · JP · EN)</th>
      <th>이름</th>
      <th>official_card_code</th>
      <th>collection_number</th>
      <th>illustrator</th>
    </tr>
  </thead>
  <tbody></tbody>
</table>
<div id="status"></div>

<script>
const tbody = document.querySelector('#t tbody');
const countEl = document.getElementById('count');
const applyBtn = document.getElementById('apply-btn');
const status = document.getElementById('status');
let rows = [];

function esc(s) { return s == null ? '' : String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }

function diffCell(cur, neu) {
  const c = (cur || '').trim();
  const n = (neu || '').trim();
  if (!n || c === n) return `<span>${esc(c) || '<span style="color:#3a5470">-</span>'}</span>`;
  return `<span class="old">${esc(c) || '∅'}</span><span class="arrow">→</span><span class="new">${esc(n)}</span>`;
}

function scrydex(ref) {
  if (!ref || ref.startsWith('NO_')) return '';
  return `https://images.scrydex.com/pokemon/${encodeURIComponent(ref)}/medium`;
}
function koLocal(cardId) {
  // 로컬 우선 — scanner/data/cards/{cardId}_ko.png, 없으면 _jp.png onerror fallback
  return `/local/cards/${cardId}_ko.png`;
}
function jpLocal(cardId) {
  return `/local/cards/${cardId}_jp.png`;
}
function thumbCell(r) {
  const koSrc = koLocal(r.card_id);
  const jpFallback = jpLocal(r.card_id);
  const jpScrydex = scrydex(r.jp_scrydex_ref || '');
  const enScrydex = scrydex(r.en_scrydex_ref || '');
  // KO: 로컬 _ko 우선, onerror 시 _jp로 fallback.
  // JP: scrydex 우선, onerror 시 로컬 _jp로 fallback.
  // EN: scrydex만 (없으면 placeholder).
  return `<div class="img-cell">
    <div class="col">
      <img class="thumb" src="${koSrc}" loading="lazy"
        onerror="this.onerror=null;this.src='${jpFallback}';this.onerror=()=>{this.replaceWith(Object.assign(document.createElement('div'),{className:'none',textContent:'없음'}));};">
      <small>KO</small>
    </div>
    <div class="col">
      ${jpScrydex
        ? `<img class="thumb" src="${esc(jpScrydex)}" loading="lazy" onerror="this.onerror=null;this.src='${jpFallback}';this.onerror=()=>{this.replaceWith(Object.assign(document.createElement('div'),{className:'none',textContent:'없음'}));};">`
        : `<div class="none">${r.jp_scrydex_ref || '없음'}</div>`}
      <small>JP</small>
    </div>
    <div class="col">
      ${enScrydex
        ? `<img class="thumb" src="${esc(enScrydex)}" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'none',textContent:'깨짐'}));">`
        : `<div class="none">${r.en_scrydex_ref || '없음'}</div>`}
      <small>EN</small>
    </div>
  </div>`;
}

async function load() {
  const res = await fetch('/list');
  rows = await res.json();
  render();
}

function render() {
  tbody.innerHTML = '';
  rows.forEach((r, i) => {
    const s = r.scraped || {};
    const tr = document.createElement('tr');
    tr.dataset.idx = i;
    const isOk = r.status === 'ok' && Object.keys(r.diff || {}).length > 0;
    tr.innerHTML = `
      <td><input type="checkbox" ${isOk ? 'checked' : ''} ${!isOk ? 'disabled' : ''}></td>
      <td>${thumbCell(r)}</td>
      <td><div class="name">${esc(r.name)}</div></td>
      <td class="code">${esc(r.official_card_code)}<br><a href="${esc(r.url)}" target="_blank" style="font-size:10px;color:#4d8fea">소스 →</a></td>
      <td class="diff-cell">${diffCell(r.collection_number, s.collection_number)}</td>
      <td class="diff-cell">${diffCell(r.illustrator, s.illustrator)}</td>
    `;
    if (isOk) tr.classList.add('approved');
    tr.querySelector('input').addEventListener('change', (e) => {
      tr.classList.toggle('approved', e.target.checked);
      updateBtn();
    });
    tbody.appendChild(tr);
  });
  updateBtn();
}

function updateBtn() {
  const approved = tbody.querySelectorAll('input:checked').length;
  countEl.textContent = `${rows.length}장 중 승인 ${approved}장`;
  applyBtn.disabled = approved === 0;
  applyBtn.textContent = `승인된 ${approved}장 DB에 반영`;
}

document.getElementById('check-all').addEventListener('click', () => {
  tbody.querySelectorAll('input:not([disabled])').forEach(c => { c.checked = true; c.dispatchEvent(new Event('change')); });
});
document.getElementById('uncheck-all').addEventListener('click', () => {
  tbody.querySelectorAll('input').forEach(c => { c.checked = false; c.dispatchEvent(new Event('change')); });
});

applyBtn.addEventListener('click', async () => {
  const approved = [...tbody.querySelectorAll('input:checked')]
    .map(c => rows[parseInt(c.closest('tr').dataset.idx)].card_id);
  if (!confirm(`${approved.length}장을 DB에 UPDATE합니다. 계속?`)) return;
  const res = await fetch('/apply', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({card_ids: approved}),
  });
  const j = await res.json();
  status.textContent = `완료 — ${j.updated}장 업데이트됨.`;
});

load();
</script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    return HTMLResponse(HTML)


MISSING_HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>결측 ref 채우기</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; background: #0a0e16; color: #fff; font-family: -apple-system, sans-serif; }
  header {
    position: sticky; top: 0; z-index: 10;
    background: #0a0e16; border-bottom: 1px solid #1a2638;
    padding: 12px 20px; display: flex; gap: 16px; align-items: center;
  }
  header h1 { margin: 0; font-size: 16px; font-weight: 700; }
  .count { color: #7a93b0; font-size: 13px; }
  .help { color: #7a93b0; font-size: 11px; margin-left: auto; }
  .help a { color: #4d8fea; text-decoration: none; margin-left: 8px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 10px; text-align: left; border-bottom: 1px solid #1a2638; font-size: 13px; vertical-align: middle; }
  th { background: #0d1520; position: sticky; top: 56px; font-size: 11px; text-transform: uppercase; color: #7a93b0; }
  img.thumb { width: 90px; height: 126px; object-fit: cover; border-radius: 6px; display: block; background: #1a2638; }
  .img-cell { display: flex; gap: 6px; }
  .img-cell .col { display: flex; flex-direction: column; align-items: center; gap: 2px; }
  .img-cell .col small { color: #7a93b0; font-size: 10px; font-weight: 700; }
  .none { width: 90px; height: 126px; background: #0d1520; border-radius: 6px;
    display: flex; align-items: center; justify-content: center; color: #3a5470; font-size: 10px; }
  .name { font-weight: 700; }
  .code { font-family: monospace; font-size: 11px; color: #7a93b0; }
  input[type=text] {
    background: #0d1520; border: 1px solid #1a2638; color: #fff;
    padding: 7px 10px; border-radius: 6px; font-size: 13px; width: 100%; max-width: 360px;
  }
  input[type=text]:focus { outline: none; border-color: #2563eb; }
  .current { color: #7a93b0; font-size: 11px; }
  .preview-wrap { display: flex; gap: 10px; align-items: flex-start; margin-top: 6px; }
  .preview-img { width: 80px; height: 112px; object-fit: cover; border-radius: 6px;
    background: #0d1520; border: 1px solid #1a2638; }
  .preview-empty { width: 80px; height: 112px; display: flex; align-items: center;
    justify-content: center; background: #0d1520; border: 1px dashed #1a2638; border-radius: 6px;
    color: #3a5470; font-size: 10px; text-align: center; padding: 4px; }
  .preview-meta { color: #7a93b0; font-size: 10px; font-family: monospace; }
  .preview-meta .ok { color: #05c072; }
  .preview-meta .err { color: #ef4444; }
  .btn {
    padding: 7px 12px; border-radius: 6px; border: none;
    font-size: 12px; font-weight: 700; cursor: pointer;
  }
  .btn-primary { background: #2563eb; color: #fff; }
  .btn-secondary { background: #1a2638; color: #fff; font-size: 11px; padding: 5px 10px; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .saved { color: #05c072; font-weight: 700; font-size: 12px; }
</style>
</head>
<body>
<header>
  <h1>결측 ref 채우기</h1>
  <span class="count" id="count">로딩...</span>
  <input id="search" type="text" placeholder="카드 이름 또는 코드 검색 (예: 마마네 / BS2017)"
    style="background:#0d1520;border:1px solid #1a2638;color:#fff;padding:7px 12px;
           border-radius:8px;font-size:13px;width:280px;">
  <select id="prefix" style="background:#0d1520;border:1px solid #1a2638;color:#fff;
           padding:7px 10px;border-radius:8px;font-size:13px;">
    <option value="">전체</option>
    <option value="SMP">SM-P 프로모</option>
    <option value="SVP">SV-P 프로모</option>
    <option value="BS">정규 BS</option>
  </select>
  <span class="help">
    <a href="/" >← 검수 페이지</a>
    <a href="/scrydex-mapper" target="_blank">scrydex_mapper</a>
    <a href="https://scrydex.com/pokemon/cards" target="_blank">scrydex.com</a>
  </span>
</header>
<table id="t">
  <thead>
    <tr>
      <th width="220">이미지 (KO · EN)</th>
      <th>카드</th>
      <th>JP ref</th>
      <th>EN ref</th>
      <th width="100">저장</th>
    </tr>
  </thead>
  <tbody></tbody>
</table>

<script>
function esc(s) { return s == null ? '' : String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function scrydex(ref) {
  if (!ref || ref.startsWith('NO_')) return '';
  return `https://images.scrydex.com/pokemon/${encodeURIComponent(ref)}/medium`;
}

function thumb(src, fallbackSrc, label) {
  if (!src) return `<div class="col"><div class="none">없음</div><small>${label}</small></div>`;
  return `<div class="col">
    <img class="thumb" src="${esc(src)}" loading="lazy"
      onerror="this.onerror=null;${fallbackSrc ? `this.src='${esc(fallbackSrc)}';this.onerror=()=>{this.replaceWith(Object.assign(document.createElement('div'),{className:'none',textContent:'없음'}));}` : `this.replaceWith(Object.assign(document.createElement('div'),{className:'none',textContent:'깨짐'}))`}">
    <small>${label}</small>
  </div>`;
}

async function load() {
  const q = document.getElementById('search').value.trim();
  const prefix = document.getElementById('prefix').value;
  const params = new URLSearchParams();
  if (q) params.set('q', q);
  if (prefix) params.set('prefix', prefix);
  const res = await fetch('/missing-refs?' + params.toString());
  const rows = await res.json();
  document.getElementById('count').textContent = `${rows.length}장 결측 (최대 200)`;
  const tbody = document.querySelector('#t tbody');
  tbody.innerHTML = '';
  rows.forEach(r => {
    const tr = document.createElement('tr');
    const koSrc = `/local/cards/${r.card_id}_ko.png`;
    const enSrc = scrydex(r.en_scrydex_ref);
    tr.innerHTML = `
      <td>
        <div class="img-cell">
          ${thumb(koSrc, null, 'KO')}
          ${thumb(enSrc, null, 'EN')}
        </div>
      </td>
      <td>
        <div class="name">${esc(r.name)}</div>
        <div class="code">${esc(r.official_card_code)} · ${esc(r.collection_number) || '-'}</div>
        <div style="margin-top:6px;display:flex;gap:6px;">
          <button class="btn btn-secondary" onclick="navigator.clipboard.writeText('${esc(r.name)}');this.textContent='복사됨'">이름 복사</button>
          <a class="btn btn-secondary" href="https://scrydex.com/pokemon/cards" target="_blank">scrydex 열기</a>
        </div>
      </td>
      <td>
        <div class="current">현재: ${esc(r.jp_scrydex_ref) || '∅'}</div>
        <input type="text" class="jp ref-input" placeholder="ref 또는 scrydex URL 붙여넣기" value="${esc(r.jp_scrydex_ref)}">
        <div class="preview-wrap">
          <div class="preview-slot jp-preview"></div>
        </div>
      </td>
      <td>
        <div class="current">현재: ${esc(r.en_scrydex_ref) || '∅'}</div>
        <input type="text" class="en ref-input" placeholder="ref 또는 scrydex URL 붙여넣기" value="${esc(r.en_scrydex_ref)}">
        <div class="preview-wrap">
          <div class="preview-slot en-preview"></div>
        </div>
      </td>
      <td>
        <button class="btn btn-primary save-btn">저장</button>
        <span class="saved" style="display:none">✓</span>
      </td>
    `;
    const saveBtn = tr.querySelector('.save-btn');
    const savedBadge = tr.querySelector('.saved');

    // ref 정규화 — backend의 _normalize_ref와 동일 패턴 (preview 즉시 반영용).
    function normalizeRef(s) {
      if (!s) return '';
      s = s.trim();
      if (!s) return '';
      if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('/')) {
        s = s.replace(/\\/$/, '').split('/').pop() || '';
      }
      const q = s.indexOf('?'); if (q >= 0) s = s.slice(0, q);
      const h = s.indexOf('#'); if (h >= 0) s = s.slice(0, h);
      return s.trim();
    }

    function updatePreview(input, slot) {
      const raw = input.value;
      const ref = normalizeRef(raw);
      slot.innerHTML = '';
      if (!ref) {
        slot.innerHTML = '<div class="preview-empty">미입력</div>';
        return;
      }
      if (ref.startsWith('NO_')) {
        slot.innerHTML = `<div class="preview-empty">${esc(ref)}<br>(발매 없음)</div>`;
        return;
      }
      const img = new Image();
      img.className = 'preview-img';
      img.loading = 'lazy';
      img.src = `https://images.scrydex.com/pokemon/${encodeURIComponent(ref)}/medium`;
      const meta = document.createElement('div');
      meta.className = 'preview-meta';
      meta.innerHTML = `→ <span class="ok">${esc(ref)}</span>`;
      const wrap = document.createElement('div');
      wrap.style.display = 'flex';
      wrap.style.flexDirection = 'column';
      wrap.style.gap = '4px';
      wrap.appendChild(img);
      wrap.appendChild(meta);
      slot.appendChild(wrap);
      img.onerror = () => {
        img.replaceWith(Object.assign(document.createElement('div'),
          { className: 'preview-empty', textContent: 'scrydex 매칭 X' }));
        meta.innerHTML = `→ <span class="err">${esc(ref)}</span>`;
      };
    }

    const jpInput = tr.querySelector('.jp');
    const enInput = tr.querySelector('.en');
    const jpSlot = tr.querySelector('.jp-preview');
    const enSlot = tr.querySelector('.en-preview');
    const jpUpdate = () => updatePreview(jpInput, jpSlot);
    const enUpdate = () => updatePreview(enInput, enSlot);
    jpInput.addEventListener('input', jpUpdate);
    enInput.addEventListener('input', enUpdate);
    jpUpdate();  // 초기 렌더
    enUpdate();

    saveBtn.addEventListener('click', async () => {
      const jp = tr.querySelector('.jp').value.trim();
      const en = tr.querySelector('.en').value.trim();
      saveBtn.disabled = true;
      saveBtn.textContent = '저장 중...';
      try {
        const res = await fetch('/update-ref', {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({card_id: r.card_id, jp_scrydex_ref: jp, en_scrydex_ref: en}),
        });
        const j = await res.json();
        if (res.ok && j.updated >= 1) {
          savedBadge.style.display = 'inline';
          saveBtn.textContent = '저장됨';
          setTimeout(() => { saveBtn.disabled = false; saveBtn.textContent = '저장'; savedBadge.style.display = 'none'; }, 2000);
        } else {
          saveBtn.textContent = '실패';
          alert('실패: ' + (j.detail || JSON.stringify(j)));
          setTimeout(() => { saveBtn.disabled = false; saveBtn.textContent = '저장'; }, 1500);
        }
      } catch (e) {
        saveBtn.textContent = '에러';
        alert(e);
      }
    });
    tbody.appendChild(tr);
  });
}

let searchTimer = null;
document.getElementById('search').addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(load, 300);
});
document.getElementById('prefix').addEventListener('change', load);

load();
</script>
</body>
</html>
"""


@app.get("/missing", response_class=HTMLResponse)
def missing_page() -> HTMLResponse:
    return HTMLResponse(MISSING_HTML)


@app.get("/scrydex-mapper", response_class=HTMLResponse)
def scrydex_mapper() -> HTMLResponse:
    """기존 scanner/data/scrydex_mapper.html 열어주기."""
    p = ROOT.parent / "data" / "scrydex_mapper.html"
    if not p.exists():
        raise HTTPException(404, "scrydex_mapper.html 없음")
    return HTMLResponse(p.read_text())


def main() -> int:
    if not STAGING.exists():
        print(f"staging 없음: {STAGING}", file=sys.stderr)
        print("→ crawl_pokemoncard_promos.py 먼저 실행", file=sys.stderr)
        return 1
    print("검수 서버 시작 — http://localhost:8084")
    uvicorn.run(app, host="127.0.0.1", port=8084, log_level="warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
