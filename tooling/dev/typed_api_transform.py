#!/usr/bin/env python3
"""One-shot transform for the typed-DSL refactor of src/lui_elements.{ml,mli}
and its callers (examples/gallery, examples/todos, test/test_lui.ml).
split/drawer/input_group call-site arity changes are done manually after."""
import re, pathlib

ROOT = pathlib.Path("/Users/devin/repos/lui")

ICON_NAMES = """alert archive arrow-down arrow-right arrow-up check check-circle
chevron-down chevron-left chevron-right chevron-up circle-dot clock copy
download edit ellipsis external-link eye file-text folder folder-open
git-branch git-merge git-pull-request info menu mic moon music panel-left
panel-right pause play plus refresh-cw repeat save search send settings
shuffle skip-back skip-forward sun terminal trash volume wrench x x-circle""".split()

def ocaml_tag(name):
    return "`" + name.replace("-", "_")

ICON_TYPE = "type icon =\n  [ " + " | ".join(ocaml_tag(n) for n in ICON_NAMES) + "\n  | `app of string ]"
ICON_CONV = "let icon_value : icon -> string = function\n  | `app name -> \"app:\" ^ name\n" + "\n".join(
    f"  | {ocaml_tag(n)} -> \"{n}\"" for n in ICON_NAMES)

TYPES_ML = '''
(* Closed vocabularies from the wire schema: fixed-value props are typed as
   polymorphic variants so invalid values fail [dune build] instead of
   erroring inside [emit_patch] at emit time. [icon] also accepts
   [`app of string] for application-registered SF Symbol names. *)

type variant =
  [ `default | `primary | `secondary | `outline | `ghost | `destructive ]

type control_size = [ `default | `sm | `lg | `icon ]
type text_size = [ `heading | `display ]
type cell_size = [ control_size | text_size ]
type main_alignment = [ `start | `center | `end_ | `space_between ]
type cross_alignment = [ `stretch | `start | `center | `end_ ]
type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `end_ | `stretch ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]

''' + ICON_TYPE + '''

(* Element kinds the schema restricts to specific parents: these types are
   abstract in the .mli so [stepper], [timeline], [bottom_tabs], [table],
   [table_row], [radio_group] and [input_group] can require them and illegal
   nesting fails at compile time. *)

type step_el = t
type timeline_item_el = t
type bottom_tab_el = t
type table_row_el = t
type table_cell_el = t
type radio_el = t
type input_group_actions_el = t

(* Children slot of leaf elements: the only inhabitant is [[]], so any real
   child fails [dune build] instead of being rejected by the schema at emit. *)
type nothing = |

let variant_value : variant -> string = function
  | `default -> "default"
  | `primary -> "primary"
  | `secondary -> "secondary"
  | `outline -> "outline"
  | `ghost -> "ghost"
  | `destructive -> "destructive"

let control_size_value : control_size -> string = function
  | `default -> "default"
  | `sm -> "sm"
  | `lg -> "lg"
  | `icon -> "icon"

let text_size_value : text_size -> string = function
  | `heading -> "heading"
  | `display -> "display"

let cell_size_value : cell_size -> string = function
  | #control_size as size -> control_size_value size
  | #text_size as size -> text_size_value size

let main_alignment_value : main_alignment -> string = function
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"
  | `space_between -> "space_between"

let cross_alignment_value : cross_alignment -> string = function
  | `stretch -> "stretch"
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"

let text_alignment_value : text_alignment -> string = function
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"

let orientation_value : orientation -> string = function
  | `horizontal -> "horizontal"
  | `vertical -> "vertical"

let icon_placement_value : icon_placement -> string = function
  | `leading -> "leading"
  | `trailing -> "trailing"
  | `top -> "top"

let anchor_value : anchor -> string = function
  | `above -> "above"
  | `below -> "below"
  | `left -> "left"
  | `right -> "right"

let anchor_alignment_value : anchor_alignment -> string = function
  | `start -> "start"
  | `end_ -> "end"
  | `stretch -> "stretch"

let frame_axes_value : frame_axes -> string = function
  | `horizontal -> "horizontal"
  | `vertical -> "vertical"
  | `both -> "both"
  | `min_horizontal -> "min-horizontal"
  | `min_vertical -> "min-vertical"
  | `min_both -> "min-both"

let resize_easing_value : resize_easing -> string = function
  | `linear -> "linear"
  | `standard -> "standard"
  | `emphasized -> "emphasized"
  | `spring -> "spring"

let role_value : role -> string = function
  | `treeitem -> "treeitem"
  | `navigation -> "navigation"
  | `navigation_heading -> "navigation-heading"

''' + ICON_CONV + "\n"

TYPES_MLI = '''
(** Closed vocabularies from the wire schema: every parameter that only
    accepts a fixed set of values is a polymorphic variant so wrong values
    fail [dune build] instead of erroring inside [emit_patch]. *)

type variant =
  [ `default | `primary | `secondary | `outline | `ghost | `destructive ]

type control_size = [ `default | `sm | `lg | `icon ]
type text_size = [ `heading | `display ]

(** [table_cell] accepts control sizes and text sizes on its [~size]. *)
type cell_size = [ control_size | text_size ]

type main_alignment = [ `start | `center | `end_ | `space_between ]
type cross_alignment = [ `stretch | `start | `center | `end_ ]
type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `end_ | `stretch ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]

(** [~icon]/[~name] values: the schema icon names, or [`app "name"] for an
    application-registered icon ([app:name] on the wire). *)
''' + ICON_TYPE + '''

(** Element kinds the schema restricts to specific parents. These are
    abstract so illegal nesting fails at compile time: [step_el] inside
    [stepper], [timeline_item_el] inside [timeline], [bottom_tab_el] inside
    [bottom_tabs], [table_row_el] inside [table], [table_cell_el] inside
    [table_row], [radio_el] inside [radio_group], and
    [input_group_actions_el] as the optional [~actions] of [input_group]. *)

type step_el
type timeline_item_el
type bottom_tab_el
type table_row_el
type table_cell_el
type radio_el
type input_group_actions_el

(** Empty type: [leaf] constructors take a [nothing list] children slot, so
    [] compiles and any real child is a type error. *)
type nothing = |
'''

LEAVES = ["heading", "paragraph", "label", "progress", "divider", "separator",
          "spacer", "spinner", "icon", "avatar", "image", "media_surface",
          "tooltip", "status_bar", "step", "timeline_item"]


def transform_ml(src):
    src = src.replace(
        "type t = Lui_ui.ui_context -> int option -> int\n",
        "type t = Lui_ui.ui_context -> int option -> int\n" + TYPES_ML, 1)

    conv = {
        "MainAlignment": ("main", "main_alignment_value"),
        "CrossAlignment": ("cross", "cross_alignment_value"),
        "ContainerRelativeFrameValue": ("container_relative_frame", "frame_axes_value"),
        "VariantValue": ("variant", "variant_value"),
        "InlineIconName": ("icon", "icon_value"),
        "IconPlacementValue": ("icon_placement", "icon_placement_value"),
        "TextAlignment": ("text_alignment", "text_alignment_value"),
        "OrientationValue": ("orientation", "orientation_value"),
        "RoleValue": ("role", "role_value"),
        "AnchorValue": ("anchor", "anchor_value"),
        "AnchorAlignmentValue": ("anchor_alignment", "anchor_alignment_value"),
        "ResizeEasing": ("resize_easing", "resize_easing_value"),
    }
    for prop, (var, fn) in conv.items():
        old = f"Option.iter (Lui_ui.string_property context node {prop}) {var};"
        new = f"Option.iter (Lui_ui.string_property context node {prop}) (Option.map {fn} {var});"
        n = src.count(old)
        src = src.replace(old, new)
        if n:
            print(f"  {prop}: {n} sites")

    src = src.replace(
        "Option.iter (Lui_ui.string_property context node SizeValue) size;",
        "Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);")
    tc = re.search(r"(let table_cell\s[^=]*=.*?)(?=\nlet )", src, re.S)
    assert tc, "table_cell fn not found"
    seg = tc.group(1).replace("control_size_value size", "cell_size_value size")
    src = src[:tc.start(1)] + seg + src[tc.end(1):]

    src = src.replace(
        "Option.iter (Lui_ui.string_property_signal context node IconName) name_signal;",
        "Option.iter (fun signal -> Lui_ui.string_property_signal context node IconName (Signal.map icon_value signal)) name_signal;")
    src = src.replace(
        "Option.iter (Lui_ui.string_property context node IconName) name;",
        "Option.iter (Lui_ui.string_property context node IconName) (Option.map icon_value name);")

    for name in LEAVES:
        pat = re.compile(r"(let " + name + r"\s[^=]*?)\(children : t list\)( : t =\n fun context parent ->.*?)(?=\nlet |\Z)", re.S)
        m = pat.search(src)
        assert m, f"{name} not found"
        body = m.group(2)
        assert "mount_children context node children;" in body, f"{name} no mount_children"
        body = body.replace("mount_children context node children;", "")
        src = src[:m.start()] + m.group(1) + "(children : nothing list)" + body + src[m.end():]
        print(f"  leaf: {name}")

    for name, elt in {"stepper": "step_el", "timeline": "timeline_item_el",
                      "bottom_tabs": "bottom_tab_el", "table": "table_row_el",
                      "table_row": "table_cell_el", "radio_group": "radio_el"}.items():
        idx = src.index(f"let {name} ")
        hdr_end = src.index("(children : t list)", idx)
        src = src[:hdr_end] + f"(children : {elt} list)" + src[hdr_end + len("(children : t list)"):]

    for name, elt in {"bottom_tab": "bottom_tab_el", "table_row": "table_row_el",
                      "table_cell": "table_cell_el", "radio": "radio_el",
                      "input_group_actions": "input_group_actions_el"}.items():
        pat = re.compile(r"(let " + name + r"\s[^=]*?\(children : [a-z_]+ list\)) : t =")
        src, n = pat.subn(r"\1 : " + elt + " =", src)
        print(f"  return {name}: {n}")
        assert n == 1, name
    for name, elt in [("step", "step_el"), ("timeline_item", "timeline_item_el")]:
        pat = re.compile(r"(let " + name + r"\s[^=]*?) : t =\n fun context parent ->")
        src, n = pat.subn(r"\1 : " + elt + " =\n fun context parent ->", src)
        print(f"  leaf-ret {name}: {n}")
        assert n == 1, name

    for name in ["split", "drawer"]:
        pat = re.compile(r"(let " + name + r"\s[^=]*?)\(children : t list\)( : t =\n fun context parent ->.*?)(?=\nlet |\Z)", re.S)
        m = pat.search(src)
        assert m, name
        body = m.group(2).replace(
            "mount_children context node children;",
            "ignore (first context (Some node));\n  ignore (second context (Some node));")
        assert "ignore (first context (Some node));" in body, name
        src = src[:m.start()] + m.group(1) + "(first : t) (second : t)" + body + src[m.end():]
        print(f"  two-child: {name}")

    pat = re.compile(r"(let input_group\s[^=]*?)\(children : t list\)( : t =\n fun context parent ->.*?)(?=\nlet |\Z)", re.S)
    m = pat.search(src)
    assert m, "input_group"
    body = m.group(2).replace(
        "mount_children context node children;",
        "ignore (field context (Some node));\n  Option.iter (fun actions -> ignore (actions context (Some node))) actions;")
    src = src[:m.start()] + m.group(1) + "?actions (field : t)" + body + src[m.end():]
    print("  input_group")

    return src


def transform_mli(src):
    src = src.replace(
        "type t = Lui_ui.ui_context -> int option -> int\n",
        "type t = Lui_ui.ui_context -> int option -> int\n" + TYPES_MLI, 1)

    for old, new in {
        "?main:string": "?main:main_alignment",
        "?cross:string": "?cross:cross_alignment",
        "?container_relative_frame:string": "?container_relative_frame:frame_axes",
        "?variant:string": "?variant:variant",
        "?icon:string": "?icon:icon",
        "?icon_placement:string": "?icon_placement:icon_placement",
        "?text_alignment:string": "?text_alignment:text_alignment",
        "?orientation:string": "?orientation:orientation",
        "?role:string": "?role:role",
        "?anchor:string": "?anchor:anchor",
        "?anchor_alignment:string": "?anchor_alignment:anchor_alignment",
        "?resize_easing:string": "?resize_easing:resize_easing",
        "?name:string": "?name:icon",
        "?name_signal:string Signal.signal": "?name_signal:icon Signal.signal",
    }.items():
        n = src.count(old)
        src = src.replace(old, new)
        print(f"  mli {old}: {n}")

    src = src.replace("?size:string", "?size:control_size")
    tc = re.search(r"(val table_cell\s*:.*?)(?=\nval |\Z)", src, re.S)
    assert tc
    seg = tc.group(1).replace("?size:control_size", "?size:cell_size")
    src = src[:tc.start(1)] + seg + src[tc.end(1):]

    valpat = lambda name: re.compile(r"(val " + name + r"\s*:.*?) -> t list -> t", re.S)

    for name in LEAVES:
        src, n = valpat(name).subn(r"\1 -> nothing list -> t", src)
        print(f"  mli leaf {name}: {n}")
        assert n == 1, name

    tails = {
        "stepper": "step_el list -> t",
        "timeline": "timeline_item_el list -> t",
        "bottom_tabs": "bottom_tab_el list -> t",
        "table": "table_row_el list -> t",
        "table_row": "table_cell_el list -> table_row_el",
        "radio_group": "radio_el list -> t",
        "bottom_tab": "t list -> bottom_tab_el",
        "table_cell": "t list -> table_cell_el",
        "radio": "t list -> radio_el",
        "input_group_actions": "t list -> input_group_actions_el",
    }
    for name, tail in tails.items():
        src, n = valpat(name).subn(r"\1 -> " + tail, src)
        print(f"  mli {name} -> {tail}: {n}")
        assert n == 1, name
    for name, elt in [("step", "step_el"), ("timeline_item", "timeline_item_el")]:
        pat = re.compile(r"(val " + name + r"\s*:.*?) -> nothing list -> t", re.S)
        src, n = pat.subn(r"\1 -> nothing list -> " + elt, src)
        print(f"  mli leaf-ret {name}: {n}")
        assert n == 1, name
    for name in ["split", "drawer"]:
        src, n = valpat(name).subn(r"\1 -> t -> t -> t", src)
        print(f"  mli two {name}: {n}")
        assert n == 1, name
    src, n = valpat("input_group").subn(r"\1 -> ?actions:input_group_actions_el -> t -> t", src)
    print(f"  mli input_group: {n}")
    assert n == 1
    return src


def transform_caller(src):
    def subs(pat, rep):
        nonlocal src
        src = re.sub(pat, rep, src)

    def tag(m):
        return "`" + m.group(1).replace("-", "_") + ("_" if m.group(1) == "end" else "")
    for p in ["main", "cross", "text_alignment"]:
        subs(rf"~{p}:\"(start|center|end|stretch|space_between)\"", lambda m: f"~{p}:" + tag(m))
    subs(r"~variant:\"(default|primary|secondary|outline|ghost|destructive)\"", r"~variant:`\1")
    subs(r"~size:\"(default|sm|lg|icon|heading|display)\"", r"~size:`\1")
    subs(r"~orientation:\"(horizontal|vertical)\"", r"~orientation:`\1")
    subs(r"~icon_placement:\"(leading|trailing|top)\"", r"~icon_placement:`\1")
    subs(r"~role:\"(treeitem|navigation|navigation-heading)\"",
         lambda m: "~role:`" + m.group(1).replace("-", "_"))
    subs(r"~anchor:\"(above|below|left|right)\"", r"~anchor:`\1")
    subs(r"~anchor_alignment:\"(start|end|stretch)\"", lambda m: "~anchor_alignment:" + tag(m))
    subs(r"~container_relative_frame:\"(horizontal|vertical|both|min-horizontal|min-vertical|min-both)\"",
         lambda m: "~container_relative_frame:`" + m.group(1).replace("-", "_"))
    subs(r"~resize_easing:\"(linear|standard|emphasized|spring)\"", r"~resize_easing:`\1")
    icon_alt = "|".join(ICON_NAMES)
    subs(rf"~icon:\"({icon_alt})\"", lambda m: "~icon:`" + m.group(1).replace("-", "_"))
    subs(rf"~name:\"({icon_alt})\"", lambda m: "~name:`" + m.group(1).replace("-", "_"))
    subs(r"~icon:\"app:([a-z0-9-]+)\"", r'~icon:(`app "\1")')
    subs(r"~name:\"app:([a-z0-9-]+)\"", r'~name:(`app "\1")')

    return src


def main():
    ml = (ROOT / "src/lui_elements.ml").read_text()
    mli = (ROOT / "src/lui_elements.mli").read_text()
    print("== .ml ==")
    (ROOT / "src/lui_elements.ml").write_text(transform_ml(ml))
    print("== .mli ==")
    (ROOT / "src/lui_elements.mli").write_text(transform_mli(mli))
    for f in ["examples/gallery/view.ml", "examples/todos/view.ml", "test/test_lui.ml"]:
        p = ROOT / f
        print(f"== {f} ==")
        p.write_text(transform_caller(p.read_text()))

main()
