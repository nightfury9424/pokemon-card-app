"""data/raw_eval 검수용 미니 웹 서버.

브라우저에서 400장 격자 보기. 클릭으로 삭제 mark → 확정 시 일괄 삭제.
선택 사항: 검수 끝나면 남은 파일을 data/eval/로 자동 이동.

실행:
  cd scanner/training
  /Users/fury/miniconda3/envs/scanner_v2/bin/python review_server.py
브라우저: http://localhost:8083
"""

from __future__ import annotations
import shutil
import sys
from pathlib import Path
from typing import List

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

ROOT = Path(__file__).parent
RAW_DIR = ROOT / "data" / "raw_eval"
EVAL_DIR = ROOT / "data" / "eval"
TRASH_DIR = ROOT / "data" / "_trash"

app = FastAPI()
TRASH_DIR.mkdir(parents=True, exist_ok=True)
EVAL_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/img", StaticFiles(directory=str(RAW_DIR)), name="img")


class DeletePayload(BaseModel):
    filenames: List[str]


class MovePayload(BaseModel):
    pass  # 남은 파일 전체를 eval/로 이동


def safe_path(name: str) -> Path:
    """경로 탈출 방지 — 단순 파일명만 허용."""
    if "/" in name or ".." in name or "\\" in name:
        raise HTTPException(400, "invalid filename")
    p = RAW_DIR / name
    if not p.exists() or not p.is_file():
        raise HTTPException(404, "not found")
    return p


@app.get("/list")
def list_files() -> JSONResponse:
    files = sorted(p.name for p in RAW_DIR.glob("*.jpg"))
    return JSONResponse({"files": files, "total": len(files)})


@app.post("/delete")
def delete(payload: DeletePayload) -> JSONResponse:
    """선택된 파일을 _trash/로 이동 (즉시 삭제 X, 안전)."""
    moved = []
    for name in payload.filenames:
        p = safe_path(name)
        dst = TRASH_DIR / name
        if dst.exists():
            dst.unlink()
        shutil.move(str(p), str(dst))
        moved.append(name)
    return JSONResponse({"moved_to_trash": len(moved), "trash_dir": str(TRASH_DIR)})


@app.post("/keep")
def keep_selected(payload: DeletePayload) -> JSONResponse:
    """선택된 파일만 eval/로 이동. 나머지는 _trash/로."""
    keep_set = set(payload.filenames)
    moved_keep = 0
    moved_trash = 0
    for p in list(RAW_DIR.glob("*.jpg")):
        if p.name in keep_set:
            dst = EVAL_DIR / p.name
            if dst.exists():
                dst.unlink()
            shutil.move(str(p), str(dst))
            moved_keep += 1
        else:
            dst = TRASH_DIR / p.name
            if dst.exists():
                dst.unlink()
            shutil.move(str(p), str(dst))
            moved_trash += 1
    return JSONResponse({
        "moved_to_eval": moved_keep,
        "moved_to_trash": moved_trash,
        "eval_dir": str(EVAL_DIR),
        "trash_dir": str(TRASH_DIR),
    })


@app.post("/move-to-eval")
def move_to_eval(_: MovePayload) -> JSONResponse:
    """raw_eval 남아있는 모든 파일 → eval/."""
    moved = 0
    for p in RAW_DIR.glob("*.jpg"):
        shutil.move(str(p), str(EVAL_DIR / p.name))
        moved += 1
    return JSONResponse({"moved_to_eval": moved, "eval_dir": str(EVAL_DIR)})


HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>크롤링 검수</title>
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
  .marked-count { color: #ef4444; font-weight: 700; }
  .btn {
    padding: 8px 14px; border-radius: 8px; border: none;
    font-size: 13px; font-weight: 600; cursor: pointer;
  }
  .btn-danger { background: #ef4444; color: #fff; }
  .btn-success { background: #05c072; color: #fff; }
  .btn-secondary { background: #1a2638; color: #fff; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .help { color: #7a93b0; font-size: 12px; margin-left: auto; }
  #grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 8px; padding: 12px;
  }
  .card {
    position: relative; aspect-ratio: 3/4; overflow: hidden;
    background: #1a2638; border-radius: 8px; cursor: pointer;
    border: 3px solid transparent; transition: border-color 0.1s;
  }
  .card img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .card.marked { border-color: #05c072; }
  .card.marked::after {
    content: '✓'; position: absolute; top: 4px; right: 4px;
    background: #05c072; color: #fff; width: 22px; height: 22px;
    border-radius: 50%; display: flex; align-items: center; justify-content: center;
    font-size: 14px; font-weight: 800;
  }
  .name { position: absolute; bottom: 0; left: 0; right: 0;
    background: linear-gradient(transparent, rgba(0,0,0,0.7));
    padding: 16px 6px 4px; font-size: 10px; color: #fff;
    text-overflow: ellipsis; overflow: hidden; white-space: nowrap;
  }
  #status { padding: 16px 20px; color: #05c072; font-weight: 600; }
</style>
</head>
<body>
<header>
  <h1>크롤링 검수</h1>
  <span class="count" id="count">로딩...</span>
  <button class="btn btn-success" id="keep-btn" disabled>
    <span id="keep-label">keep 선택 안 됨</span>
  </button>
  <button class="btn btn-secondary" id="move-btn">전부 _trash/로 (포기)</button>
  <span class="help">
    클릭 = 이거 keep. Shift+클릭 = 범위. "A" = 전부, "U" = 전부 해제.
    버튼 누르면 선택한 거만 eval/로, 나머지는 _trash/.
  </span>
</header>
<div id="grid"></div>
<div id="status"></div>

<script>
const grid = document.getElementById('grid');
const countEl = document.getElementById('count');
const keepBtn = document.getElementById('keep-btn');
const keepLabel = document.getElementById('keep-label');
const moveBtn = document.getElementById('move-btn');
const status = document.getElementById('status');
let files = [];
let lastClicked = -1;

async function load() {
  const res = await fetch('/list');
  const j = await res.json();
  files = j.files;
  renderGrid();
}

function renderGrid() {
  grid.innerHTML = '';
  countEl.textContent = `${files.length}장 (체크된: 0)`;
  files.forEach((name, i) => {
    const card = document.createElement('div');
    card.className = 'card';
    card.dataset.idx = i;
    card.innerHTML = `<img src="/img/${name}" loading="lazy"><span class="name">${name}</span>`;
    card.addEventListener('click', (e) => onCardClick(i, e.shiftKey));
    grid.appendChild(card);
  });
  updateDelButton();
}

function onCardClick(idx, shift) {
  const cards = grid.children;
  const target = cards[idx];
  const wasMarked = target.classList.contains('marked');
  if (shift && lastClicked >= 0) {
    const [s, e] = [Math.min(lastClicked, idx), Math.max(lastClicked, idx)];
    const targetState = !wasMarked;
    for (let i = s; i <= e; i++) {
      cards[i].classList.toggle('marked', targetState);
    }
  } else {
    target.classList.toggle('marked', !wasMarked);
  }
  lastClicked = idx;
  updateDelButton();
}

function updateDelButton() {
  const marked = grid.querySelectorAll('.card.marked').length;
  countEl.textContent = `${files.length}장 (keep 체크: ${marked})`;
  keepBtn.disabled = marked === 0;
  keepLabel.textContent = marked === 0 ? 'keep 선택 안 됨'
    : `${marked}장만 eval/로, 나머지 ${files.length - marked}장 _trash/`;
}

keepBtn.addEventListener('click', async () => {
  const marked = [...grid.querySelectorAll('.card.marked')]
    .map(c => files[parseInt(c.dataset.idx)]);
  const drop = files.length - marked.length;
  if (!confirm(`${marked.length}장만 eval/로 이동, ${drop}장은 _trash/로. 계속?`)) return;
  const res = await fetch('/keep', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({filenames: marked}),
  });
  const j = await res.json();
  status.textContent = `eval/로 ${j.moved_to_eval}장, _trash/로 ${j.moved_to_trash}장 이동 완료.`;
  files = [];
  renderGrid();
});

moveBtn.addEventListener('click', async () => {
  if (!confirm(`raw_eval 전부(${files.length}장) _trash/로 보냅니다. 검수 포기?`)) return;
  const res = await fetch('/delete', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({filenames: files}),
  });
  const j = await res.json();
  status.textContent = `${j.moved_to_trash}장 _trash/로 이동 완료.`;
  files = [];
  renderGrid();
});

document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT') return;
  if (e.key === 'a' || e.key === 'A') {
    [...grid.children].forEach(c => c.classList.add('marked'));
    updateDelButton();
  } else if (e.key === 'u' || e.key === 'U') {
    [...grid.children].forEach(c => c.classList.remove('marked'));
    updateDelButton();
  }
});

load();
</script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    return HTMLResponse(HTML)


def main() -> int:
    if not RAW_DIR.exists() or not list(RAW_DIR.glob("*.jpg")):
        print(f"raw_eval 비어있음: {RAW_DIR}", file=sys.stderr)
        print("→ crawl_eval_set.py 먼저 실행", file=sys.stderr)
        return 1
    print(f"검수 서버 시작 — 브라우저: http://localhost:8083")
    print(f"폴더: {RAW_DIR}")
    print(f"삭제된 파일 → {TRASH_DIR} (복구 가능)")
    uvicorn.run(app, host="127.0.0.1", port=8083, log_level="warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
