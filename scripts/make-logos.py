# Usage: python3 scripts/make-logos.py
# Builds every logo derivative from the designer's exports in assets/logo/source/*.svg:
#   - clean SVGs in assets/logo/svg (no white background, white fills become cut-outs) plus white variants
#   - transparent PNGs in assets/logo/png
#   - menu bar template images, the About logo and the app icon in App/Assets.xcassets
#   - the GitHub social preview (assets/logo/social-preview.png)
# Rasterizes with headless Google Chrome. Needs Pillow for crop bounds.
import json
import pathlib
import re
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/logo/source"
SVG = ROOT / "assets/logo/svg"
PNG = ROOT / "assets/logo/png"
ASSETS = ROOT / "App/Assets.xcassets"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
COLOUR = "colour"
SIZES = [1024, 512, 256, 128, 64, 32, 16]
# Glyphs used in the menu bar (see StatusText.iconName)
MENU = ["online", "pause", "stop"]
MENU_HEIGHT_PT = 16

tmp = pathlib.Path(tempfile.mkdtemp())
HEADER = '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000" fill="none">\n'


def chrome_shot(html: str, out: pathlib.Path, w: int, h: int, transparent: bool = True) -> None:
    page = tmp / "page.html"
    page.write_text(html)
    args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={w},{h}", f"--screenshot={out}", page.as_uri()]
    if transparent:
        args.insert(-2, "--default-background-color=00000000")
    subprocess.run(args, check=True, capture_output=True)


def render(svg: pathlib.Path, out: pathlib.Path, w: int, h: int, style: str = "") -> None:
    chrome_shot(f'<html><body style="margin:0;background:transparent"><img src="{svg.as_uri()}" '
                f'width="{w}" height="{h}" style="display:block;{style}"></body></html>', out, w, h)


def paths(text: str) -> list[dict]:
    found = []
    for m in re.finditer(r'<path ([^>]*?)/?>', text):
        attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(1)))
        found.append(attrs)
    return found


def clean_mono(text: str) -> str:
    """Designer export → transparent, single-colour SVG.

    white fill + black stroke  → outline (no fill)
    white fill, no stroke      → cut out of the black shape it sits on (even-odd)
    black fill + white stroke  → solid shape with a transparent gap of that stroke around it (mask)
    """
    body, cuts, solid = [], [], None
    for p in paths(text):
        fill, stroke = p.get("fill"), p.get("stroke")
        if fill == "white" and stroke == "black":
            body.append(f'<path stroke="#000" stroke-width="{p["stroke-width"]}" d="{p["d"]}"/>')
        elif fill == "white" and solid is not None:
            body[solid] = body[solid].replace('" d="', '" d="', 1).replace('"/>', f' {p["d"]}"/>')
        elif fill == "black" and stroke == "white":
            cuts.append((p["d"], p["stroke-width"]))
            body.append(f'<path fill="#000" d="{p["d"]}" data-cut="1"/>')
        elif fill == "black":
            solid = len(body)
            body.append(f'<path fill="#000" fill-rule="evenodd" clip-rule="evenodd" d="{p["d"]}"/>')
        else:
            raise SystemExit(f"unexpected paint fill={fill} stroke={stroke}")
    if not cuts:
        return HEADER + "\n".join(body) + "\n</svg>\n"
    masked = [b for b in body if 'data-cut' not in b]
    slashes = [b.replace(' data-cut="1"', '') for b in body if 'data-cut' in b]
    mask = "\n".join(f'<path fill="#000" stroke="#000" stroke-width="{w}" d="{d}"/>' for d, w in cuts)
    return (HEADER + '<defs>\n<mask id="gap" maskUnits="userSpaceOnUse" x="-100" y="-100" width="1200" height="1200">\n'
            '<rect x="-100" y="-100" width="1200" height="1200" fill="#fff"/>\n' + mask + '\n</mask>\n</defs>\n'
            '<g mask="url(#gap)">\n' + "\n".join(masked) + '\n</g>\n' + "\n".join(slashes) + "\n</svg>\n")


def clean_colour(text: str) -> str:
    text = re.sub(r'<rect width="1000" height="1000" fill="white"/>\n?', "", text)
    return text.replace('width="1000" height="1000" viewBox="0 0 1000 1000" fill="none" xmlns="http://www.w3.org/2000/svg"',
                        'xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000" fill="none"')


def recolor(text: str, color: str) -> str:
    # Visible paint only; mask contents keep their meaning.
    head, sep, rest = text.partition("</defs>")
    if not sep:
        head, rest = "", text
    return head + sep + rest.replace('"#000"', f'"{color}"')


def alpha_bbox(svg: pathlib.Path) -> tuple[int, int, int, int]:
    out = tmp / "bbox.png"
    render(svg, out, 1000, 1000)
    return Image.open(out).getchannel("A").getbbox()


def crop(svg: pathlib.Path, box: tuple[float, float, float, float], out: pathlib.Path) -> pathlib.Path:
    x, y, w, h = box
    out.write_text(re.sub(r'width="1000" height="1000" viewBox="[^"]+"',
                          f'width="{w:g}" height="{h:g}" viewBox="{x:g} {y:g} {w:g} {h:g}"',
                          svg.read_text(), count=1))
    return out


def imageset(name: str, files: dict[str, str], template: bool) -> pathlib.Path:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.png"):
        old.unlink()
    contents = {"images": [{"filename": f, "idiom": "universal", "scale": s} for s, f in files.items()],
                "info": {"author": "xcode", "version": 1}}
    if template:
        contents["properties"] = {"template-rendering-intent": "template"}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    return folder


# 1. Clean SVGs and white variants
SVG.mkdir(parents=True, exist_ok=True)
for old in SVG.glob("*.svg"):
    old.unlink()
mono = sorted(p.stem for p in SOURCE.glob("*.svg") if p.stem != COLOUR)
for name in mono:
    clean = clean_mono((SOURCE / f"{name}.svg").read_text())
    (SVG / f"{name}.svg").write_text(clean)
    (SVG / f"{name}-white.svg").write_text(recolor(clean, "#fff"))
(SVG / f"{COLOUR}.svg").write_text(clean_colour((SOURCE / f"{COLOUR}.svg").read_text()))

# 2. Transparent PNGs
PNG.mkdir(parents=True, exist_ok=True)
for old in PNG.glob("*.png"):
    old.unlink()
for svg in sorted(SVG.glob("*.svg")):
    for s in SIZES:
        render(svg, PNG / f"{svg.stem}-{s}.png", s, s)

# 3. Menu bar template images: one shared crop around every glyph so they line up
boxes = [alpha_bbox(SVG / f"{n}.svg") for n in MENU]
left, top = min(b[0] for b in boxes), min(b[1] for b in boxes)
right, bottom = max(b[2] for b in boxes), max(b[3] for b in boxes)
pad = 4
menu_box = (left - pad, top - pad, right - left + 2 * pad, bottom - top + 2 * pad)
menu_w_pt = round(MENU_HEIGHT_PT * menu_box[2] / menu_box[3])
for old in ASSETS.glob("MenuBar*.imageset"):
    for f in old.iterdir():
        f.unlink()
    old.rmdir()
for n in MENU:
    cropped = crop(SVG / f"{n}.svg", menu_box, tmp / f"menu-{n}.svg")
    name = f"MenuBar{n.capitalize()}"
    files = {f"{k}x": (f"{name}@{k}x.png" if k > 1 else f"{name}.png") for k in (1, 2, 3)}
    folder = imageset(name, files, template=True)
    for k in (1, 2, 3):
        render(cropped, folder / files[f"{k}x"], menu_w_pt * k, MENU_HEIGHT_PT * k)

# 4. About logo: colour mark cropped to the cloud with room for a soft shadow
l, t, r, b = alpha_bbox(SVG / f"{COLOUR}.svg")
about_h_pt = 100
margin = 0.08 * (r - l)
about_box = (l - margin, t - margin * 0.6, r - l + 2 * margin, b - t + margin * 2)
about_w_pt = round(about_h_pt * about_box[2] / about_box[3])
cropped = crop(SVG / f"{COLOUR}.svg", about_box, tmp / "about.svg")
folder = imageset("Logo", {"1x": "Logo.png", "2x": "Logo@2x.png"}, template=False)
for f, k in (("Logo.png", 1), ("Logo@2x.png", 2)):
    render(cropped, folder / f, about_w_pt * k, about_h_pt * k,
           f"filter:drop-shadow(0 {3 * k}px {4 * k}px rgba(0,60,170,.28))")
print(f"About logo: {about_w_pt}x{about_h_pt} pt, menu bar: {menu_w_pt}x{MENU_HEIGHT_PT} pt")

# 5. App icon: blue tile, white cloud, blue lettering, on Apple's 1024 grid (824 tile, 100 inset)
shy = paths((SOURCE / "shy.svg").read_text())
cloud, letters = shy[0]["d"], " ".join(p["d"] for p in shy[1:])
(SVG / "app-icon.svg").write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" fill="none">
<defs>
<linearGradient id="tile" x1="300" y1="80" x2="720" y2="960" gradientUnits="userSpaceOnUse">
<stop stop-color="#5FF4FF"/>
<stop offset="0.45" stop-color="#1FA6FF"/>
<stop offset="1" stop-color="#0066FF"/>
</linearGradient>
<radialGradient id="glow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(330 170) rotate(60) scale(720 620)">
<stop stop-color="#fff" stop-opacity="0.22"/>
<stop offset="1" stop-color="#fff" stop-opacity="0"/>
</radialGradient>
<linearGradient id="rim" x1="512" y1="100" x2="512" y2="924" gradientUnits="userSpaceOnUse">
<stop stop-color="#fff" stop-opacity="0.45"/>
<stop offset="0.5" stop-color="#fff" stop-opacity="0.06"/>
<stop offset="1" stop-color="#002A80" stop-opacity="0.18"/>
</linearGradient>
<linearGradient id="cloud" x1="500" y1="184" x2="500" y2="817" gradientUnits="userSpaceOnUse">
<stop stop-color="#FFFFFF"/>
<stop offset="1" stop-color="#E4F0FF"/>
</linearGradient>
<linearGradient id="type" x1="500" y1="312" x2="500" y2="737" gradientUnits="userSpaceOnUse">
<stop stop-color="#22B4F7"/>
<stop offset="1" stop-color="#0A62F0"/>
</linearGradient>
<filter id="cloudShadow" x="-15%" y="-15%" width="130%" height="145%" color-interpolation-filters="sRGB">
<feDropShadow dx="0" dy="22" stdDeviation="22" flood-color="#00307F" flood-opacity="0.32"/>
</filter>
<filter id="lift" x="-10%" y="-10%" width="120%" height="130%" color-interpolation-filters="sRGB">
<feDropShadow dx="0" dy="10" stdDeviation="9" flood-color="#00307F" flood-opacity="0.30"/>
</filter>
<clipPath id="tileClip"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#tile)"/>
<g clip-path="url(#tileClip)"><rect x="100" y="100" width="824" height="824" fill="url(#glow)"/></g>
<rect x="101.5" y="101.5" width="821" height="821" rx="183.5" stroke="url(#rim)" stroke-width="3"/>
<g transform="translate(512 500) scale(0.72) translate(-500 -500)">
<path fill="url(#cloud)" filter="url(#cloudShadow)" d="{cloud}"/>
<path fill="url(#type)" filter="url(#lift)" d="{letters}"/>
</g>
</svg>
''')
icon_dir = ASSETS / "AppIcon.appiconset"
for old in icon_dir.glob("*.png"):
    old.unlink()
master = tmp / "icon-1024.png"
chrome_shot(f'<html><body style="margin:0;background:transparent">'
            f'<div style="position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;'
            f'box-shadow:0 10px 22px rgba(0,0,0,.22)"></div>'
            f'<img src="{(SVG / "app-icon.svg").as_uri()}" width="1024" height="1024" '
            f'style="position:absolute;left:0;top:0"></body></html>', master, 1024, 1024)
images = []
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        px = base * scale
        subprocess.run(["sips", "-z", str(px), str(px), str(master), "--out", str(icon_dir / name)],
                       check=True, capture_output=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{base}x{base}"})
(icon_dir / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
                                                   indent=2, sort_keys=True) + "\n")

# 6. README logo
(ROOT / "docs/images/logo.svg").write_text((SVG / f"{COLOUR}.svg").read_text())

# 7. GitHub social preview (1280×640; GitHub may crop ~40px, so content stays inside)
(tmp / "puff.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">'
                              f'<path fill="#fff" d="{cloud}"/></svg>')
jaro = (ROOT / "App/Fonts/Jaro.ttf").as_uri()
chrome_shot(f"""<html><head><style>
@font-face {{ font-family:Jaro; src:url("{jaro}"); }}
body {{ margin:0; width:1280px; height:640px; overflow:hidden; position:relative;
  font-family:-apple-system,'SF Pro Display',Helvetica,sans-serif;
  background: radial-gradient(120% 90% at 18% 20%, #ffffff 0%, #eaf6ff 45%, #d3e9ff 100%); }}
.puff {{ position:absolute; opacity:.55; filter:blur(2px); }}
.wrap {{ position:absolute; inset:0; display:flex; align-items:center; gap:64px; padding:0 104px; }}
.logo {{ width:380px; height:380px; flex:none; filter:drop-shadow(0 24px 34px rgba(0,70,190,.28)); }}
h1 {{ margin:0; font-family:Jaro; font-size:150px; font-weight:400; line-height:1.1; padding-bottom:.08em; margin-bottom:-.12em;
  background:linear-gradient(180deg,#0b1d33,#16365c); -webkit-background-clip:text; color:transparent; }}
p {{ margin:22px 0 34px; font-size:38px; line-height:1.22; color:#38536e; font-weight:500; max-width:600px; }}
.chips {{ display:flex; gap:12px; flex-wrap:wrap; }}
.chip {{ font-size:22px; font-weight:600; color:#0a5bd6; background:rgba(255,255,255,.75);
  border:1.5px solid rgba(10,108,255,.18); border-radius:999px; padding:10px 20px; }}
.url {{ position:absolute; right:104px; bottom:52px; font-size:22px; color:#6b84a0; font-weight:500; }}
</style></head><body>
<img class="puff" src="{(tmp / 'puff.svg').as_uri()}" style="width:420px;left:-120px;bottom:-150px;opacity:.7">
<img class="puff" src="{(tmp / 'puff.svg').as_uri()}" style="width:300px;right:-60px;top:-110px">
<div class="wrap"><img class="logo" src="{(SVG / f'{COLOUR}.svg').as_uri()}">
<div><h1>shyCloud</h1><p>Pause iCloud Drive sync<br>on your Mac, on a schedule.</p>
<div class="chips"><span class="chip">Free &amp; open source</span><span class="chip">Apple Silicon</span>
<span class="chip">No tracking</span></div></div></div>
<div class="url">github.com/ekremus/shycloud</div>
</body></html>""", ROOT / "assets/logo/social-preview.png", 1280, 640, transparent=False)
print("done")
