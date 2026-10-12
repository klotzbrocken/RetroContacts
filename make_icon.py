import sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
src = Image.open(sys.argv[1]).convert("RGB")
a = np.asarray(src).astype(int)
mn = a.min(axis=2)
light = (mn >= 228).astype(np.uint8) * 255
m = Image.fromarray(light).convert("RGB")
# flood fill background from all four corners
for p in [(0,0),(m.width-1,0),(0,m.height-1),(m.width-1,m.height-1)]:
    if m.getpixel(p)==(255,255,255): ImageDraw.floodfill(m, p, (255,0,255))
_m = np.asarray(m); bg = (_m[:,:,0]==255) & (_m[:,:,1]==0)
rgb = np.asarray(src).astype(float).copy()
alpha = np.full(mn.shape, 255, dtype=float)
sh = bg & (mn >= 205)
alpha[sh] = np.clip((255 - mn[sh]) / 50.0 * 150, 0, 150)   # soft shadow, max 150
alpha[bg & (mn >= 252)] = 0
rgb[sh] = (40, 30, 30)                                      # shadow colour, no white halo
al = Image.fromarray(alpha.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
out = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA"); out.putalpha(al)
out.save("Resources/icon-source.png")
