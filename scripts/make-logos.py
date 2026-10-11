# Usage: python3 scripts/make-logos.py
# Builds every logo derivative from assets/logo/svg/{shy,colour,colour-cutout,pause,offline}.svg:
#   - white variants (for dark backgrounds)
#   - transparent PNGs in assets/logo/png
#   - menu bar template images, the About logo and the app icon in App/Assets.xcassets
#   - the GitHub social preview (assets/logo/social-preview.png)
# Rasterizes with headless Google Chrome.
import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SVG = ROOT / "assets/logo/svg"
PNG = ROOT / "assets/logo/png"
ASSETS = ROOT / "App/Assets.xcassets"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
MONO = ["shy", "pause", "offline"]
SIZES = [1024, 512, 256, 128, 64, 32, 16]
# Menu bar crop: 21:16, tight around the cloud (y 160–840) plus the offline slash.
MENU_VIEWBOX = "0 125 1000 761.9"
MENU_PT = (21, 16)

tmp = pathlib.Path(tempfile.mkdtemp())


def render(svg: pathlib.Path, out: pathlib.Path, w: int, h: int, html_extra: str = "") -> None:
    page = tmp / "r.html"
    page.write_text(f'<html><body style="margin:0;background:transparent">'
                    f'<img src="{svg.as_uri()}" width="{w}" height="{h}" style="display:block">{html_extra}</body></html>')
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--default-background-color=00000000",
                    f"--window-size={w},{h}", f"--screenshot={out}", page.as_uri()],
                   check=True, capture_output=True)


def recolor(text: str, color: str) -> str:
    # Visible paint only; mask contents (#fff/#000 inside <mask>) keep their meaning.
    head, sep, rest = text.partition("</defs>")
    if not sep:
        head, rest = "", text
    return head + sep + rest.replace('"#000"', f'"{color}"')


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


# White variants
for n in MONO:
    (SVG / f"{n}-white.svg").write_text(recolor((SVG / f"{n}.svg").read_text(), "#fff"))

# Transparent PNGs
PNG.mkdir(parents=True, exist_ok=True)
for n in MONO + [f"{m}-white" for m in MONO] + ["colour", "colour-cutout"]:
    for s in SIZES:
        render(SVG / f"{n}.svg", PNG / f"{n}-{s}.png", s, s)

# Menu bar template images (tight crop)
for n in MONO:
    cropped = tmp / f"menu-{n}.svg"
    text = (SVG / f"{n}.svg").read_text()
    text = re.sub(r'width="1000" height="1000" viewBox="[^"]+"',
                  f'width="1000" height="761.9" viewBox="{MENU_VIEWBOX}"', text, count=1)
    cropped.write_text(text)
    name = f"MenuBar{n.capitalize()}"
    files = {}
    for scale in (1, 2, 3):
        f = f"{name}@{scale}x.png" if scale > 1 else f"{name}.png"
        files[f"{scale}x"] = f
    folder = imageset(name, files, template=True)
    for scale_str, f in files.items():
        k = int(scale_str[0])
        render(cropped, folder / f, MENU_PT[0] * k, MENU_PT[1] * k)

# About logo: colour mark cropped to the cloud (1.28:1) with room for a soft shadow
ABOUT_PT = (128, 100)
cropped = tmp / "about.svg"
cropped.write_text(re.sub(r'width="1000" height="1000" viewBox="[^"]+"',
                          'width="1000" height="781.25" viewBox="-60 105 1120 875"',
                          (SVG / "colour.svg").read_text(), count=1))
folder = imageset("Logo", {"1x": "Logo.png", "2x": "Logo@2x.png"}, template=False)
for f, k in (("Logo.png", 1), ("Logo@2x.png", 2)):
    w, h = ABOUT_PT[0] * k, ABOUT_PT[1] * k
    page = tmp / "logo.html"
    page.write_text(f'<html><body style="margin:0;background:transparent">'
                    f'<img src="{cropped.as_uri()}" width="{w}" height="{h}" style="display:block;'
                    f'filter:drop-shadow(0 {3 * k}px {4 * k}px rgba(0,60,170,.28))"></body></html>')
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--default-background-color=00000000", f"--window-size={w},{h}",
                    f"--screenshot={folder / f}", page.as_uri()], check=True, capture_output=True)

# App icon: assets/logo/svg/app-icon.svg (blue tile, white cloud, blue lettering) on Apple's 1024 grid
icon_dir = ASSETS / "AppIcon.appiconset"
for old in icon_dir.glob("*.png"):
    old.unlink()
icon_page = tmp / "icon.html"
icon_page.write_text(f'<html><body style="margin:0;background:transparent">'
                     f'<div style="position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;'
                     f'box-shadow:0 10px 22px rgba(0,0,0,.22)"></div>'
                     f'<img src="{(SVG / "app-icon.svg").as_uri()}" width="1024" height="1024" '
                     f'style="position:absolute;left:0;top:0"></body></html>')
master = tmp / "icon-1024.png"
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                "--default-background-color=00000000", "--window-size=1024,1024", f"--screenshot={master}",
                icon_page.as_uri()], check=True, capture_output=True)
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

# GitHub social preview (1280×640; GitHub may crop ~40px, so content stays inside)
logo = (SVG / "colour.svg").as_uri()
# Background puffs: the bare cloud silhouette (first subpath of the mark), no lettering.
cloud = re.search(r' d="(M[^M]+)', (SVG / "shy.svg").read_text()).group(1)
(tmp / "puff.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">'
                              f'<path fill="#fff" d="{cloud}"/></svg>')
puff = (tmp / "puff.svg").as_uri()
page = tmp / "social.html"
jaro = (ROOT / "App/Fonts/Jaro.ttf").as_uri()
page.write_text(f"""<html><head><style>
@font-face {{ font-family:Jaro; src:url("{jaro}"); }}
body {{ margin:0; width:1280px; height:640px; overflow:hidden; position:relative;
  font-family:-apple-system,'SF Pro Display',Helvetica,sans-serif;
  background: radial-gradient(120% 90% at 18% 20%, #ffffff 0%, #eaf6ff 45%, #d3e9ff 100%); }}
.puff {{ position:absolute; opacity:.55; filter:blur(2px); }}
.wrap {{ position:absolute; inset:0; display:flex; align-items:center; gap:64px; padding:0 104px; }}
.logo {{ width:380px; height:380px; flex:none; filter:drop-shadow(0 24px 34px rgba(0,70,190,.28)); }}
h1 {{ margin:0; font-family:Jaro; font-size:150px; font-weight:400; letter-spacing:0; line-height:1.1; padding-bottom:.08em; margin-bottom:-.12em;
  background:linear-gradient(180deg,#0b1d33,#16365c); -webkit-background-clip:text; color:transparent; }}
p {{ margin:22px 0 34px; font-size:38px; line-height:1.22; color:#38536e; font-weight:500; max-width:600px; }}
.chips {{ display:flex; gap:12px; flex-wrap:wrap; }}
.chip {{ font-size:22px; font-weight:600; color:#0a5bd6; background:rgba(255,255,255,.75);
  border:1.5px solid rgba(10,108,255,.18); border-radius:999px; padding:10px 20px; }}
.url {{ position:absolute; right:104px; bottom:52px; font-size:22px; color:#6b84a0; font-weight:500; }}
</style></head><body>
<img class="puff" src="{puff}" style="width:420px;left:-120px;bottom:-150px;opacity:.7">
<img class="puff" src="{puff}" style="width:300px;right:-60px;top:-110px">
<div class="wrap"><img class="logo" src="{logo}">
<div><h1>shyCloud</h1><p>Pause iCloud Drive sync<br>on your Mac, on a schedule.</p>
<div class="chips"><span class="chip">Free &amp; open source</span><span class="chip">Apple Silicon</span>
<span class="chip">No tracking</span></div></div></div>
<div class="url">github.com/ekremus/shycloud</div>
</body></html>""")
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                "--window-size=1280,640", f"--screenshot={ROOT / 'assets/logo/social-preview.png'}", page.as_uri()],
               check=True, capture_output=True)
print("done")
