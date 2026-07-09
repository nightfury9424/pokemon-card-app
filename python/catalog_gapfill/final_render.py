"""검수 HTML — [KO][JP][EN][기존prod] + 관리자 DTO 필드 preview + 준비상태.
 목적=사람이 눈으로 80장 ADD 검수. 실행/POST/스크립트 아님. final_add_payload_clean.json 은 보조데이터.
 준비상태: ADMIN_READY / PRODUCT_MISSING / JP_REF_MISSING / DUP_OFFICIAL_CODE / DUP_JP_REF / EXCLUDE_* / DEFER_RR / NEEDS_TRAINER
"""
import json, csv, os, re, collections

P = os.path.dirname(os.path.abspath(__file__))
SCRY = "https://images.scrydex.com/pokemon/{}/medium"
DTO = ['type', 'name', 'productId', 'rarityCode', 'collectionNumber', 'superType', 'subType', 'officialCardCode', 'jpScrydexRef', 'enScrydexRef']


def real(x):
    return bool(x) and not str(x).startswith('NO_')


def nset(s):
    return re.sub(r'[\s「」（）()【】]', '', (s or '')).lower()


# prod 역조회/검증 소스
prod_by_jp, prod_by_en, prod_prod, prod_codes, prod_jp, prod_product_ids = {}, {}, {}, set(), set(), set()
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        c = (r.get('official_card_code') or '').strip()
        j = (r.get('jp_scrydex_ref') or '').strip()
        if c:
            prod_codes.add(c)
        if real(j):
            prod_by_jp[j] = r; prod_jp.add(j)
        if real(r.get('en_scrydex_ref')):
            prod_by_en[r['en_scrydex_ref'].strip()] = r
prod_name = {}
with open(os.path.join(P, 'prod_products_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        prod_prod[r['product_id']] = r
        prod_product_ids.add(r['product_id'])
        k = nset(r['name'])
        if r.get('language', 'KO') == 'KO' or k not in prod_name:
            prod_name[k] = r

SRC = os.environ.get('GAPFILL_SRC', 'jp_match_preview.json')
OUT = os.environ.get('GAPFILL_OUT', 'final_review.html')
data = json.load(open(os.path.join(P, SRC)))
out = []
for r in data:
    batch = r.get('batch', 'PRIMARY')
    tab = 'DEFER_RR' if batch == 'DEFER_RR' else ('NEEDS_TRAINER' if r.get('needs_manual') else 'PRIMARY')
    prod = prod_name.get(nset(r['ko_set_name']))
    pid = prod['product_id'] if prod else None
    super_type = 'TRAINER' if '서포트' in (r.get('type') or '') else 'POKEMON'
    en_ref = r.get('en_ref') if r.get('en_conf') == 'EN_MATCH_EXACT' else None
    admin = {'type': 'KO', 'name': r['ko_name'], 'productId': pid, 'rarityCode': r['ko_rarity'],
             'collectionNumber': r['ko_collection_no'], 'superType': super_type, 'subType': None,
             'officialCardCode': r['code'], 'jpScrydexRef': r.get('jp_ref'), 'enScrydexRef': en_ref}
    # 준비상태
    v = r.get('verdict')
    if v in ('EXCLUDE_JP', 'EXCLUDE_EN'):
        status = v
    elif tab == 'DEFER_RR':
        status = 'DEFER_RR'
    elif tab == 'NEEDS_TRAINER':
        status = 'NEEDS_TRAINER'
    elif not pid:
        status = 'PRODUCT_MISSING'
    elif not real(r.get('jp_ref')):
        status = 'JP_REF_MISSING'
    elif r['code'] in prod_codes:
        status = 'DUP_OFFICIAL_CODE'
    elif r.get('jp_ref') in prod_jp:
        status = 'DUP_JP_REF'
    else:
        status = 'ADMIN_READY'
    # 기존 prod (EXCLUDE)
    e = prod_by_jp.get(r.get('jp_ref')) if v == 'EXCLUDE_JP' else (prod_by_en.get(r.get('en_ref')) if v == 'EXCLUDE_EN' else None)
    ex = None
    if e:
        pp = prod_prod.get(e['product_id'], {})
        ex = {'card_id': e['card_id'], 'name': e['name'], 'product': pp.get('name', e['product_id']), 'productId': e['product_id'],
              'num': e['collection_number'], 'rarity': e['rarity_code'], 'jp_ref': e['jp_scrydex_ref'], 'en_ref': e['en_scrydex_ref'],
              'img': SCRY.format(e['en_scrydex_ref']) if real(e['en_scrydex_ref']) else (SCRY.format(e['jp_scrydex_ref']) if real(e['jp_scrydex_ref']) else '')}
    out.append({
        'tab': tab, 'status': status, 'verdict': v,
        'code': r['code'], 'ko_name': r['ko_name'], 'ko_set': r['ko_set_name'], 'ko_no': r['ko_collection_no'],
        'ko_rarity': r['ko_rarity'], 'type': r.get('type', ''), 'ko_img': r['ko_image_url'], 'ko_detail': r['ko_detail_url'],
        'jp_ref': r.get('jp_ref'), 'jp_img': r.get('jp_image_url'), 'jp_name': r.get('jp_name', ''),
        'jp_conf': r.get('jp_conf'), 'jp_reason': r.get('match_reason', ''),
        'en_ref': r.get('en_ref'), 'en_img': r.get('en_image_url'), 'en_name': r.get('en_name', ''),
        'en_conf': r.get('en_conf', 'EN_UNRESOLVED'), 'en_reason': r.get('en_reason', ''), 'en_candidates': r.get('en_candidates'),
        'admin': admin, 'ex': ex,
        'series': {'productId': r.get('series_productId'), 'source': r.get('series_source'),
                   'jp_set': r.get('series_jp_set'), 'jp_conf': r.get('series_jp_conf'), 'jp_dist': r.get('series_jp_dist'),
                   'en_set': r.get('series_en_set'), 'en_conf': r.get('series_en_conf'), 'en_dist': r.get('series_en_dist')},
    })

DATA = json.dumps(out, ensure_ascii=False)
DTOJS = json.dumps(DTO)
TPL = r'''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>KO 갭 추가후보 검수</title>
<style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}body{margin:0;background:#f4f5f7;font-size:13px;color:#1a1a1a}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:10;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.tabs{display:flex;gap:8px;margin-bottom:8px}.tab{padding:6px 14px;border-radius:20px;border:1px solid #ccc;background:#fff;cursor:pointer;font-weight:700}.tab.on{background:#2962ff;color:#fff;border-color:#2962ff}
.bar{display:flex;gap:7px;align-items:center;flex-wrap:wrap}select,input{padding:5px 8px;border:1px solid #ccc;border-radius:6px;font-size:13px}
.seg{display:inline-flex;border:1px solid #ccc;border-radius:6px;overflow:hidden}.seg button{border:none;background:#fff;padding:5px 10px;cursor:pointer;font-weight:600}.seg button.on{background:#37474f;color:#fff}
.stat{margin-left:auto;font-weight:700}.grid{padding:14px;display:grid;grid-template-columns:1fr;gap:12px;max-width:1180px;margin:0 auto}
.card{background:#fff;border:2px solid #e0e0e0;border-radius:12px;padding:12px}.card.ADD{border-color:#66bb6a}.card.EXCLUDE_JP,.card.EXCLUDE_EN{border-color:#ef9a9a;background:#fff7f6}
.hd{display:flex;align-items:center;gap:8px;margin-bottom:8px;flex-wrap:wrap}.hd .nm{font-size:16px;font-weight:800}
.cols{display:flex;gap:10px;flex-wrap:wrap}.col{flex:1;min-width:188px;border:1px solid #eee;border-radius:8px;padding:8px}
.col.ko{background:#f1f6ff}.col.jp{background:#fff8f1}.col.en{background:#f3fbf3}.col.ex{background:#fbe9e7;border-color:#ef9a9a}
.col .lbl{font-size:11px;font-weight:800;color:#555;margin-bottom:5px}.col img{width:100%;max-width:148px;height:200px;object-fit:contain;background:#fff;border-radius:6px;display:block;margin:0 auto 6px}
.pend{height:200px;display:flex;align-items:center;justify-content:center;background:#fafafa;border:1px dashed #bbb;border-radius:6px;color:#999;font-weight:700;text-align:center;padding:6px;margin-bottom:6px;font-size:11px}
.id{font-size:12px;line-height:1.5}.refs{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:#1565c0;word-break:break-all}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:10.5px;font-weight:800}
.ADD,.ADMIN_READY{background:#e8f5e9;color:#2e7d32}.EXCLUDE_JP,.EXCLUDE_EN,.DUP_OFFICIAL_CODE,.DUP_JP_REF{background:#ffebee;color:#c62828}
.PRODUCT_MISSING,.JP_REF_MISSING,.NEEDS_TRAINER{background:#fff3e0;color:#e65100}.DEFER_RR{background:#eceff1;color:#546e7a}
.rar{background:#ede7f6;color:#5e35b1}.code{background:#eceff1;color:#455a64;font-family:ui-monospace,Menlo}
.ok{background:#e8f5e9;color:#2e7d32}.amb{background:#fff8e1;color:#f57f17}.un{background:#eceff1;color:#789}
.muted{color:#888}.lnk{color:#1565c0;text-decoration:none}.reason{font-size:10.5px;color:#777;margin-top:3px}
.admin{margin-top:10px;border-top:1px dashed #ddd;padding-top:8px}.admin .t{font-size:11px;font-weight:800;color:#555;margin-bottom:5px}
.dto{display:flex;flex-wrap:wrap;gap:4px 14px}.dto div{font-size:11.5px}.dto .k{color:#888}.dto .v{font-family:ui-monospace,Menlo;color:#222}.dto .miss{color:#c62828;font-weight:700}
.decbar{margin-top:9px;display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.decbar button{border:1px solid #ccc;background:#fff;border-radius:6px;padding:4px 11px;cursor:pointer;font-weight:700;font-size:12px}
.decbar button.on.ap{background:#2e7d32;color:#fff;border-color:#2e7d32}.decbar button.on.rj{background:#c62828;color:#fff;border-color:#c62828}
.decbar button.on.rr{background:#e65100;color:#fff;border-color:#e65100}.decbar button.on.hd{background:#546e7a;color:#fff;border-color:#546e7a}
.card.dap{box-shadow:0 0 0 3px #66bb6a inset}.card.drj{box-shadow:0 0 0 3px #ef5350 inset;opacity:.55}.card.drr{box-shadow:0 0 0 3px #ffa726 inset}
.encand{cursor:pointer;border:2px solid #ccc;border-radius:5px}.encand.pick{border-color:#2e7d32;box-shadow:0 0 0 2px #66bb6a}
.tbtn{padding:5px 11px;border:none;border-radius:6px;cursor:pointer;font-weight:700;font-size:12px}
</style></head><body>
<header><div class="tabs" id="tabs"></div>
<div class="bar"><div class="seg" id="seg"><button class="on" data-v="" onclick="seg('')">전체</button><button data-v="ADD" onclick="seg('ADD')">ADD</button><button data-v="EXCLUDE" onclick="seg('EXCLUDE')">EXCLUDE</button></div>
 <select id="fstat" onchange="render()"></select><select id="fen" onchange="render()"><option value="">EN 전체</option><option>EN_MATCH_EXACT</option><option>EN_MATCH_VISUAL</option><option>EN_MATCH_AMBIGUOUS</option><option>EN_UNRESOLVED</option></select>
 <select id="fset" onchange="render()"></select><select id="frar" onchange="render()"></select>
 <input id="fq" placeholder="이름검색" oninput="render()" style="width:110px">
 <select id="fdec" onchange="render()"><option value="">검수 전체</option><option value="none">미정</option><option value="mapping_verified">매핑확인</option><option value="reroll_requested">다시찾기</option><option value="mapping_rejected">제외</option><option value="hold">보류</option></select>
 <button class="tbtn" style="background:#2e7d32;color:#fff" onclick="expDec('mapping_verified')">매핑확인 목록 내보내기</button>
 <button class="tbtn" style="background:#e65100;color:#fff" onclick="expDec('reroll_requested')">다시찾기 목록 내보내기</button>
 <button class="tbtn" style="background:#9e9e9e;color:#fff" onclick="if(confirm('검수상태 전부 초기화? (데이터 파일은 안 건드림)')){localStorage.removeItem('gapfill_dec');location.reload();}">상태 초기화</button>
 <span class="stat" id="stat"></span></div>
<div style="font-size:11.5px;color:#555;margin-top:6px;line-height:1.6">검수 가이드 — <b style="color:#2e7d32">✓ 매핑확인</b> KO·JP·EN 같은 카드(맞음→다음단계) &nbsp;·&nbsp; <b style="color:#e65100">↻ 다시찾기</b> 후보가 틀림 → 새 후보 탐색요청(<u>현재후보 보존</u>) &nbsp;·&nbsp; <b style="color:#c62828">✗ 제외</b> 이 카드 자체를 후보에서 뺌(리롤 안함) &nbsp;·&nbsp; <b style="color:#546e7a">⏸ 보류</b> 판단 미룸. <span style="color:#999">※ 매핑확인=DB추가 아님(1단계).</span></div></header>
<div class="grid" id="grid"></div>
<script>
const DATA=__DATA__,DTO=__DTO__;const TABS=['PRIMARY','DEFER_RR','NEEDS_TRAINER'];const LBL={PRIMARY:'1차(non-RR)',DEFER_RR:'RR 보류',NEEDS_TRAINER:'트레이너 보류'};
let cur='PRIMARY',segv='';
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
const im=(u,t)=>u?`<img src="${esc(u)}" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'pend',textContent:'이미지 없음'}))">`:`<div class="pend">${t||'없음'}</div>`;
const cf=c=>c&&(c.endsWith('EXACT')||c=='EN_MATCH_VISUAL'||c=='EN_MERGED_MANUAL')?'ok':c&&c.endsWith('AMBIGUOUS')?'amb':'un';
const DEC=JSON.parse(localStorage.getItem('gapfill_dec')||'{}');
const _MIG={approve:'mapping_verified',reject:'mapping_rejected',reroll:'reroll_requested'};
let _md=false;for(const k in DEC){if(DEC[k]&&_MIG[DEC[k].state]){DEC[k].state=_MIG[DEC[k].state];_md=true;}}
if(_md)localStorage.setItem('gapfill_dec',JSON.stringify(DEC));
function saveDec(){localStorage.setItem('gapfill_dec',JSON.stringify(DEC));}
function dc(code){return DEC[code]||{};}
function setSt(code,st){const d=DEC[code]||{};d.state=d.state==st?null:st;DEC[code]=d;saveDec();render();}
function setEn(code,ref){const d=DEC[code]||{};d.enPick=d.enPick==ref?null:ref;DEC[code]=d;saveDec();render();}
function expDec(st){const o=[];DATA.forEach(c=>{const d=DEC[c.code];if(!d||d.state!=st)return;
 if(st=='reroll_requested'){o.push({code:c.code,ko_name:c.ko_name,productId:(c.admin&&c.admin.productId)||null,current_jp_ref:c.jp_ref,current_en_ref:(d.enPick||c.en_ref||null),current_en_candidates:c.en_candidates||[],rejected_or_bad_candidate:c.en_ref||null,reason:'reroll_requested'});}
 else{o.push({code:c.code,ko_name:c.ko_name,ko_set:c.ko_set,ko_rarity:c.ko_rarity,productId:(c.admin&&c.admin.productId)||null,officialCardCode:c.code,jpScrydexRef:c.jp_ref,enScrydexRef:(d.enPick||c.en_ref||null),en_conf:c.en_conf,state:st});}});
 if(!o.length){alert('해당 상태 카드 없음');return;}
 const fn=(st=='reroll_requested')?'reroll_request':st;
 const b=new Blob([JSON.stringify(o,null,1)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=fn+'_'+new Date().toISOString().slice(0,19).replace(/[:T]/g,'')+'.json';a.click();alert(fn+' '+o.length+'건 내보냄 (catalog_gapfill 저장 → '+(st=='reroll_requested'?'reroll.py 실행':'다음=가격/차트 검수')+')');}
document.getElementById('tabs').innerHTML=TABS.map(t=>`<div class="tab ${t==cur?'on':''}" onclick="tab('${t}')">${LBL[t]} <span>${DATA.filter(c=>c.tab==t).length}</span></div>`).join('');
function tab(t){cur=t;document.querySelectorAll('.tab').forEach((e,i)=>e.classList.toggle('on',TABS[i]==t));fill();render();}
function seg(v){segv=v;document.querySelectorAll('#seg button').forEach(e=>e.classList.toggle('on',e.dataset.v==v));render();}
function fill(){const d=DATA.filter(c=>c.tab==cur);
 fstat.innerHTML='<option value="">준비상태 전체</option>'+[...new Set(d.map(c=>c.status))].sort().map(x=>`<option>${x}</option>`).join('');
 fset.innerHTML='<option value="">전체세트('+d.length+')</option>'+[...new Set(d.map(c=>c.ko_set))].sort().map(x=>'<option>'+esc(x)+'</option>').join('');
 frar.innerHTML='<option value="">전체레어도</option>'+[...new Set(d.map(c=>c.ko_rarity))].sort().map(x=>'<option>'+esc(x)+'</option>').join('');}
function vis(){return DATA.filter(c=>c.tab==cur&&(!fstat.value||c.status==fstat.value)&&(!fen.value||c.en_conf==fen.value)&&(!fset.value||c.ko_set==fset.value)&&(!frar.value||c.ko_rarity==frar.value)&&(!fq.value.trim()||c.ko_name.includes(fq.value.trim()))&&(!segv||(segv=='EXCLUDE'?(c.verdict||'').startsWith('EXCLUDE'):c.verdict==segv))&&(!fdec.value||(fdec.value=='none'?!dc(c.code).state:dc(c.code).state==fdec.value)));}
function seriesRow(c){const s=c.series||{};const cc=x=>x=='EXACT'?'ok':x=='AMBIGUOUS'?'amb':'un';
 return `<div class="admin"><div class="t">DB 기존매핑 기준 시리즈 (productId — 진실원, scrydex 추론 아님) <span class="badge ${s.source=='DB_PRODUCT'?'ADMIN_READY':s.source=='DB_SERIES'?'amb':'un'}">${esc(s.source||'—')}</span></div><div class="dto">`+
 `<div><span class="k">productId</span> <span class="v">${esc(s.productId||'—')}</span></div>`+
 `<div><span class="k">JP 시리즈</span> <span class="v">${esc(s.jp_set||'—')}</span> <span class="badge ${cc(s.jp_conf)}">${esc(s.jp_conf||'')}</span></div>`+
 `<div><span class="k">EN 시리즈</span> <span class="v">${esc(s.en_set||'—')}</span> <span class="badge ${cc(s.en_conf)}">${esc(s.en_conf||'')}</span></div>`+
 (s.jp_conf=='AMBIGUOUS'?`<div><span class="k">jp분포</span> <span class="v">${esc(s.jp_dist)}</span></div>`:'')+
 (s.en_conf=='AMBIGUOUS'?`<div><span class="k">en분포</span> <span class="v">${esc(s.en_dist)}</span></div>`:'')+
 `</div></div>`;}
function dtoRow(c){return `<div class="admin"><div class="t">관리자 추가 필드 preview (POST /api/admin/cards)</div><div class="dto">`+
 DTO.map(k=>{const v=c.admin[k];const miss=(k=='productId'||k=='jpScrydexRef')&&!v;return `<div><span class="k">${k}</span> <span class="v ${miss?'miss':''}">${v==null?(k=='enScrydexRef'?'null(수동)':'—'):esc(v)}</span></div>`;}).join('')+`</div></div>`;}
function card(c){
 const ko=`<div class="col ko"><div class="lbl">KO 공식 (pokemoncard)</div>${im(c.ko_img)}<div class="id"><b>${esc(c.ko_name)}</b><br>${esc(c.ko_set)}<br>번호 ${esc(c.ko_no)} · <span class="badge rar">${esc(c.ko_rarity)}</span><br><span class="refs">${esc(c.code)}</span><br><a class="lnk" href="${esc(c.ko_detail)}" target="_blank">상세↗</a></div></div>`;
 const jp=`<div class="col jp"><div class="lbl">JP 후보 <span class="badge ${cf(c.jp_conf)}">${esc((c.jp_conf||'').replace('JP_MATCH_','').replace('JP_',''))}</span></div>${c.jp_ref?im(c.jp_img):`<div class="pend">${c.tab=='DEFER_RR'?'RR 보류':c.tab=='NEEDS_TRAINER'?'트레이너 보류':'JP 미해결'}</div>`}<div class="id">${c.jp_ref?`<b>${esc(c.jp_name)}</b><br><span class="refs">${esc(c.jp_ref)}</span><div class="reason">${esc(c.jp_reason)}</div>`:'<span class="muted">—</span>'}</div></div>`;
 const enCands=(c.en_candidates&&c.en_candidates.length)?`<div style="display:flex;gap:5px;flex-wrap:wrap;justify-content:center">`+c.en_candidates.map(rf=>`<div style="text-align:center"><img class="encand ${dc(c.code).enPick==rf?'pick':''}" onclick="setEn('${c.code}','${esc(rf)}')" title="클릭=이 변종을 EN으로 선택" src="https://images.scrydex.com/pokemon/${esc(rf)}/medium" style="width:62px;height:86px;object-fit:contain;background:#fff" loading="lazy"><div class="refs" style="font-size:9px">${esc(rf)} <a href="https://scrydex.com/pokemon/cards/_/${esc(rf)}" target="_blank">↗</a></div></div>`).join('')+`</div>`:'';
 const enBody=c.en_ref?im(c.en_img):(enCands?`<div class="id" style="text-align:center;margin-bottom:5px;color:#f57f17;font-weight:700">변종 ${c.en_candidates.length} — 사람이 선택</div>${enCands}`:`<div class="pend">EN 미해결<br><span style="font-weight:400">${esc(c.en_reason)||'보류'}</span></div>`);
 const en=`<div class="col en"><div class="lbl">EN 후보 <span class="badge ${cf(c.en_conf)}">${esc((c.en_conf||'').replace('EN_MATCH_','').replace('EN_',''))}</span></div>${enBody}<div class="id">${c.en_ref?`<b>${esc(c.en_name)}</b><br><span class="refs">${esc(c.en_ref)}</span><div class="reason">${esc(c.en_reason)}</div>`:`<div class="reason">${esc(c.en_reason)}</div>`}</div></div>`;
 let ex='';if(c.ex){ex=`<div class="col ex"><div class="lbl">↳ 기존 prod (추가 제외)</div>${im(c.ex.img)}<div class="id"><b>${esc(c.ex.name)}</b> <span class="muted">${esc(c.ex.card_id)}</span><br>${esc(c.ex.product)} <span class="muted">${esc(c.ex.productId)}</span><br>번호 ${esc(c.ex.num)} · <span class="badge rar">${esc(c.ex.rarity)}</span><br><span class="refs">JP ${esc(c.ex.jp_ref)}<br>EN ${esc(c.ex.en_ref||'—')}</span></div></div>`;}
 const ds=dc(c.code).state;const dcls=ds=='mapping_verified'?'dap':ds=='mapping_rejected'?'drj':ds=='reroll_requested'?'drr':'';
 const decbar=`<div class="decbar"><span class="muted" style="font-size:11px">1단계 매핑검수:</span><button class="ap ${ds=='mapping_verified'?'on':''}" title="KO·JP·EN 같은 카드(맞음) → 다음 단계로" onclick="setSt('${c.code}','mapping_verified')">✓ 매핑확인</button><button class="rr ${ds=='reroll_requested'?'on':''}" title="후보가 틀림 → 새 후보 탐색요청(현재후보 보존, reroll.py)" onclick="setSt('${c.code}','reroll_requested')">↻ 다시찾기</button><button class="rj ${ds=='mapping_rejected'?'on':''}" title="이 카드 자체를 후보에서 뺌(리롤 안함, 드롭)" onclick="setSt('${c.code}','mapping_rejected')">✗ 제외</button><button class="hd ${ds=='hold'?'on':''}" title="판단 미룸, 나중에" onclick="setSt('${c.code}','hold')">⏸ 보류</button>${dc(c.code).enPick?`<span class="muted">EN 수동선택 <span class="refs">${esc(dc(c.code).enPick)}</span></span>`:''}</div>`;
 return `<div class="card ${c.verdict} ${dcls}"><div class="hd"><span class="nm">${esc(c.ko_name)}</span><span class="badge ${c.status}">${esc(c.status)}</span>${c.verdict?`<span class="badge ${c.verdict}">${esc(c.verdict)}</span>`:''}<span class="badge code">${esc(c.code)}</span><span class="muted">${esc(c.type)}</span></div><div class="cols">${ko}${jp}${en}${ex}</div>${seriesRow(c)}${dtoRow(c)}${decbar}</div>`;}
function render(){const v=vis();grid.innerHTML=v.map(card).join('');
 const d=DATA.filter(c=>c.tab==cur);const ready=d.filter(c=>c.status=='ADMIN_READY').length;
 const ap=d.filter(c=>dc(c.code).state=='mapping_verified').length,rj=d.filter(c=>dc(c.code).state=='mapping_rejected').length,rr=d.filter(c=>dc(c.code).state=='reroll_requested').length;
 stat.textContent=`보임 ${v.length} | ADMIN_READY ${ready} | ✓매핑확인 ${ap} ↻다시찾기 ${rr} ✗제외 ${rj}`;}
tab('PRIMARY');
</script></body></html>'''
open(os.path.join(P, OUT), 'w').write(TPL.replace('__DATA__', DATA).replace('__DTO__', DTOJS))
sc = collections.Counter(c['status'] for c in out if c['tab'] == 'PRIMARY')
print("PRIMARY 준비상태:", dict(sc))
print("→ final_review.html (검수용: 4칸 + 관리자 DTO preview + 준비상태/EN/세트/레어도 필터)")
