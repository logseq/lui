#!/usr/bin/env python3
"""Generate src/lui_json_view.ml from src/lui_elements.mli.

The generated module renders a language-neutral view-model value
(JSON-shaped) into LUI elements — the generic layer dynamic/plugin
frontends (e.g. meng's JS plugins) target so the full cross-platform
component vocabulary is reachable without hand-mapping each
constructor. Regenerate after changing lui_elements.mli:

    python3 tools/gen_json_view.py
"""
import re

MLI = 'src/lui_elements.mli'
OUT = 'src/lui_json_view.ml'

# universal optional args shared by every element constructor; emitted
# through the parsed `sty` record
UNIVERSAL_ARG = {
    'key': 's.s_key', 'gap': 's.s_gap', 'main': 's.s_main',
    'cross': 's.s_cross', 'grow': 's.s_grow', 'columns': 's.s_columns',
    'padding': 's.s_pad', 'padding_horizontal': 's.s_pad_h',
    'padding_vertical': 's.s_pad_v', 'background': 's.s_bg',
    'foreground': 's.s_fg', 'border_color': 's.s_border_color',
    'border_width': 's.s_border_width', 'corner_radius': 's.s_radius',
    'width': 's.s_width', 'height': 's.s_height',
    'min_width': 's.s_min_width', 'max_width': 's.s_max_width',
    'min_height': 's.s_min_height', 'max_height': 's.s_max_height',
    'container_relative_frame':
        '(frame_axes_opt (v_str props "container-relative-frame"))',
    'container_relative_frame_inset':
        '(v_int props "container-relative-frame-inset")',
    'accessibility_identifier': '(v_str props "accessibility-identifier")',
    'style_class': 's.s_class',
    'on_appear': '(ev "appear" emit props)',
}

EVENT_NAME = {
    'on_press': 'press', 'on_long_press': 'long-press',
    'on_double_press': 'double-press', 'on_toggle': 'toggle',
    'on_input': 'input', 'on_submit': 'submit', 'on_change': 'change',
    'on_dismiss': 'dismiss', 'on_resize': 'resize', 'on_appear': 'appear',
}

ENUM_DECODER = {
    'variant': 'variant_opt', 'control_size': 'control_size_opt',
    'cell_size': 'cell_size_opt', 'main_alignment': 'main_opt',
    'cross_alignment': 'cross_opt', 'text_alignment': 'text_align_opt',
    'orientation': 'orientation_opt', 'icon_placement': 'icon_placement_opt',
    'anchor': 'anchor_opt', 'anchor_alignment': 'anchor_align_opt',
    'frame_axes': 'frame_axes_opt', 'resize_easing': 'resize_easing_opt',
    'role': 'role_opt',
}

SKIP = set('''mount reactive map sample get get_state attach enable
mount_children dynamic dyn if_ keyed press on_input on_event
is_press is_long_press is_double_press is_change is_input is_submit
is_toggle is_dismiss is_appear is_resize register_press
register_long_press register_double_press register_change
register_input register_submit register_toggle register_dismiss
appear_handler register_resize apply_universal'''.split())


def parse_args(body):
    return [(n, ' '.join(t.split()))
            for n, t in re.findall(r'\?(\w+)\s*:\s*([^>\n]+?)(?=\s*->|\?|$)',
                                   body, re.S)]


def kind_of(name):
    n = name[:-1] if name.endswith('_') else name
    return n.replace('_', '-')


def extra_arg(name, typ):
    """?arg application fragment, or None to skip (signals)."""
    j = name.replace('_', '-')
    if 'Signal.signal' in typ:
        return None
    if typ == 'string':
        return f'?{name}:(v_str props "{j}")'
    if typ == 'int':
        return f'?{name}:(v_int props "{j}")'
    if typ == 'float':
        return f'?{name}:(v_float props "{j}")'
    if typ == 'bool':
        return f'?{name}:(v_bool props "{j}")'
    if typ == 'icon':
        return f'?{name}:(icon_prop props "{j}")'
    if typ in ENUM_DECODER:
        return f'?{name}:({ENUM_DECODER[typ]} (v_str props "{j}"))'
    if 'Lui_protocol.event' in typ:
        ev = EVENT_NAME.get(name)
        return f'?{name}:(ev "{ev}" emit props)' if ev else None
    if typ == 'input_group_actions_el':
        return f'?{name}:(actions_of ~emit child_nodes)'
    raise SystemExit(f'unhandled arg type: {name} : {typ}')


def call_args(args):
    parts = []
    for name, typ in args:
        if 'Signal.signal' in typ:
            continue
        if name in UNIVERSAL_ARG:
            parts.append(f'?{name}:{UNIVERSAL_ARG[name]}')
        else:
            frag = extra_arg(name, typ)
            if frag:
                parts.append(frag)
    return ('\n      ' + ' '.join(parts)) if parts else ''


def main():
    mli = open(MLI).read()
    blocks = re.findall(r'val (\w+) :\s*(.*?)(?=\nval |\Z)', mli, re.S)

    normal = []           # arms in `element`
    restricted = []       # (name, kind, args, el_type, cat)
    parents = {}          # constructor -> restricted child el type
    el_to_kind = {}       # el type -> child kind string

    for name, body in blocks:
        if name in SKIP:
            continue
        args = parse_args(body)
        # tail after the last ?arg = the children/return shape
        ms = list(re.finditer(r'\?\w+\s*:\s*', body))
        tail = body[ms[-1].end():] if ms else body
        # drop the last arg's type (paren types may contain inner arrows)
        tail = re.sub(r'^\s*(\([^)]*\)|[\w\.\[\] ]+?)\s*->\s*', '', tail,
                      count=1)
        ret = ' '.join(tail.split())
        kind = kind_of(name)

        ret_children, _, ret_target = ret.rpartition(' -> ')
        if ret_target != 't':
            # constructor returns a restricted *_el type — needs its own
            # builder, only constructible inside its parent
            if ret_children.endswith('_el list'):
                cat = ('restricted_children', ret_children.split()[0])
            elif ret_children == 'nothing list':
                cat = ('leaf', None)
            else:
                cat = ('container', None)
            restricted.append((name, kind, args, ret_target, cat))
            el_to_kind[ret_target] = kind
        elif ret_children.endswith('_el list'):
            parents[name] = ret_children.split()[0]
            normal.append((name, kind, args, ret))
        else:
            normal.append((name, kind, args, ret))

    out = [HEADER, CORE]

    out.append('(* ---------- element dispatch ---------- *)\n\n')
    out.append(
        'let rec element ~emit (node : value) : E.t =\n'
        '  match node with\n'
        '  | Obj fields -> (\n'
        '    let props = props_of fields in\n'
        '    let child_nodes =\n'
        '      match List.assoc_opt "children" fields with\n'
        '      | Some (Arr l) -> l\n'
        '      | _ -> []\n'
        '    in\n'
        '    let children = List.map (element ~emit) child_nodes in\n'
        '    let s = sty_of props in\n'
        '    match kind_of_node fields with\n')

    for name, kind, args, ret in normal:
        kids = kids_expr(name, ret, parents)
        out.append(f'    | "{kind}" ->\n      E.{name}{call_args(args)} {kids}\n')
    for name, kind, _, el_type, _ in restricted:
        out.append(
            f'    | "{kind}" ->\n'
            f'      placeholder "{kind} only inside its parent container"\n')
    out.append('''    | other -> placeholder ("unsupported component: " ^ other))
  | _ -> placeholder "view-model node must be an object"

(* first/second child for split & drawer (t -> t -> t) *)
and child_at ~emit nodes i =
  match List.nth_opt nodes i with
  | Some c -> element ~emit c
  | None -> placeholder "missing child"

(* input-group body: first child that isn't the actions group *)
and body_child ~emit nodes =
  match
    List.find_opt
      (fun c ->
         match c with
         | Obj f -> kind_of_node f <> "input-group-actions"
         | _ -> true)
      nodes
  with
  | Some c -> element ~emit c
  | None -> placeholder "input-group needs a child"

and actions_of ~emit nodes : E.input_group_actions_el option =
  match
    List.find_opt
      (fun c ->
         match c with
         | Obj f -> kind_of_node f = "input-group-actions"
         | _ -> false)
      nodes
  with
  | Some (Obj f) ->
    let kids =
      match List.assoc_opt "children" f with Some (Arr l) -> l | _ -> []
    in
    Some (build_input_group_actions ~emit (props_of f) kids)
  | _ -> None

''')

    # typed child-list builders for restricted parents
    for el_type, kind in el_to_kind.items():
        ctor = next(n for n, k, _, t, _ in restricted if t == el_type)
        out.append(f'''and list_{el_type} ~emit (nodes : value list) : E.{el_type} list =
  List.filter_map
    (fun c ->
       match c with
       | Obj f when kind_of_node f = "{kind}" ->
         Some
           (build_{ctor} ~emit (props_of f)
              (match List.assoc_opt "children" f with
               | Some (Arr l) -> l
               | _ -> []))
       | _ -> None)
    nodes

''')

    # restricted builders
    for name, kind, args, el_type, cat in restricted:
        tag, sub = cat
        if tag == 'restricted_children':
            kids = f'(list_{sub} ~emit child_nodes)'
        elif tag == 'container':
            kids = '(List.map (element ~emit) child_nodes)'
        else:
            kids = '[]'
        param = 'child_nodes' if tag != 'leaf' else '_child_nodes'
        out.append(f'''and build_{name} ~emit props {param} : E.{el_type} =
  let s = sty_of props in
  E.{name}{call_args(args)} {kids}
''')

    out.append(TRAILER)
    open(OUT, 'w').write(''.join(out))
    print(f'wrote {OUT}: {len(normal)} top-level kinds, '
          f'{len(restricted)} restricted kinds')


def kids_expr(name, ret, parents):
    if name in parents:
        return f'(list_{parents[name]} ~emit child_nodes)'
    if ret == 't -> t -> t':
        return '(child_at ~emit child_nodes 0) (child_at ~emit child_nodes 1)'
    if ret == 't -> t':
        return '(body_child ~emit child_nodes)'
    if 'nothing list' in ret:
        return '[]'
    return 'children'


HEADER = '''(* GENERATED by tools/gen_json_view.py — regenerate, don't edit.
   Renders a language-neutral view-model (JSON-shaped [value]) into LUI
   elements: the generic layer plugin/remote frontends target so the
   full cross-platform component vocabulary is reachable without
   hand-mapping each constructor.

   View-model node shape:
     { "kind": "card", ...props, "children": [ ...nodes ] }
   Kind names are the constructor names with [-] for [_]
   ([switch_] is ["switch"]). *)

module E = Lui_elements
module P = Lui_protocol

type value =
  | Null
  | Bool of bool
  | Num of float
  | Str of string
  | Arr of value list
  | Obj of (string * value) list

type node = value

type event_sink =
  id:string -> kind:string -> fields:(string * value) list -> unit
'''

CORE = r'''
(* ---------- value accessors ---------- *)

let get props n = List.assoc_opt n props
let v_str p n = match get p n with Some (Str s) -> Some s | _ -> None
let v_int p n =
  match get p n with Some (Num f) -> Some (int_of_float f) | _ -> None
let v_float p n = match get p n with Some (Num f) -> Some f | _ -> None
let v_bool p n = match get p n with Some (Bool b) -> Some b | _ -> None

let kind_of_node fields =
  match List.assoc_opt "kind" fields with Some (Str k) -> k | _ -> ""

let props_of fields =
  List.filter (fun (n, _) -> n <> "kind" && n <> "children") fields

(* ---------- enum decoders (unknown -> None, never raise) ---------- *)

let variant_opt = function
  | Some "primary" -> Some `primary
  | Some "secondary" -> Some `secondary
  | Some "outline" -> Some `outline
  | Some "ghost" -> Some `ghost
  | Some "destructive" -> Some `destructive
  | Some "default" -> Some `default
  | _ -> None

let control_size_opt = function
  | Some "sm" -> Some `sm
  | Some "lg" -> Some `lg
  | Some "icon" -> Some `icon
  | Some "default" -> Some `default
  | _ -> None

let cell_size_opt = function
  | Some "heading" -> Some `heading
  | Some "display" -> Some `display
  | other -> (control_size_opt other :> E.cell_size option)

let main_opt = function
  | Some "center" -> Some `center
  | Some ("end" | "end_") -> Some `end_
  | Some ("space-between" | "space_between") -> Some `space_between
  | Some "start" -> Some `start
  | _ -> None

let cross_opt = function
  | Some "stretch" -> Some `stretch
  | Some "start" -> Some `start
  | Some "center" -> Some `center
  | Some ("end" | "end_") -> Some `end_
  | _ -> None

let text_align_opt = function
  | Some "center" -> Some `center
  | Some ("end" | "end_") -> Some `end_
  | Some "start" -> Some `start
  | _ -> None

let orientation_opt = function
  | Some "vertical" -> Some `vertical
  | Some "horizontal" -> Some `horizontal
  | _ -> None

let icon_placement_opt = function
  | Some "trailing" -> Some `trailing
  | Some "top" -> Some `top
  | Some "leading" -> Some `leading
  | _ -> None

let anchor_opt = function
  | Some "above" -> Some `above
  | Some "below" -> Some `below
  | Some "left" -> Some `left
  | Some "right" -> Some `right
  | _ -> None

let anchor_align_opt = function
  | Some "start" -> Some `start
  | Some ("end" | "end_") -> Some `end_
  | Some "stretch" -> Some `stretch
  | _ -> None

let frame_axes_opt = function
  | Some "horizontal" -> Some `horizontal
  | Some "vertical" -> Some `vertical
  | Some "both" -> Some `both
  | Some "min-horizontal" -> Some `min_horizontal
  | Some "min-vertical" -> Some `min_vertical
  | Some "min-both" -> Some `min_both
  | _ -> None

let resize_easing_opt = function
  | Some "linear" -> Some `linear
  | Some "standard" -> Some `standard
  | Some "emphasized" -> Some `emphasized
  | Some "spring" -> Some `spring
  | _ -> None

let role_opt = function
  | Some "treeitem" -> Some `treeitem
  | Some "navigation" -> Some `navigation
  | Some "navigation-heading" -> Some `navigation_heading
  | _ -> None

(* schema icon names; unknown -> `app (host-registered icon) *)
let icon_of_string = function
  | "alert" -> Some `alert
  | "archive" -> Some `archive
  | "arrow-down" -> Some `arrow_down
  | "arrow-right" -> Some `arrow_right
  | "arrow-up" -> Some `arrow_up
  | "check" -> Some `check
  | "check-circle" -> Some `check_circle
  | "chevron-down" -> Some `chevron_down
  | "chevron-left" -> Some `chevron_left
  | "chevron-right" -> Some `chevron_right
  | "chevron-up" -> Some `chevron_up
  | "circle-dot" -> Some `circle_dot
  | "clock" -> Some `clock
  | "copy" -> Some `copy
  | "download" -> Some `download
  | "edit" -> Some `edit
  | "ellipsis" -> Some `ellipsis
  | "external-link" -> Some `external_link
  | "eye" -> Some `eye
  | "file-text" -> Some `file_text
  | "folder" -> Some `folder
  | "folder-open" -> Some `folder_open
  | "git-branch" -> Some `git_branch
  | "git-merge" -> Some `git_merge
  | "git-pull-request" -> Some `git_pull_request
  | "info" -> Some `info
  | "menu" -> Some `menu
  | "mic" -> Some `mic
  | "moon" -> Some `moon
  | "music" -> Some `music
  | "panel-left" -> Some `panel_left
  | "panel-right" -> Some `panel_right
  | "pause" -> Some `pause
  | "play" -> Some `play
  | "plus" -> Some `plus
  | "refresh-cw" -> Some `refresh_cw
  | "repeat" -> Some `repeat
  | "save" -> Some `save
  | "search" -> Some `search
  | "send" -> Some `send
  | "settings" -> Some `settings
  | "shuffle" -> Some `shuffle
  | "skip-back" -> Some `skip_back
  | "skip-forward" -> Some `skip_forward
  | "sun" -> Some `sun
  | "terminal" -> Some `terminal
  | "trash" -> Some `trash
  | "volume" -> Some `volume
  | "wrench" -> Some `wrench
  | "x" -> Some `x
  | "x-circle" -> Some `x_circle
  | _ -> None

let icon_prop props name : E.icon option =
  match v_str props name with
  | Some n ->
    (match icon_of_string n with Some _ as i -> i | None -> Some (`app n))
  | None -> None

(* ---------- universal style props ---------- *)

type sty = {
  s_key : string option;
  s_gap : int option;
  s_main : E.main_alignment option;
  s_cross : E.cross_alignment option;
  s_grow : float option;
  s_columns : int option;
  s_pad : int option;
  s_pad_h : int option;
  s_pad_v : int option;
  s_bg : string option;
  s_fg : string option;
  s_border_color : string option;
  s_border_width : int option;
  s_radius : int option;
  s_width : int option;
  s_height : int option;
  s_min_width : int option;
  s_max_width : int option;
  s_min_height : int option;
  s_max_height : int option;
  s_class : string option;
}

let sty_of p =
  {
    s_key = v_str p "key";
    s_gap = v_int p "gap";
    s_main = main_opt (v_str p "main");
    s_cross = cross_opt (v_str p "cross");
    s_grow = v_float p "grow";
    s_columns = v_int p "columns";
    s_pad = v_int p "padding";
    s_pad_h = v_int p "padding-horizontal";
    s_pad_v = v_int p "padding-vertical";
    s_bg = v_str p "background";
    s_fg = v_str p "foreground";
    s_border_color = v_str p "border-color";
    s_border_width = v_int p "border-width";
    s_radius = v_int p "corner-radius";
    s_width = v_int p "width";
    s_height = v_int p "height";
    s_min_width = v_int p "min-width";
    s_max_width = v_int p "max-width";
    s_min_height = v_int p "min-height";
    s_max_height = v_int p "max-height";
    s_class = v_str p "style-class";
  }

(* ---------- events ---------- *)

(* every interaction routes through the node's "id" prop to the event
   sink; the runtime event's payload is decoded into fields *)
let ev name (emit : event_sink) props =
  match v_str props "id" with
  | Some id ->
    Some
      (fun (e : P.event) ->
         let fields =
           match e with
           | P.ToggleChanged (_, checked) -> [ ("checked", Bool checked) ]
           | P.TextChanged (_, text) -> [ ("text", Str text) ]
           | P.ValueChanged (_, v) -> [ ("value", Num v) ]
           | _ -> []
         in
         emit ~id ~kind:name ~fields)
  | None -> None

(* visible fallback for bad kinds — never blank *)
let placeholder msg = E.text ~value:("(" ^ msg ^ ")") []
'''

TRAILER = '''
(* ---------- public API ---------- *)

let render ~(on_event : event_sink) (node : value) : E.t =
  element ~emit:on_event node

(* minimal JSON parser — a host can feed raw JSON without a JSON dep *)
let parse (s : string) : (value, string) result =
  let n = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < n then Some s.[!pos] else None in
  let skip_ws () =
    while
      !pos < n
      && (match s.[!pos] with ' ' | '\\t' | '\\n' | '\\r' -> true | _ -> false)
    do
      incr pos
    done
  in
  let expect c =
    skip_ws ();
    match peek () with
    | Some x when x = c -> incr pos
    | _ -> failwith ("expected " ^ String.make 1 c)
  in
  let rec value () =
    skip_ws ();
    match peek () with
    | Some '{' -> obj ()
    | Some '[' -> arr ()
    | Some '"' -> Str (str ())
    | Some 't' -> lit "true" (Bool true)
    | Some 'f' -> lit "false" (Bool false)
    | Some 'n' -> lit "null" Null
    | Some ('-' | '0' .. '9') ->
      Num
        (float_of_string
           (let st = !pos in
            while
              !pos < n
              && (match s.[!pos] with
                  | '-' | '+' | '.' | 'e' | 'E' | '0' .. '9' -> true
                  | _ -> false)
            do
              incr pos
            done;
            String.sub s st (!pos - st)))
    | _ -> failwith "unexpected character"
  and lit w v =
    if !pos + String.length w <= n
       && String.sub s !pos (String.length w) = w
    then begin
      pos := !pos + String.length w;
      v
    end
    else failwith ("bad literal " ^ w)
  and str () =
    expect '"';
    let b = Buffer.create 32 in
    (try
       while true do
         match s.[!pos] with
         | '"' -> incr pos; raise Exit
         | '\\\\' -> (
           incr pos;
           match s.[!pos] with
           | 'u' ->
             let h = String.sub s (!pos + 1) 4 in
             Buffer.add_utf_8_uchar b
               (Uchar.of_int (int_of_string ("0x" ^ h)));
             pos := !pos + 5
           | 'n' -> Buffer.add_char b '\\n'; incr pos
           | 't' -> Buffer.add_char b '\\t'; incr pos
           | 'r' -> Buffer.add_char b '\\r'; incr pos
           | 'b' -> Buffer.add_char b '\\b'; incr pos
           | 'f' -> Buffer.add_char b '\\012'; incr pos
           | c -> Buffer.add_char b c; incr pos)
         | c -> Buffer.add_char b c; incr pos
       done
     with
     | Exit -> ()
     | Invalid_argument _ -> ());
    Buffer.contents b
  and arr () =
    expect '[';
    skip_ws ();
    let items = ref [] in
    (match peek () with
     | Some ']' -> incr pos
     | _ ->
       (try
          while true do
            items := value () :: !items;
            skip_ws ();
            match peek () with
            | Some ',' -> incr pos
            | _ -> raise Exit
          done
        with _ -> ()));
    skip_ws ();
    (match peek () with Some ']' -> incr pos | _ -> ());
    Arr (List.rev !items)
  and obj () =
    expect '{';
    skip_ws ();
    let fields = ref [] in
    (match peek () with
     | Some '}' -> incr pos
     | _ ->
       (try
          while true do
            skip_ws ();
            let k = str () in
            expect ':';
            fields := (k, value ()) :: !fields;
            skip_ws ();
            match peek () with
            | Some ',' -> incr pos
            | _ -> raise Exit
          done
        with _ -> ()));
    skip_ws ();
    (match peek () with Some '}' -> incr pos | _ -> ());
    Obj (List.rev !fields)
  in
  try
    let v = value () in
    skip_ws ();
    Ok v
  with e -> Error (Printexc.to_string e)
'''

if __name__ == '__main__':
    main()
