#!/usr/bin/env python3
"""팩 자산 알파 QA — 실제 투명 여부 실측 + 검정/흰색/빨강 3배경 엣지 검수.

사용:
    python3 qa_alpha.py <pack.png>
합격: mode=RGBA · 네 모서리 alpha=0 · 팩 외부/톱니 사이 alpha=0 · 외곽 프린지 없음.
가짜 투명(체크무늬 구운 RGB)은 여기서 걸러진다. 옆에 <name>_edgecheck.png 저장(검정/흰색/빨강).
"""
import sys
from PIL import Image

def main():
    p = sys.argv[1]
    im = Image.open(p)
    has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
    print(f"file={p.split('/')[-1]} mode={im.mode} size={im.size} real_alpha={has_alpha}")
    im = im.convert("RGBA"); a = im.getchannel("A"); w, h = im.size; tot = w * h
    corners = [a.getpixel(c) for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    hist = a.histogram()
    print(f"corners={corners} (투명이면 0) | alpha0={100*hist[0]/tot:.1f}% "
          f"alpha255={100*hist[255]/tot:.1f}% partial={100*(tot-hist[0]-hist[255])/tot:.1f}%")
    verdict = "PASS" if (has_alpha and max(corners) == 0 and hist[0] > 0) else "FAIL(가짜투명/프린지 의심)"
    print("VERDICT:", verdict)
    # 3배경 엣지 검수
    th = 380; tw = int(w * th / h); sm = im.resize((tw, th))
    strip = Image.new("RGB", (tw * 3 + 40, th), (18, 18, 20))
    for i, bg in enumerate([(0, 0, 0), (255, 255, 255), (200, 25, 25)]):
        lay = Image.new("RGBA", (tw, th), bg + (255,)); lay.alpha_composite(sm)
        strip.paste(lay.convert("RGB"), (i * (tw + 20), 0))
    out = p.rsplit(".", 1)[0] + "_edgecheck.png"; strip.save(out)
    print("edgecheck:", out)

if __name__ == "__main__":
    main()
