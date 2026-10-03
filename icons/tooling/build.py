#!/usr/bin/env python3
"""Build the Logseq icon companion site + validate the set.

Reads icons/{16,24}/*.svg and icons/{16,24}/filled/*.svg, merges
icons/metadata.json (tags + product aliases), writes icons/site/index.html.

With --emit, first recompiles every scene in icons/scenes/{16,24} to SVG
via the tu CLI (tu binary from $TU or PATH). Emitted SVGs get their
root width/height attributes stripped (consumers size icons themselves).
"""
import json, os, re, shutil, subprocess, sys, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = json.load(open(os.path.join(ROOT, "metadata.json")))

STROKE = {16: "1.5", 24: "2"}

def emit_scenes():
    tu = os.environ.get("TU") or shutil.which("tu")
    if not tu:
        print("WARN: tu not found ($TU or PATH) — skipping scene emit",
              file=sys.stderr)
        return
    sdir = os.path.join(ROOT, "scenes")
    n = 0
    for size in (16, 24):
        for sub in ("", "filled"):
            d = os.path.join(sdir, str(size), sub)
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                if not f.endswith(".tu"):
                    continue
                out = os.path.join(ROOT, str(size), sub,
                                   f.replace(".tu", ".svg"))
                subprocess.run([tu, "emit", os.path.join(d, f),
                                "-o", out], check=True)
                s = open(out).read()
                s = re.sub(r'<svg xmlns="http://www\.w3\.org/2000/svg" '
                           r'width="\d+" height="\d+" ',
                           '<svg xmlns="http://www.w3.org/2000/svg" ',
                           s, count=1)
                open(out, "w").write(s)
                n += 1
    print(f"emitted {n} SVGs from scenes")

def read_svg(path):
    return open(path).read().strip()

def inner(svg):
    m = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S)
    return m.group(1).strip() if m else svg

def collect():
    icons = {}
    for size in (16, 24):
        d = os.path.join(ROOT, str(size))
        for f in sorted(os.listdir(d)):
            if f.endswith(".svg"):
                name = f[:-4]
                icons.setdefault(name, {})[f"o{size}"] = read_svg(os.path.join(d, f))
        fd = os.path.join(d, "filled")
        if os.path.isdir(fd):
            for f in sorted(os.listdir(fd)):
                if f.endswith(".svg"):
                    name = f[:-4]
                    icons.setdefault(name, {})[f"f{size}"] = read_svg(os.path.join(fd, f))
    return icons

def validate(icons):
    errs = []
    for name, variants in icons.items():
        for key, svg in variants.items():
            if "stroke-width=\"0\"" in svg or "opacity=\"0\"" in svg:
                errs.append(f"{name}/{key}: leftover hidden geometry")
            if key.startswith("o"):
                if "stroke=" not in svg:
                    # fill-only glyph (bullet, status-dot): not a stroked icon
                    if 'fill="currentColor"' not in svg:
                        errs.append(f"{name}/{key}: fill-only glyph should fill=currentColor")
                    continue
                w = STROKE[int(key[1:])]
                if f'stroke-width="{w}"' not in svg:
                    errs.append(f"{name}/{key}: wrong stroke-width")
                if 'fill="none"' not in svg:
                    errs.append(f"{name}/{key}: outline should fill=none")
                if 'stroke-linecap="round"' not in svg:
                    errs.append(f"{name}/{key}: missing round caps")
            else:
                if 'fill="currentColor"' not in svg:
                    errs.append(f"{name}/{key}: filled should fill=currentColor")
    return errs

def build_site(icons):
    cells = []
    for name in sorted(icons):
        v = icons[name]
        m = META.get(name, {})
        tags = m.get("tags", [])
        aliases = m.get("aliases", [])
        parts = []
        for key, label in (("o16", 16), ("o24", 24), ("f16", 16), ("f24", 24)):
            if key in v:
                filled = "f" if key[0] == "f" else "o"
                parts.append(dict(key=key, size=label, style=("filled" if key[0]=="f" else "outline"),
                                  svg=v[key], inner=inner(v[key])))
        cells.append(dict(name=name, tags=tags, aliases=aliases, variants=parts))
    data = json.dumps(cells)
    return TEMPLATE.replace("__DATA__", data)

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Logseq Icons</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root {
    --bg: #fafafa; --fg: #1a1a1a; --muted: #777; --line: #e4e4e4; --cell: #fff;
    --chip: #f0f0f0;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #141414; --fg: #e8e8e8; --muted: #999; --line: #2a2a2a; --cell: #1c1c1c; --chip: #262626; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; font: 14px/1.5 -apple-system, "SF Pro Text", system-ui, sans-serif;
         background: var(--bg); color: var(--fg); }
  header { position: sticky; top: 0; z-index: 10; background: var(--bg);
           border-bottom: 1px solid var(--line); padding: 14px 24px;
           display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
  h1 { font-size: 16px; font-weight: 600; margin: 0; letter-spacing: -.01em; }
  .sub { color: var(--muted); font-size: 12.5px; }
  input[type=search] { flex: 1; min-width: 160px; max-width: 340px; padding: 7px 12px;
    border: 1px solid var(--line); border-radius: 8px; background: var(--cell); color: var(--fg);
    font: inherit; outline: none; }
  input[type=search]:focus { border-color: var(--muted); }
  .seg { display: flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
  .seg button { padding: 6px 12px; border: 0; background: transparent; color: var(--muted);
    font: inherit; font-size: 12.5px; cursor: pointer; }
  .seg button.on { background: var(--chip); color: var(--fg); }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(128px, 1fr));
          gap: 1px; background: var(--line); padding: 1px; }
  .cell { background: var(--bg); padding: 18px 8px 12px; text-align: center; position: relative;
          cursor: default; min-height: 96px; display: flex; flex-direction: column;
          align-items: center; justify-content: flex-end; gap: 8px; }
  .cell:hover { background: var(--cell); }
  .cell svg { color: var(--fg); }
  .cell .nm { font-size: 11px; color: var(--muted); font-family: ui-monospace, "SF Mono", monospace; }
  .cell:hover .nm { color: var(--fg); }
  .count { color: var(--muted); font-size: 12.5px; }
  .empty { padding: 60px; text-align: center; color: var(--muted); display: none; }
</style>
</head>
<body>
<header>
  <div>
    <h1>Logseq Icons</h1>
    <div class="sub">one set · two sizes · two styles</div>
  </div>
  <input id="q" type="search" placeholder="Search icons, tags, concepts…" autofocus>
  <div class="seg" id="size">
    <button data-v="16" class="on">16px</button><button data-v="24">24px</button>
  </div>
  <div class="seg" id="zoom">
    <button data-v="1" class="on">1×</button><button data-v="2">2×</button><button data-v="3">3×</button>
  </div>
  <div class="seg" id="style">
    <button data-v="outline" class="on">Outline</button><button data-v="filled">Filled</button>
  </div>
  <span class="count" id="count"></span>
</header>
<div class="grid" id="grid"></div>
<div class="empty" id="empty">No icons match.</div>
<script>
const DATA = __DATA__;
const grid = document.getElementById('grid');
const q = document.getElementById('q');
const countEl = document.getElementById('count');
const emptyEl = document.getElementById('empty');
let size = 16, style = 'outline', zoom = 1;
function pick(v) {
  // prefer requested style+size; fall back outline same size; then any
  const want = (style === 'filled' ? 'f' : 'o') + size;
  return v.find(x => x.key === want) ||
         v.find(x => x.key === 'o' + size) ||
         v.find(x => x.key === 'o16') || v[0];
}
function render() {
  const term = q.value.trim().toLowerCase();
  let shown = 0;
  grid.innerHTML = '';
  for (const icon of DATA) {
    const hay = [icon.name, ...icon.tags, ...icon.aliases].join(' ').toLowerCase();
    if (term && !hay.includes(term)) continue;
    const v = pick(icon.variants);
    const div = document.createElement('div');
    div.className = 'cell';
    div.title = icon.name + (icon.aliases.length ? '  ·  ' + icon.aliases.join(', ') : '');
    div.innerHTML = v.svg.replace('<svg ', `<svg width="${size * zoom}" height="${size * zoom}" `) +
                    `<div class="nm">${icon.name}</div>`;
    grid.appendChild(div);
    shown++;
  }
  countEl.textContent = shown + ' icons';
  emptyEl.style.display = shown ? 'none' : 'block';
}
for (const id of ['size', 'style', 'zoom']) {
  document.getElementById(id).addEventListener('click', e => {
    if (e.target.tagName !== 'BUTTON') return;
    for (const b of e.currentTarget.children) b.classList.remove('on');
    e.target.classList.add('on');
    if (id === 'size') size = +e.target.dataset.v; else if (id === 'zoom') zoom = +e.target.dataset.v; else style = e.target.dataset.v;
    render();
  });
}
q.addEventListener('input', render);
render();
</script>
</body>
</html>
"""

def main():
    if "--emit" in sys.argv:
        emit_scenes()
    icons = collect()
    errs = validate(icons)
    for e in errs:
        print("WARN", e, file=sys.stderr)
    out = build_site(icons)
    site = os.path.join(ROOT, "site")
    os.makedirs(site, exist_ok=True)
    open(os.path.join(site, "index.html"), "w").write(out)
    n16 = sum(1 for v in icons.values() if "o16" in v)
    n24 = sum(1 for v in icons.values() if "o24" in v)
    nf = sum(1 for v in icons.values() if "f16" in v or "f24" in v)
    print(f"{len(icons)} icons — {n16}@16, {n24}@24, {nf} with filled")
    if errs:
        sys.exit(1)

if __name__ == "__main__":
    main()
