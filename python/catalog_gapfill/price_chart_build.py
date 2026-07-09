"""2단계 가격/차트 검수 (재작성) — 관리자 preview API 기반. 임의 공식 금지.
 각 mapping_verified 카드를 POST /api/admin/cards/preview 로 호출 →
 globalPriceService.previewCardAdd / calculateKoEstimatedForCard (실제 추가와 동일 모델·DB write 0)
 응답(koEstimated/jpRawKrw/enRawKrw/anchorSource/priceDisclaimer/chart)만 사용해 화면 생성.

 환경변수:
   PREVIEW_URL  예: http://localhost:8080/api/admin/cards/preview  (또는 prod)
   ADMIN_AUTH   Authorization 헤더 전체값 (예 'Bearer xxx'). ★로그 출력 안 함.
 실행:  PREVIEW_URL=... ADMIN_AUTH=... python price_chart_build.py [mapping_verified_*.json]
 ※ DB write 0 (preview는 transient). final_review.html / 원본 미변경.
"""
import json, os, sys, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor, as_completed

P = os.path.dirname(os.path.abspath(__file__))
URL = os.environ.get('PREVIEW_URL')
AUTH = os.environ.get('ADMIN_AUTH')
SCRY_IMG = "https://images.scrydex.com/pokemon/{}/medium"
MVPATH = sys.argv[1] if len(sys.argv) > 1 else '/Users/fury/Downloads/mapping_verified_2026-06-19094110.json'

if not URL:
    print("PREVIEW_URL 미설정. 예:")
    print("  PREVIEW_URL=http://localhost:8080/api/admin/cards/preview ADMIN_AUTH='Bearer <token>' python price_chart_build.py")
    sys.exit(1)

MV = json.load(open(MVPATH))
prev = {r['code']: r for r in json.load(open(os.path.join(P, 'jp_match_preview.json')))}


def call_preview(card):
    body = json.dumps({'rarityCode': card.get('ko_rarity'), 'productId': card.get('productId'),
                       'enScrydexRef': card.get('enScrydexRef'), 'jpScrydexRef': card.get('jpScrydexRef')}).encode()
    req = urllib.request.Request(URL, data=body, method='POST',
                                 headers={'Content-Type': 'application/json', **({'Authorization': AUTH} if AUTH else {})})
    try:
        raw = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'ignore')
        j = json.loads(raw)
        d = j.get('data', j)   # ReturnData.success → {data:{...}} 또는 직접
        return card['code'], d, None
    except urllib.error.HTTPError as e:
        return card['code'], None, f"HTTP {e.code} {e.read()[:120].decode('utf-8','ignore')}"
    except Exception as e:
        return card['code'], None, str(e)


print(f"preview 호출 {len(MV)}장 → {URL}", flush=True)
res = {}
errs = []
with ThreadPoolExecutor(max_workers=6) as ex:
    futs = [ex.submit(call_preview, c) for c in MV]
    done = 0
    for f in as_completed(futs):
        code, d, err = f.result()
        if err:
            errs.append((code, err))
        else:
            res[code] = d
        done += 1
        if done % 15 == 0:
            print(f"  {done}/{len(MV)}", flush=True)

print(f"성공 {len(res)} / 실패 {len(errs)}")
for c, e in errs[:8]:
    print(f"   ERR {c}: {e}")
if not res:
    print("★ preview 응답 0 — 백엔드/URL/인증 확인. 화면 생성 중단.")
    sys.exit(1)

rows = []
for c in MV:
    d = res.get(c['code'])
    if not d:
        continue
    ko = d.get('koEstimated')
    jpkrw = d.get('jpRawKrw')
    enkrw = d.get('enRawKrw')
    chart = d.get('chart') or []
    if ko is None or ko == 0:
        pst = 'PRICE_MISSING'
    elif ko > 5_000_000:
        pst = 'PRICE_OUTLIER'
    elif jpkrw and enkrw:
        pst = 'PRICE_OK'
    else:
        pst = 'PRICE_NEEDS_REVIEW'
    cst = 'CHART_OK' if len(chart) >= 2 else 'CHART_MISSING'
    pr = prev.get(c['code'], {})
    rows.append({
        **{k: c.get(k) for k in ('code', 'ko_name', 'ko_set', 'ko_rarity', 'productId', 'officialCardCode', 'jpScrydexRef', 'enScrydexRef')},
        'ko_img': pr.get('ko_image_url', ''), 'jp_img': SCRY_IMG.format(c['jpScrydexRef']) if c.get('jpScrydexRef') else '',
        'en_img': SCRY_IMG.format(c['enScrydexRef']) if c.get('enScrydexRef') else '',
        'koEstimated': ko, 'jpRawKrw': jpkrw, 'enRawKrw': enkrw, 'anchorSource': d.get('anchorSource'),
        'isChase': d.get('isChaseCandidate'), 'disclaimer': d.get('priceDisclaimer'), 'chartProjected': d.get('chartProjected'),
        'chart': [{'d': p.get('date') or p.get('tradedAt'), 'p': p.get('price')} for p in chart],
        'price_status': pst, 'chart_status': cst,
    })

print("price_status:", dict(collections.Counter(r['price_status'] for r in rows)))
print("chart_status:", dict(collections.Counter(r['chart_status'] for r in rows)))

DATA = json.dumps(rows, ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang=ko><head><meta charset=utf-8><title>2단계: 가격/차트 검수 (관리자 preview 기반)</title><style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}body{margin:0;background:#f4f5f7;font-size:13px}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:9;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.tbtn{padding:5px 11px;border:none;border-radius:6px;cursor:pointer;font-weight:700;font-size:12px}select{padding:5px 8px;border:1px solid #ccc;border-radius:6px}
.grid{padding:14px;display:grid;gap:12px;max-width:1180px;margin:0 auto}
.card{background:#fff;border:2px solid #e0e0e0;border-radius:12px;padding:12px}
.card.dok{box-shadow:0 0 0 3px #66bb6a inset}.card.dhold{box-shadow:0 0 0 3px #ffa726 inset}.card.derr{box-shadow:0 0 0 3px #ef5350 inset;opacity:.6}
.hd{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:8px}.nm{font-size:15px;font-weight:800}
.row{display:flex;gap:12px;flex-wrap:wrap}.imgs img{height:140px;object-fit:contain;background:#fff;border:1px solid #eee;border-radius:6px;margin-right:6px}
.info{flex:1;min-width:300px;font-size:12px;line-height:1.7}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:10.5px;font-weight:800}
.PRICE_OK,.CHART_OK{background:#e8f5e9;color:#2e7d32}.PRICE_MISSING,.CHART_MISSING{background:#eceff1;color:#607d8b}.PRICE_OUTLIER{background:#ffebee;color:#c62828}.PRICE_NEEDS_REVIEW{background:#fff8e1;color:#f57f17}.rar{background:#ede7f6;color:#5e35b1}
.refs{font-family:ui-monospace,Menlo;font-size:11px;color:#1565c0}.muted{color:#888}.est{color:#c62828;font-weight:800;font-size:14px}.won{font-weight:700}
.decbar{margin-top:9px;display:flex;gap:6px;flex-wrap:wrap}.decbar button{border:1px solid #ccc;background:#fff;border-radius:6px;padding:4px 10px;cursor:pointer;font-weight:700;font-size:12px}
.decbar button.on.ok{background:#2e7d32;color:#fff}.decbar button.on.hd{background:#e65100;color:#fff}.decbar button.on.er{background:#c62828;color:#fff}.decbar button.on.rc{background:#1565c0;color:#fff}
</style></head><body>
<header><b>2단계: 가격/차트 검수</b> <span class=muted>관리자 preview API 기반 · DB write 0 · 실제 추가 모델과 동일</span>
<select id=fps onchange=render()><option value="">가격상태 전체</option><option>PRICE_OK</option><option>PRICE_NEEDS_REVIEW</option><option>PRICE_OUTLIER</option><option>PRICE_MISSING</option></select>
<select id=fd onchange=render()><option value="">검수 전체</option><option value=none>미정</option><option value=price_ok>가격확인</option><option value=price_hold>가격보류</option><option value=price_err>가격오류</option><option value=recalc>재계산요청</option></select>
<button class=tbtn style=background:#2e7d32;color:#fff onclick="exp('price_ok')">가격확인 목록 내보내기</button>
<button class=tbtn style=background:#9e9e9e;color:#fff onclick="if(confirm('가격검수 상태 초기화?')){localStorage.removeItem('price_dec2');location.reload()}">상태 초기화</button>
<span style=margin-left:auto;font-weight:700 id=st></span></header>
<div class=grid id=grid></div><script>
const DATA=__DATA__;const DEC=JSON.parse(localStorage.getItem('price_dec2')||'{}');
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
const won=n=>n==null?'—':n.toLocaleString()+'원';
function sv(d){const pp=(d||[]).filter(x=>x.p!=null);if(pp.length<2)return '<span class=muted>차트없음</span>';const v=pp.map(x=>x.p),mn=Math.min(...v),mx=Math.max(...v),w=260,h=46;
 const pts=pp.map((x,i)=>`${(i/(pp.length-1)*w).toFixed(1)},${(h-(mx==mn?h/2:(x.p-mn)/(mx-mn)*h)).toFixed(1)}`).join(' ');
 return `<svg width=${w} height=${h} style="background:#fafafa;border-radius:4px"><polyline points="${pts}" fill=none stroke=#c62828 stroke-width=1.5/></svg> <span class=muted>${pp.length}p · ${won(mn)}~${won(mx)}</span>`;}
function setD(code,st){const d=DEC[code]||{};d.state=d.state==st?null:st;DEC[code]=d;localStorage.setItem('price_dec2',JSON.stringify(DEC));render();}
function exp(st){const o=DATA.filter(c=>(DEC[c.code]||{}).state==st);if(!o.length){alert('없음');return;}
 const b=new Blob([JSON.stringify(o.map(c=>({code:c.code,ko_name:c.ko_name,officialCardCode:c.officialCardCode,productId:c.productId,jpScrydexRef:c.jpScrydexRef,enScrydexRef:c.enScrydexRef,koEstimated:c.koEstimated,price_status:c.price_status,state:st})),null,1)],{type:'application/json'});
 const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='price_'+st+'_'+new Date().toISOString().slice(0,10)+'.json';a.click();alert(st+' '+o.length+'건');}
function vis(){return DATA.filter(c=>(!fps.value||c.price_status==fps.value)&&(!fd.value||(fd.value=='none'?!(DEC[c.code]||{}).state:(DEC[c.code]||{}).state==fd.value)));}
function card(c){const ds=(DEC[c.code]||{}).state;const cl=ds=='price_ok'?'dok':ds=='price_hold'?'dhold':ds=='price_err'?'derr':'';
 return `<div class="card ${cl}"><div class=hd><span class=nm>${esc(c.ko_name)}</span><span class="badge rar">${esc(c.ko_rarity)}</span><span class="badge ${c.price_status}">${c.price_status}</span><span class="badge ${c.chart_status}">${c.chart_status}</span>${c.isChase?'<span class="badge" style="background:#fff3e0;color:#e65100">CHASE</span>':''}<span class=refs>${esc(c.code)}</span></div>
 <div class=row><div class=imgs><img src="${esc(c.ko_img)}" title=KO><img src="${esc(c.jp_img)}" title=JP><img src="${esc(c.en_img)}" title=EN></div>
 <div class=info><div>${esc(c.ko_set)} · <span class=refs>${esc(c.officialCardCode)}</span> · ${esc(c.ko_rarity)}</div>
  <div class=refs>JP ${esc(c.jpScrydexRef)} · EN ${esc(c.enScrydexRef||'—')} · product ${esc(c.productId)}</div>
  <div>관리자 preview 예상가: <span class=est>${won(c.koEstimated)}</span> <span class=muted>앵커 ${esc(c.anchorSource||'—')}</span></div>
  <div>JP raw <span class=won>${won(c.jpRawKrw)}</span> · EN raw <span class=won>${won(c.enRawKrw)}</span></div>
  <div class=muted>${esc(c.disclaimer||'')}</div>
  <div>투영 KO 차트(${c.chartProjected?'JP/EN 투영':'실거래'}): ${sv(c.chart)}</div>
 </div></div>
 <div class=decbar><span class=muted style=font-size:11px>2단계 가격검수:</span>
  <button class="ok ${ds=='price_ok'?'on':''}" onclick="setD('${c.code}','price_ok')">✓ 가격확인</button>
  <button class="hd ${ds=='price_hold'?'on':''}" onclick="setD('${c.code}','price_hold')">⏸ 가격보류</button>
  <button class="er ${ds=='price_err'?'on':''}" onclick="setD('${c.code}','price_err')">✗ 가격오류</button>
  <button class="rc ${ds=='recalc'?'on':''}" onclick="setD('${c.code}','recalc')">↻ 재계산요청</button></div></div>`;}
function render(){const v=vis();grid.innerHTML=v.map(card).join('');
 const ok=DATA.filter(c=>(DEC[c.code]||{}).state=='price_ok').length;
 st.textContent=`보임 ${v.length}/${DATA.length} | ✓가격확인 ${ok} | OK ${DATA.filter(c=>c.price_status=='PRICE_OK').length} REVIEW ${DATA.filter(c=>c.price_status=='PRICE_NEEDS_REVIEW').length} OUTLIER ${DATA.filter(c=>c.price_status=='PRICE_OUTLIER').length} MISSING ${DATA.filter(c=>c.price_status=='PRICE_MISSING').length}`;}
render();</script></body></html>'''
open(os.path.join(P, 'price_chart_review.html'), 'w').write(TPL.replace('__DATA__', DATA))
print("→ price_chart_review.html (관리자 preview 기반) 생성 완료")
