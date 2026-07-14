#!/usr/bin/env python3
"""오리파 봉인팩 마스터 PNG → 4레이어(base/open_body/top_strip/mouth_shadow) + 알파 QA.

사용:
    python3 pack_layers.py <master.png> <outdir> [--matte]
  --matte : 알파가 없거나(RGB) 전면 불투명이면 rembg로 배경 제거(밝은 팩은 어두운 배경 촬영 권장).

의존: pip install --user rembg onnxruntime pillow numpy
규칙: strip_h = mouth_h = 팩 높이의 14%(닫힘 정합). 3종 동일 실루엣이면 결과 구조 동일.
"""
import sys, os
import numpy as np
from PIL import Image

STRIP_FRAC = 0.14  # 상단 크림프=개봉구. oripa_sealed_pack.dart _stripFrac 과 일치시킬 것.

def qa(img, tag):
    a = img.getchannel("A"); w, h = img.size; tot = w * h; hist = a.histogram()
    corners = [a.getpixel(c) for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    print(f"[{tag}] {w}x{h} corners={corners} "
          f"alpha0={100*hist[0]/tot:.1f}% alpha255={100*hist[255]/tot:.1f}% "
          f"partial={100*(tot-hist[0]-hist[255])/tot:.1f}%")

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    inp, outdir = sys.argv[1], sys.argv[2]
    matte = "--matte" in sys.argv
    os.makedirs(outdir, exist_ok=True)
    im = Image.open(inp).convert("RGBA")
    if matte or im.getchannel("A").getextrema() == (255, 255):
        from rembg import remove
        im = remove(im)
    im = im.crop(im.getchannel("A").getbbox())
    W, H = im.size
    im.save(f"{outdir}/base.png"); qa(im, "base")
    arr = np.array(im)
    sh = int(H * STRIP_FRAC)
    strip = np.zeros_like(arr); strip[:sh] = arr[:sh]
    Image.fromarray(strip).save(f"{outdir}/top_strip.png")
    grad = np.linspace(0.88, 0.0, sh)[:, None]
    ob = arr.astype(float)
    for c in range(3):
        ob[:sh, :, c] *= (1 - grad)
    Image.fromarray(ob.clip(0, 255).astype("uint8")).save(f"{outdir}/open_body.png")
    ms = np.zeros((sh, W, 4), "uint8")
    ms[:, :, 3] = np.repeat((grad * 255).astype("uint8"), W, axis=1)
    Image.fromarray(ms).save(f"{outdir}/mouth_shadow.png")
    print(f"OK -> {outdir}  (strip/mouth_h={sh})")

if __name__ == "__main__":
    main()
