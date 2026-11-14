"""Icône Shreddish : S en Bricolage Grotesque, tranché en diagonale (la sèche), point tomate.

Usage : python3 draw_icon.py sortie.png 8 ios/App/Resources/Fonts/BricolageGrotesque.ttf (Pillow requis).
"""
import sys, math
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter
K = 4; N = 1024 * K
def hx(h, a=255): return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)
font = ImageFont.truetype(sys.argv[3], 860 * K)
try: font.set_variation_by_name("ExtraBold")
except Exception as e: print(e, font.get_variation_names())
# Fond dégradé.
top, bottom = hx(0x38805A), hx(0x1E4832)
bg = Image.new("RGBA", (N, N))
d = ImageDraw.Draw(bg)
for y in range(0, N, K):
    t = y / N
    d.rectangle((0, y, N, y + K), fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
# Lettre S centrée (masque).
mask = Image.new("L", (N, N), 0)
md = ImageDraw.Draw(mask)
l, t_, r, b = md.textbbox((0, 0), "S", font=font)
md.text(((N - (r - l)) / 2 - l - 30 * K, (N - (b - t_)) / 2 - t_ + 10 * K), "S", font=font, fill=255)
# Coupe nette en diagonale (le « shred ») : bande vide, moitié basse décalée.
angle = math.radians(-24)
cx, cy = N / 2 - 30 * K, N / 2 + 10 * K
gap = 30 * K
def side(px, py): return (py - cy) * math.cos(angle) - (px - cx) * math.sin(angle)
upper = Image.new("L", (N, N), 0); lower = Image.new("L", (N, N), 0)
ud, ld = ImageDraw.Draw(upper), ImageDraw.Draw(lower)
L = N * 2
nx, ny = -math.sin(angle), math.cos(angle)  # normale
tx, ty = math.cos(angle), math.sin(angle)
def band(draw, o1, o2):
    pts = [(cx + tx * -L + nx * o1, cy + ty * -L + ny * o1), (cx + tx * L + nx * o1, cy + ty * L + ny * o1),
           (cx + tx * L + nx * o2, cy + ty * L + ny * o2), (cx + tx * -L + nx * o2, cy + ty * -L + ny * o2)]
    draw.polygon(pts, fill=255)
band(ud, -L, -gap / 2); band(ld, gap / 2, L)
up = ImageChops.multiply(mask, upper); lo = ImageChops.multiply(mask, lower)
shift = int(float(sys.argv[2]) * K) if len(sys.argv) > 2 else 0
lo = ImageChops.offset(lo, int(tx * shift), int(ty * shift))
letter = ImageChops.lighter(up, lo)
shadow = letter.filter(ImageFilter.GaussianBlur(22 * K)).point(lambda v: v * 0.35)
img = Image.composite(Image.new("RGBA", (N, N), (0, 0, 0, 255)), bg, shadow)
img = Image.composite(Image.new("RGBA", (N, N), hx(0xF5F1E8)), img, letter)
# Pépin tomate au bout de la coupe.
d = ImageDraw.Draw(img)
r = 42 * K
px, py = cx + tx * 345 * K, cy + ty * 345 * K
d.ellipse((px - r, py - r, px + r, py + r), fill=hx(0xE5603A))
img.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(sys.argv[1])
