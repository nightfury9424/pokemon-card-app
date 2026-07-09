"""리롤 채택 merge (별도·비파괴) — reroll_review.html 에서 사람이 채택한 reroll_selection.json 을
 현재 검수본 복사본에 반영 → jp_match_preview_merged.json + final_review_merged.html.
 ★원본 jp_match_preview.json / final_review.html 는 절대 수정 안 함.
   python merge_reroll.py reroll_selection_*.json
"""
import json, os, sys, subprocess

P = os.path.dirname(os.path.abspath(__file__))
SCRY = "https://images.scrydex.com/pokemon/{}/medium"

if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
    print("사용법: python merge_reroll.py <reroll_selection_*.json>  (reroll_review.html '리롤 채택 내보내기' 산출물)")
    sys.exit(1)

sel = json.load(open(sys.argv[1]))           # [{code, en_ref}]
picks = {x['code']: x.get('en_ref') for x in sel if x.get('en_ref')}

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))   # 원본 read-only
n = 0
for r in data:
    ref = picks.get(r['code'])
    if ref:
        r['en_ref'] = ref
        r['en_image_url'] = SCRY.format(ref)
        r['en_conf'] = 'EN_MERGED_MANUAL'
        r['en_reason'] = f"리롤 수동채택 {ref}"
        r['en_candidates'] = None
        n += 1

MERGED = os.path.join(P, 'jp_match_preview_merged.json')
json.dump(data, open(MERGED, 'w'), ensure_ascii=False, indent=1)   # 새 파일

env = os.environ.copy()
env['GAPFILL_SRC'] = 'jp_match_preview_merged.json'
env['GAPFILL_OUT'] = 'final_review_merged.html'
subprocess.run([sys.executable, os.path.join(P, 'final_render.py')], cwd=P, env=env, check=True)
print(f"merge {n}/{len(picks)} 채택 반영 → jp_match_preview_merged.json + final_review_merged.html")
print("※ 원본(jp_match_preview.json / final_review.html) 미변경. 검수는 merged 화면에서.")
