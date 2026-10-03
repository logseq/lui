#!/usr/bin/env python3
"""Author Logseq icon scenes (.tu) and emit SVGs via tu.

Geometry sources:
- generic icons: Lucide (ISC) 24px-grid geometry, scaled to the 16px grid
  (x2/3) with stroke bumped to 1.5; 24px uses the native geometry, stroke 2.
- Logseq-specific icons: hand-authored here at both sizes.
"""
import json, os, re, subprocess, urllib.request, xml.etree.ElementTree as ET

TU = os.environ.get("TU", "tu")
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = os.path.join(OUT, "scenes")
CACHE = os.path.join(OUT, ".lucide-cache")
os.makedirs(CACHE, exist_ok=True)

LUCIDE = {
  "alert":"triangle-alert","apps":"layout-grid","archive":"archive",
  "arrow-down":"arrow-down","arrow-left":"arrow-left","arrow-right":"arrow-right",
  "arrow-up":"arrow-up","arrow-up-right":"arrow-up-right","book":"book-open",
  "bug":"bug","bulb":"lightbulb","calendar":"calendar","camera":"camera",
  "check":"check","check-circle":"circle-check-big","chevron-down":"chevron-down",
  "chevron-left":"chevron-left","chevron-right":"chevron-right","chevron-up":"chevron-up",
  "circle-dot":"circle-dot","clock":"clock","cloud":"cloud","code":"code",
  "command":"command","copy":"copy","database":"database","download":"download",
  "edit":"square-pen","ellipsis":"ellipsis","ellipsis-vertical":"ellipsis-vertical",
  "external-link":"external-link","eye":"eye","file":"file","file-text":"file-text",
  "filter":"funnel","folder":"folder","folder-open":"folder-open",
  "git-branch":"git-branch","git-merge":"git-merge","git-pull-request":"git-pull-request",
  "grip-vertical":"grip-vertical","hash":"hash","help-circle":"circle-help",
  "history":"history","home":"house","image":"image","inbox":"inbox",
  "info":"info","keyboard":"keyboard","layout-split":"columns-2","link":"link",
  "list":"list","loader":"loader-circle","lock":"lock","logout":"log-out",
  "maximize":"maximize-2","menu":"menu","message-circle":"message-circle",
  "mic":"mic","minus":"minus","mood-smile":"smile","moon":"moon","music":"music",
  "panel-left":"panel-left","panel-right":"panel-right","paperclip":"paperclip",
  "pause":"pause","pin":"pin","play":"play","plug":"plug-2","plus":"plus",
  "quote":"quote","refresh-cw":"refresh-cw","repeat":"repeat","rotate-cw":"rotate-cw",
  "save":"save","search":"search","send":"send","settings":"settings",
  "shuffle":"shuffle","star":"star","sun":"sun","tag":"tag",
  "indent":"list-indent-increase","outdent":"list-indent-decrease","terminal":"terminal","trash":"trash-2","upload":"upload","user":"user",
  "users":"users","volume":"volume-2","waveform":"audio-lines","world":"globe",
  "wrench":"wrench","x":"x","x-circle":"circle-x",
}

# ---------------- path scaling ----------------
NUM = r"-?\d*\.?\d+(?:e-?\d+)?"
ARGS = {"M":2,"L":2,"H":1,"V":1,"C":6,"S":4,"Q":4,"T":2,"A":7,"Z":0}

def tokenize(d):
    return re.findall(r"[MLHVCSTQAZmlhvcstqaz]|" + NUM, d)

def scale_path(d, k, dec=2):
    toks = tokenize(d)
    out, i, x, y, cx, cy = [], 0, 0.0, 0.0, 0.0, 0.0
    last = None
    def f(v): 
        v = round(v * k, dec)
        return int(v) if v == int(v) else v
    while i < len(toks):
        t = toks[i]
        if not re.match(r"^[A-Za-z]$", t):
            # implicit repetition: numbers following a command repeat it
            # (M becomes L). Re-inject the command letter and loop.
            rep = ("l" if last == "m" else "L" if last == "M" else last)
            toks.insert(i, rep)
            continue
        i += 1
        cmd = t; rel = cmd.islower(); C = cmd.upper()
        n = ARGS[C]
        if n == 0:
            out.append("Z"); continue
        # arc flags may be packed into the surrounding digits ("a2 2 0 0022 17"):
        # expand flag positions so each flag is its own single-char token
        if C == "A":
            for j in (i + 3, i + 4):
                t_ = toks[j]
                if len(t_) > 1:
                    toks[j] = t_[0]
                    toks.insert(j + 1, t_[1:])
        args = [float(toks[i+j]) for j in range(n)]; i += n
        res = []
        if C == "H":
            nx = args[0] + (x if rel else 0)
            res = [f(nx)]; x = nx
        elif C == "V":
            ny = args[0] + (y if rel else 0)
            res = [f(ny)]; y = ny
        elif C == "A":
            rx, ry, rot, laf, sf, dx, dy = args
            nx = dx + (x if rel else 0); ny = dy + (y if rel else 0)
            res = [f(rx), f(ry), int(rot) if rot == int(rot) else rot,
                   int(laf), int(sf), f(nx), f(ny)]
            x, y = nx, ny
        else:
            vals = []
            for j in range(0, n, 2):
                ax, ay = args[j], args[j+1]
                nx = ax + (x if rel else 0); ny = ay + (y if rel else 0)
                vals += [f(nx), f(ny)]
                if j == 0 and C in ("S","Q"): pass
                x, y = nx, ny
            res = vals
        out.append(C + " " + " ".join(map(str, res)) if res else C)
        last = cmd
    return " ".join(out)

def svg_inner_scale(svg_text, k):
    """Scale all shape coords in lucide svg by k. Returns list of (tag, attrs)."""
    root = ET.fromstring(svg_text)
    ns = "{http://www.w3.org/2000/svg}"
    els = []
    for e in root:
        tag = e.tag.replace(ns, "")
        a = dict(e.attrib)
        if tag == "path":
            a["d"] = scale_path(a["d"], k)
        elif tag in ("circle", "ellipse"):
            for kk in ("cx","cy","r","rx","ry"):
                if kk in a: a[kk] = round(float(a[kk])*k, 2)
        elif tag in ("line",):
            for kk in ("x1","y1","x2","y2"):
                a[kk] = round(float(a[kk])*k, 2)
        elif tag in ("rect",):
            for kk in ("x","y","width","height","rx","ry"):
                if kk in a: a[kk] = round(float(a[kk])*k, 2)
        elif tag in ("polyline","polygon"):
            a["points"] = " ".join(
                f"{round(float(p.split(',')[0])*k,2)} {round(float(p.split(',')[1])*k,2)}"
                if "," in p else p
                for p in re.split(r"\s+", a["points"].strip()))
        els.append((tag, a))
    return els

def fetch_lucide(name):
    fp = os.path.join(CACHE, name + ".svg")
    if not os.path.exists(fp):
        url = f"https://unpkg.com/lucide-static@1.49.0/icons/{name}.svg"
        urllib.request.urlretrieve(url, fp)
    return open(fp).read()

def child(tag, attrs):
    k = "tu-" + tag if tag in ("path","circle","ellipse","line","rect","polygon","polyline") else "svg-" + tag
    a = {kk: v for kk, v in attrs.items()}
    a["kind"] = k
    return a

STROKE = {"stroke":"currentColor","fill":"none",
          "stroke-linecap":"round","stroke-linejoin":"round"}

def scene(size, children):
    return {"canvas": {"width": size, "height": size},
            "root": {"kind": "stack", "children": children}}

def write_scene(rel, sc):
    fp = os.path.join(SCENES, rel + ".tu")
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    with open(fp, "w") as fh: json.dump(sc, fh, indent=1)
    return fp

def outline_children(size):
    sw = "1.5" if size == 16 else "2"
    return dict(STROKE, **{"stroke-width": sw})

# ---------------- custom icons (authored at 24, scaled to 16) ----------------

def P(d, **kw): return dict(kind="tu-path", d=d, **kw)
def C(cx, cy, r, **kw): return dict(kind="tu-circle", cx=cx, cy=cy, r=r, **kw)
def R(x, y, w, h, rx, **kw): return dict(kind="tu-rect", x=x, y=y, width=w, height=h, rx=rx, **kw)
def fill(**kw): return dict(kw, fill="currentColor")

def scale_children(children, k):
    out = []
    for ch in children:
        c = dict(ch)
        if c["kind"] == "tu-path":
            c["d"] = scale_path(c["d"], k)
        else:
            for kk in ("cx","cy","r","rx","ry","x","y","width","height",
                       "x1","y1","x2","y2"):
                if kk in c: c[kk] = round(float(c[kk]) * k, 2)
        out.append(c)
    return out

CUSTOM24 = {
 # Logseq-specific / no lucide equivalent
 "bullet": [C(12,12,3, **fill())],
 "status-dot": [C(12,12,4.5, **fill())],
 "task-todo": [C(12,12,8.5)],
 "task-doing": [C(12,12,8.5), P("M12 12V3.5A8.5 8.5 0 0 1 20.5 12Z", **fill())],
 "task-done": [C(12,12,8.5), P("M7.8 12.6L10.7 15.5L16.4 9")],
 "task-canceled": [C(12,12,8.5), P("M8.9 8.9L15.1 15.1M15.1 8.9L8.9 15.1")],
 "task-backlog": [C(12,12,8.5, **{"stroke-dasharray":"2.5 3"})],
 "task-review": [C(12,12,8.5), P("M12 7.5V12L15 14.5")],
 "logo": [dict(kind="tu-ellipse", cx=13.4, cy=14.3, rx=5.2, ry=4.4),
          dict(kind="tu-ellipse", cx=7.3, cy=7.7, rx=2.1, ry=2.3),
          dict(kind="tu-ellipse", cx=12.9, cy=6.5, rx=2.2, ry=1.5)],
 "graph": [P("M6.8 5.5L16.7 6.3M5.7 6.9L8.5 17M17.9 8.5L10.9 17.2"),
           C(5,5,2), C(19,6.5,2.5), C(9.5,19,2.2)],
 "keyboard-hide": [R(2.5,5,19,10,2),
                   P("M6 8.5h.01M9.83 8.5h.01M13.67 8.5h.01M17.5 8.5h.01M8 12.5H16"),
                   P("M9.75 19.5L12 21.75L14.25 19.5")],
 "sidebar-toggle": [R(3,4,18,16,2), P("M9.5 4V20"), P("M5.2 10L7.2 12L5.2 14")],
 "cards": [P("M5 6.5V4.5A2 2 0 0 1 7 2.5H18A2 2 0 0 1 20 4.5V13.5A2 2 0 0 1 18 15.5H17.5"),
           P("M8.5 10.5V8.5A2 2 0 0 1 10.5 6.5H19.5A2 2 0 0 1 21.5 8.5V17.5A2 2 0 0 1 19.5 19.5H18"),
           R(3,10.5,14,10.5,2)],
}

# filled variants (24px authorship)
FILLED24 = {
 "bullet": [C(12,12,3, **fill())],
 "status-dot": [C(12,12,4.5, **fill())],
 "circle-dot": [P("M12 20.5A8.5 8.5 0 1 1 12 3.5A8.5 8.5 0 1 1 12 20.5Z "
                  "M12 8A4 4 0 1 0 12 16A4 4 0 1 0 12 8Z",
                  fill="currentColor", **{"fill-rule":"evenodd"}),
                C(12,12,2.25, **fill())],
 "check-circle": [P("M12 20.5A8.5 8.5 0 1 1 12 3.5A8.5 8.5 0 1 1 12 20.5Z "
                    "M7.4 12.1L8.9 10.6L10.7 12.4L15.2 7.9L16.7 9.4L10.7 15.4Z",
                    fill="currentColor", **{"fill-rule":"evenodd"})],
 "x-circle": [P("M12 20.5A8.5 8.5 0 1 1 12 3.5A8.5 8.5 0 1 1 12 20.5Z "
                "M9.4 8L12 10.6L14.6 8L16 9.4L13.4 12L16 14.6L14.6 16L12 13.4"
                "L9.4 16L8 14.6L10.6 12L8 9.4Z",
                fill="currentColor", **{"fill-rule":"evenodd"})],
 "task-done": [P("M12 20.5A8.5 8.5 0 1 1 12 3.5A8.5 8.5 0 1 1 12 20.5Z "
                 "M7.4 12.1L8.9 10.6L10.7 12.4L15.2 7.9L16.7 9.4L10.7 15.4Z",
                 fill="currentColor", **{"fill-rule":"evenodd"})],
 "task-canceled": [P("M12 20.5A8.5 8.5 0 1 1 12 3.5A8.5 8.5 0 1 1 12 20.5Z "
                     "M9.4 8L12 10.6L14.6 8L16 9.4L13.4 12L16 14.6L14.6 16"
                     "L12 13.4L9.4 16L8 14.6L10.6 12L8 9.4Z",
                     fill="currentColor", **{"fill-rule":"evenodd"})],
 "task-doing": [P("M12 12V3.5A8.5 8.5 0 1 0 20.5 12Z", **fill())],
 "play": [P("M7 4.8V19.2A0.8 0.8 0 0 0 8.2 19.8L19.4 12.6A0.8 0.8 0 0 0 19.4 11.4"
            "L8.2 4.2A0.8 0.8 0 0 0 7 4.8Z", **fill())],
 "pause": [R(6.5,5,3.5,14,1.2, **fill()), R(14,5,3.5,14,1.2, **fill())],
 "star": [P("M12 2.6L14.9 8.5L21.3 9.4L16.7 13.9L17.8 20.3L12 17.3L6.2 20.3"
            "L7.3 13.9L2.7 9.4L9.1 8.5Z", **fill())],
}

def stroke_children(base, size):
    """Apply outline stroke props to children that lack fill."""
    sw = "1.5" if size == 16 else "2"
    out = []
    for ch in base:
        c = dict(ch)
        if c.get("fill") == "currentColor":
            pass
        elif c.get("fill") is None or c.get("fill") == "none":
            c.setdefault("fill", "none")
            c["stroke"] = "currentColor"
            c["stroke-width"] = sw
            c["stroke-linecap"] = "round"
            c["stroke-linejoin"] = "round"
        out.append(c)
    return out

def emit(scene_path, svg_path):
    subprocess.run([TU, "emit", scene_path, "-o", svg_path], check=True)
    # strip width/height attrs from root svg tag
    s = open(svg_path).read()
    s = re.sub(r'<svg xmlns="http://www\.w3\.org/2000/svg" width="\d+" height="\d+" ',
               '<svg xmlns="http://www.w3.org/2000/svg" ', s, count=1)
    open(svg_path, "w").write(s)

def main():
    made = []
    # lucide-derived
    for name, lname in sorted(LUCIDE.items()):
        svg = fetch_lucide(lname)
        els24 = svg_inner_scale(svg, 1.0)
        els16 = svg_inner_scale(svg, 2/3)
        for size, els in ((16, els16), (24, els24)):
            kids = []
            for tag, attrs in els:
                ch = child(tag, attrs)
                for drop in ("stroke","stroke-width","stroke-linecap",
                             "stroke-linejoin","fill"):
                    ch.pop(drop, None)
                ch.update(outline_children(size))
                kids.append(ch)
            rel = f"{size}/{name}"
            write_scene(rel, scene(size, kids))
            made.append(rel)
    # custom outline
    for name, kids24 in CUSTOM24.items():
        for size, k in ((16, 2/3), (24, 1.0)):
            kids = scale_children(kids24, k)
            kids = stroke_children(kids, size)
            write_scene(f"{size}/{name}", scene(size, kids))
            made.append(f"{size}/{name}")
    # filled
    for name, kids24 in FILLED24.items():
        for size, k in ((16, 2/3), (24, 1.0)):
            kids = scale_children(kids24, k)
            write_scene(f"{size}/filled/{name}", scene(size, kids))
            made.append(f"{size}/filled/{name}")
    # emit all scenes to svg
    for size in (16, 24):
        sdir = os.path.join(SCENES, str(size))
        for fn in sorted(os.listdir(sdir)):
            fp = os.path.join(sdir, fn)
            if fn.endswith(".tu"):
                emit(fp, os.path.join(OUT, str(size), fn.replace(".tu",".svg")))
            elif fn == "filled":
                for f2 in sorted(os.listdir(fp)):
                    emit(os.path.join(fp, f2),
                         os.path.join(OUT, str(size), "filled", f2.replace(".tu",".svg")))
    print(f"{len(made)} scenes, emitted")

if __name__ == "__main__":
    main()
