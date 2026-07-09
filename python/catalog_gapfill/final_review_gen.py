#!/usr/bin/env python3
"""최종 검수 HTML v3 (5탭 + 전체 증거). read-only. prod write 0."""
import json, collections, html, csv

HI = {'RR','RRR','AR','SR','SAR','SSR','UR','HR','CSR','MUR','MA','CHR'}
CDN = "https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp"
jm = {c['code']: c for c in json.load(open('jp_match_preview.json'))}
res = {r['code']: r for r in json.load(open('/tmp/img_dedup_results.json'))}
rej = {o['code']: o for o in json.load(open('/tmp/rejudge.json'))}
rf = json.load(open('/tmp/resolve_final.json'))
resolved_ref = {o['code']: o['resolved_ref'] for o in rf['resolved']}
unresolved = {o['code']: o for o in rf['unresolved']}

# prod ref 맵
prod_jp = {}; prod_en = {}
for line in open('/tmp/prod_refmap.csv'):
    p = (line.rstrip('\n').split('|') + ['']*4)[:4]
    cid, nm, jp, en = p
    if jp and not jp.startswith('NO_'): prod_jp[jp] = (cid, nm)
    if en and not en.startswith('NO_'): prod_en[en] = (cid, nm)

# 246 스코프
scope = [c for c in jm.values() if c.get('verdict') != 'EXCLUDE_JP' and c['ko_rarity'] in HI
         and (('포켓몬' in c['type']) or ('서포트' in c['type']))]

def final_jp_ref(c):
    return c.get('jp_ref') or resolved_ref.get(c['code']) or ''

def classify(c):
    code = c['code']; jp = c.get('jp_ref') or ''; en = c.get('en_ref') or ''
    # exact ref dup (jp 또는 en이 prod에)
    if (jp and (jp in prod_jp or jp in prod_en)) or (en and (en in prod_jp or en in prod_en)):
        return 'EXCLUDE_EXACT_REF'
    r = res.get(code, {}); s = r.get('score', 0)
    if s >= 0.75:
        o = rej.get(code, {})
        if o.get('s1', 0) >= 0.92 and o.get('nm_match') and o.get('rar_match') and o.get('margin', 0) >= 0.05:
            return 'EXCLUDE_SAME_ART_AUTO_CANDIDATE'
        return 'MANUAL_REVIEW'
    # 신규 추정
    if code in resolved_ref: return 'NEW_CANDIDATE'
    if c.get('jp_ref'): return 'NEW_CANDIDATE'
    return 'UNRESOLVED'

groups = collections.defaultdict(list)
for c in scope: groups[classify(c)].append(c['code'])

def img(u, w=105):
    return f'<img src="{html.escape(u or "")}" loading=lazy style="width:{w}px;display:block">' if u else '<i>—</i>'

def row(code, mode):
    c = jm[code]; r = res.get(code, {}); o = rej.get(code, {})
    koi = c.get('ko_image_url', ''); jpi = c.get('jp_image_url') or c.get('en_image_url') or ''
    fref = final_jp_ref(c)
    jp_ref_disp = html.escape(fref) if fref else ('<b style=color:red>미확정</b>')
    src = ' <span style=color:green>(resolved)</span>' if code in resolved_ref else ''
    base = f"<td>{img(koi)}<br><b>{html.escape(c['ko_name'])}</b><br>{c['ko_rarity']} · #{c['ko_collection_no']}<br>{html.escape(c['ko_set_name'][:20])}</td>"
    jp_cell = f"<td>{img(jpi)}<br><code>{jp_ref_disp}</code>{src}<br>{html.escape((c.get('jp_name') or '')[:24])}</td>"
    if mode in ('EXCLUDE', 'MANUAL'):
        mcid = o.get('match_cid', ''); pm = f"{CDN}/{mcid}.png" if mcid else ''
        evid = (f"<td>{img(pm)}<br>{html.escape(o.get('t1_name',''))} ({o.get('t1_rar','')})<br>"
                f"cid <code>{mcid[:14]}</code><br>s1=<b>{o.get('s1',0)}</b> s2={o.get('s2',0)} margin=<b>{o.get('margin',0)}</b><br>"
                f"이름:{'O' if o.get('nm_match') else '<b style=color:red>X</b>'} "
                f"레어도:{'O' if o.get('rar_match') else '<b style=color:red>X</b>'}</td>")
        return f"<tr>{base}{jp_cell}{evid}</tr>"
    if mode == 'UNRESOLVED':
        u = unresolved.get(code, {})
        sims = ' · '.join(f"{rr}:{ss}" for rr, ss in (u.get('sims') or [])[:3])
        return f"<tr>{base}{jp_cell}<td>사유: {html.escape(u.get('reason',''))}<br>후보: {html.escape(sims)}</td></tr>"
    return f"<tr>{base}{jp_cell}</tr>"

def section(name, codes, desc, mode):
    by = collections.defaultdict(list)
    for code in codes:
        c = jm[code]; fr = final_jp_ref(c); s = fr.split('-')[0] if fr else (c.get('series_jp_set') or '?')
        by[s].append(code)
    h = f"<h2 id={name}>{name} ({len(codes)}) — {desc}</h2>"
    for s in sorted(by, key=lambda x: -len(by[x])):
        h += f"<h3>{s} ({len(by[s])})</h3><table><tr><th>KO 원본</th><th>JP 후보</th>"
        h += ("<th>prod 중복 (증거)</th>" if mode in ('EXCLUDE', 'MANUAL') else ("<th>미해결 사유</th>" if mode == 'UNRESOLVED' else "")) + "</tr>"
        for code in sorted(by[s], key=lambda x: jm[x]['ko_rarity']):
            h += row(code, mode)
        h += "</table>"
    return h

tabs = [('NEW_CANDIDATE', groups['NEW_CANDIDATE'], 'READY_FOR_REVIEW — 신규 추정 (jp_ref 확정/resolved)', 'NEW'),
        ('UNRESOLVED', groups['UNRESOLVED'], 'jp_ref 미해결 (애매/이미지없음) — 추가 보류', 'UNRESOLVED'),
        ('MANUAL_REVIEW', groups['MANUAL_REVIEW'], '사람 판정 (score/margin/이름/레어도 조건 미달)', 'MANUAL'),
        ('EXCLUDE_SAME_ART_AUTO_CANDIDATE', groups['EXCLUDE_SAME_ART_AUTO_CANDIDATE'], '동일일러스트 추정 — 네 이미지확인 후에만 제외확정', 'EXCLUDE'),
        ('EXCLUDE_EXACT_REF', groups['EXCLUDE_EXACT_REF'], 'prod에 동일 jp/en ref 존재 (안전 제외)', 'EXCLUDE')]
nav = " · ".join(f'<a href=#{n}>{n} {len(cs)}</a>' for n, cs, _, _ in tabs)
body = "".join(section(n, cs, d, m) for n, cs, d, m in tabs)
note = ("교차검증: JP ref 해결 25(중복0) · en_ref 데이터 없음→이미지 dedup(prod 전체, EN출처 포함)이 일러스트 중복 커버 · 25장 전부 img&lt;0.75=prod 미존재 · "
        "<b>모두 '신규 추정'이며 확정 아님 — 네 검수 후 확정</b>")
doc = f"""<!doctype html><meta charset=utf-8><title>시리즈 갭 최종검수 v4</title>
<style>body{{font-family:sans-serif;margin:10px;background:#f4f4f4}}table{{border-collapse:collapse;margin:5px 0;background:#fff}}
td,th{{border:1px solid #ccc;padding:4px;font-size:11px;vertical-align:top}}code{{background:#eee;font-size:10px}}
.nav{{position:sticky;top:0;background:#222;color:#fff;padding:8px;z-index:9}}.nav a{{color:#7cf;margin-right:8px}}h2{{background:#333;color:#fff;padding:6px}}h3{{color:#555}} .note{{background:#553;color:#fff;padding:6px;font-size:11px}}</style>
<div class=nav><b>시리즈 갭 최종검수 v4 (RR+ 포켓몬/서포트) · prod write 금지</b><br>{nav}</div>
<div class=note>{note}</div>{body}"""
open('series_gap_final_review_v4.html', 'w').write(doc)

# CSV 5종
def wcsv(fn, codes, extra=False):
    with open(fn, 'w', newline='') as f:
        cols = ['code', 'ko_name', 'rarity', 'ko_no', 'ko_set', 'jp_ref', 'series'] + (['match_cid', 'match_name', 's1', 's2', 'margin', 'nm_match', 'rar_match'] if extra else [])
        w = csv.writer(f); w.writerow(cols)
        for code in codes:
            c = jm[code]; o = rej.get(code, {}); fr = final_jp_ref(c)
            base = [code, c['ko_name'], c['ko_rarity'], c['ko_collection_no'], c['ko_set_name'], fr, fr.split('-')[0] if fr else '']
            if extra: base += [o.get('match_cid', ''), o.get('t1_name', ''), o.get('s1', ''), o.get('s2', ''), o.get('margin', ''), o.get('nm_match', ''), o.get('rar_match', '')]
            w.writerow(base)
wcsv('final_new_candidate.csv', groups['NEW_CANDIDATE'])
wcsv('final_unresolved.csv', groups['UNRESOLVED'])
wcsv('final_manual_review.csv', groups['MANUAL_REVIEW'], True)
wcsv('final_exclude_same_art_candidate.csv', groups['EXCLUDE_SAME_ART_AUTO_CANDIDATE'], True)
wcsv('final_exclude_exact_ref.csv', groups['EXCLUDE_EXACT_REF'])

print("series_gap_final_review_v3.html + CSV 5종 생성")
for n, cs, _, _ in tabs: print(f"  {n}: {len(cs)}")
print(f"  합계 {sum(len(cs) for _, cs, _, _ in tabs)} = 246")
