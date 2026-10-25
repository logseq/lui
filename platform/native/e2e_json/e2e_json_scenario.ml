(* JSON scenario runner for the headless native e2e driver.

   Each scenario file drives one [E2e_harness] + [Lui_window.Ui] pair
   through a list of steps — patch application, pointer input, text
   input, IME composition, scrolling, drops, and explicit event
   dispatch — and asserts on the recorded event stream, the store, and
   the captured frame. Writing a new e2e test is adding a JSON file. *)

open Lui_scene
open Lui_protocol

module J = Yojson.Safe

exception Fail of string

let failf fmt = Printf.ksprintf (fun s -> raise (Fail s)) fmt

(* ---------- json helpers ---------- *)

let jget (name : string) (j : J.t) : J.t option =
  match j with `Assoc a -> List.assoc_opt name a | _ -> None

let jreq name j =
  match jget name j with
  | Some v -> v
  | None -> failf "missing required field %S in %s" name (J.to_string j)

let jstr name j = J.Util.to_string (jreq name j)

let jint_opt name j =
  match jget name j with
  | Some (`Int i) -> i
  | Some (`Intlit s) -> int_of_string s
  | Some _ -> failf "field %S must be an int" name
  | None -> 0

let jfloat name default j =
  match jget name j with
  | Some (`Int i) -> float_of_int i
  | Some (`Float f) -> f
  | Some (`Intlit s) -> float_of_string s
  | Some _ -> failf "field %S must be a number" name
  | None -> default

let jstr_list name j =
  match jget name j with
  | Some (`List l) -> List.map J.Util.to_string l
  | _ -> []

(* ---------- subset matching ----------

   "*" accepts anything, "~x" is string-contains,
   {"$gt"|"$lt"|"$ge"|"$le": n} compares numbers, and objects match
   recursively by subset. *)

let str_contains hay needle =
  let lh = String.length hay and ln = String.length needle in
  let rec go i =
    if i + ln > lh then false
    else if String.sub hay i ln = needle then true
    else go (i + 1)
  in
  ln = 0 || go 0

let is_comparator fields =
  match fields with
  | [ (("$gt" | "$lt" | "$ge" | "$le"), _) ] -> true
  | _ -> false

let num_of = function
  | `Int i -> Some (float_of_int i)
  | `Float f -> Some f
  | `Intlit s -> Some (float_of_string s)
  | _ -> None

let rec jmatch (expect : J.t) (actual : J.t) : bool =
  match expect with
  | `String "*" -> true
  | `String s when String.length s > 0 && s.[0] = '~' ->
    (match actual with
     | `String a -> str_contains a (String.sub s 1 (String.length s - 1))
     | _ -> false)
  | `String s -> actual = `String s
  | `Assoc fields when is_comparator fields ->
    (match fields with
     | [ (op, n) ] ->
       (match num_of actual, num_of n with
        | Some a, Some b ->
          (match op with
           | "$gt" -> a > b
           | "$lt" -> a < b
           | "$ge" -> a >= b
           | "$le" -> a <= b
           | _ -> false)
        | _ -> false)
     | _ -> false)
  | `Assoc fields ->
    (match actual with
     | `Assoc af ->
       List.for_all
         (fun (k, v) ->
           match List.assoc_opt k af with
           | Some av -> jmatch v av
           | None -> false)
         fields
     | _ -> false)
  | `List es ->
    (match actual with
     | `List as_ ->
       List.length es = List.length as_
       && List.for_all2 jmatch es as_
     | _ -> false)
  | `Int i ->
    (match actual with
     | `Int j -> i = j
     | `Intlit s -> s = string_of_int i
     | `Float f -> f = float_of_int i
     | _ -> false)
  | `Float f ->
    (match actual with
     | `Float g -> f = g
     | `Int j -> f = float_of_int j
     | `Intlit s -> f = float_of_string s
     | _ -> false)
  | `Bool _ | `Null -> expect = actual
  | `Intlit s ->
    (match actual with
     | `Intlit t -> s = t
     | `Int j -> s = string_of_int j
     | _ -> false)

let jmatch_at ~what expect actual =
  if not (jmatch expect actual) then
    failf "%s mismatch\n  expected: %s\n  actual:   %s" what
      (J.to_string expect) (J.to_string actual)

(* ---------- scenario environment ---------- *)

type ctx = {
  h : Lui_e2e.E2e_harness.t;
  ui : Lui_window.Ui.t;
  mutable app : E2e_json_apps.boxed option;
  events : J.t Queue.t;
  scale : float;
  name : string;
}

let store ctx = Lui_e2e.E2e_harness.store ctx.h

(* ---------- value rendering ---------- *)

let wire_json (v : wire_value) : J.t =
  match v with
  | StringValue s -> `String s
  | BoolValue b -> `Bool b
  | IntValue i -> `Int i
  | FloatValue f -> `Float f

let rect_json (r : rect) : J.t =
  `Assoc
    [ ("x", `Float r.x); ("y", `Float r.y)
    ; ("w", `Float r.w); ("h", `Float r.h) ]

let color_json (c : color) : J.t =
  `Assoc
    [ ("r", `Int c.r); ("g", `Int c.g)
    ; ("b", `Int c.b); ("a", `Int c.a) ]

let detail_json (d : pointer_detail) : J.t =
  `Assoc
    [ ("x", `Float d.x); ("y", `Float d.y)
    ; ("modifiers", `Int d.modifiers); ("button", `Int d.button)
    ; ("target-class", `String d.target_class) ]

let event_json (e : event) : J.t =
  let k v = ("kind", `String v) in
  let n v = ("node", `Int v) in
  match e with
  | Press id -> `Assoc [ k "press"; n id ]
  | LongPress id -> `Assoc [ k "long-press"; n id ]
  | DoublePress id -> `Assoc [ k "double-press"; n id ]
  | TextChanged (id, s) ->
    `Assoc [ k "text-changed"; n id; ("text", `String s) ]
  | NavigatePrevious id -> `Assoc [ k "navigate-previous"; n id ]
  | NavigateNext id -> `Assoc [ k "navigate-next"; n id ]
  | NavigationKey (id,key,shift) ->
    `Assoc [k "navigation-key";n id;"key",`String key;"shift",`Bool shift]
  | Submit id -> `Assoc [ k "submit"; n id ]
  | ToggleChanged (id, b) ->
    `Assoc [ k "toggle-changed"; n id; ("checked", `Bool b) ]
  | Change id -> `Assoc [ k "change"; n id ]
  | ValueChanged (id, f) ->
    `Assoc [ k "value-changed"; n id; ("value", `Float f) ]
  | Dismiss id -> `Assoc [ k "dismiss"; n id ]
  | Appear id -> `Assoc [ k "appear"; n id ]
  | ScrollCompleted (id, token, outcome) ->
    `Assoc
      [ k "scroll-completed"; n id; ("token", `Int token)
      ; ("outcome", `String outcome) ]
  | VisibleRange (id, first, last) ->
    `Assoc
      [ k "visible-range"; n id; ("first", `Int first)
      ; ("last", `Int last) ]
  | VirtualWindow (id, generation, first, last, pins) ->
    `Assoc
      [ k "virtual-window"; n id; ("generation", `Int generation)
      ; ("first", `Int first); ("last", `Int last)
      ; ("pins", `List (List.map (fun node -> `Int node) pins)) ]
  | Picked (id, p) ->
    `Assoc [ k "picked"; n id; ("payload", `String p) ]
  | PressModifiers (id, m) ->
    `Assoc [ k "press-modifiers"; n id; ("modifiers", `Int m) ]
  | PressDetail (id, d) ->
    (match detail_json d with
     | `Assoc a -> `Assoc (("kind", `String "press-detail") :: n id :: a)
     | j -> j)
  | PointerDown (id, d) ->
    (match detail_json d with
     | `Assoc a -> `Assoc (("kind", `String "pointer-down") :: n id :: a)
     | j -> j)
  | PointerUp (id, d) ->
    (match detail_json d with
     | `Assoc a -> `Assoc (("kind", `String "pointer-up") :: n id :: a)
     | j -> j)
  | PointerEnter id -> `Assoc [ k "pointer-enter"; n id ]
  | PointerLeave id -> `Assoc [ k "pointer-leave"; n id ]
  | ContextMenuPress (id, d) ->
    (match detail_json d with
     | `Assoc a ->
       `Assoc (("kind", `String "context-menu-press") :: n id :: a)
     | j -> j)
  | Load id -> `Assoc [ k "load"; n id ]
  | ScrollEdges (id, at_top, at_bottom) ->
    `Assoc
      [ k "scroll-edges"; n id; ("top", `Bool at_top)
      ; ("bottom", `Bool at_bottom) ]
  | ExtensionEvent (id, ident, name, values) ->
    `Assoc
      [ k "extension-event"; n id; ("identifier", `String ident)
      ; ("name", `String name)
      ; ( "json"
        , `Assoc
            (List.map
               (fun (key, v) -> (key, wire_json v))
               (String_map.bindings values)) ) ]

let action_json (a : Lui_window.action) : J.t =
  match a with
  | Lui_window.Dispatch e -> event_json e
  | Lui_window.Focus_changed id ->
    `Assoc [ ("kind", `String "focus-changed"); ("node", `Int id) ]
  | Lui_window.Resize_host (w, h) ->
    `Assoc
      [ ("kind", `String "resize-host"); ("width", `Int w)
      ; ("height", `Int h) ]
  | Lui_window.Ime_rect r ->
    `Assoc [ ("kind", `String "ime-rect"); ("rect", rect_json r) ]
  | Lui_window.Clipboard_write s ->
    `Assoc [ ("kind", `String "clipboard-write"); ("text", `String s) ]
  | Lui_window.Paste_request ->
    `Assoc [ ("kind", `String "paste-request") ]
  | Lui_window.Quit -> `Assoc [ ("kind", `String "quit") ]

let op_json (o : op) : J.t =
  match o with
  | Fill f ->
    `Assoc
      [ ("kind", `String "fill"); ("rect", rect_json f.frect)
      ; ("color", color_json f.fcolor)
      ; ("opacity", `Float f.fopacity) ]
  | Shadow s ->
    `Assoc
      [ ("kind", `String "shadow"); ("rect", rect_json s.srect)
      ; ("color", color_json s.scolor); ("blur", `Float s.sblur)
      ; ("inset", `Bool s.sinset) ]
  | Glyphs g ->
    `Assoc
      [ ("kind", `String "glyphs"); ("start", `Int g.gstart)
      ; ("end", `Int g.gend); ("color", color_json g.gcolor) ]
  | Image i ->
    `Assoc
      [ ("kind", `String "image"); ("rect", rect_json i.irect2)
      ; ("w", `Int i.iimage.iw); ("h", `Int i.iimage.ih) ]
  | Push_clip c ->
    `Assoc
      [ ("kind", `String "push_clip"); ("rect", rect_json c.crect) ]
  | Pop_clip -> `Assoc [ ("kind", `String "pop_clip") ]
  | Effect e ->
    `Assoc
      [ ("kind", `String "effect"); ("rect", rect_json e.edrect)
      ; ("index", `Int e.edindex) ]
  | Hole h ->
    `Assoc [ ("kind", `String "hole"); ("rect", rect_json h.hrect) ]

(* ---------- node references ----------

   A node ref is an int id, a "lui-N" string, or
   {"kind": ..., "text": ..., "index": i} — the i-th (0-based) node of
   that kind whose "text" prop matches. *)

let kind_of_name (s : string) : node_kind =
  match
    List.find_opt
      (fun k -> Lui_wire_schema.node_kind_name k = s)
      Lui_wire_schema.all_node_kinds
  with
  | Some k -> k
  | None -> failf "unknown node kind %S" s

let property_of_name (s : string) : property =
  match
    List.find_opt
      (fun p -> Lui_wire_schema.property_name p = s)
      Lui_wire_schema.all_properties
  with
  | Some p -> p
  | None -> failf "unknown property %S" s

let resolve_ref ctx (j : J.t) : int =
  match j with
  | `Int i -> i
  | `Intlit s -> int_of_string s
  | `Float f -> int_of_float f
  | `String s when String.length s > 4 && String.sub s 0 4 = "lui-" ->
    int_of_string (String.sub s 4 (String.length s - 4))
  | `Assoc _ ->
    let kind_name = jstr "kind" j in
    let index =
      match jget "index" j with
      | Some (`Int i) -> i
      | _ -> 0
    in
    let store = store ctx in
    let cands =
      List.filter_map
        (fun n ->
          if Lui_store.node_kind n = kind_name then
            Some (Lui_store.node_id n)
          else None)
        (Lui_store.all_nodes store)
    in
    let cands =
      match jget "text" j with
      | Some (`String s) ->
        List.filter
          (fun id ->
            Lui_e2e.E2e_harness.text_prop store id = s)
          cands
      | _ -> cands
    in
    (match List.nth_opt cands index with
     | Some id -> id
     | None ->
       failf "no node matching ref %s (candidates: [%s])"
         (J.to_string j)
         (String.concat ";" (List.map string_of_int cands)))
  | _ -> failf "invalid node ref %s" (J.to_string j)

(* ---------- patch batch decoding ---------- *)

let wire_of_json (j : J.t) : wire_value =
  match j with
  | `String s -> StringValue s
  | `Bool b -> BoolValue b
  | `Int i -> IntValue i
  | `Float f -> FloatValue f
  | `Intlit s -> IntValue (int_of_string s)
  | _ -> failf "invalid wire value %s" (J.to_string j)

let patch_op_of_json (j : J.t) : patch_op =
  let op = jstr "op" j in
  let id () = jint_opt "id" j in
  let prop () = property_of_name (jstr "prop" j) in
  match op with
  | "create-node" ->
    CreateNode (id (), kind_of_name (jstr "kind" j))
  | "create-extension" ->
    CreateExtension
      (id (), jstr "identifier" j, jstr "fingerprint" j)
  | "drop-node" -> DropNode (id ())
  | "detach-subtree" -> DetachSubtree (id ())
  | "set-prop" ->
    SetProp (id (), prop (), wire_of_json (jreq "value" j))
  | "remove-prop" -> RemoveProp (id (), prop ())
  | "set-extension-prop" ->
    SetExtensionProp (id (), jstr "prop" j, wire_of_json (jreq "value" j))
  | "remove-extension-prop" ->
    RemoveExtensionProp (id (), jstr "prop" j)
  | "insert-child" ->
    InsertChild (jint_opt "parent" j, jint_opt "child" j, jint_opt "index" j)
  | "remove-child" ->
    RemoveChild (jint_opt "parent" j, jint_opt "child" j)
  | "move-child" ->
    MoveChild (jint_opt "parent" j, jint_opt "child" j, jint_opt "index" j)
  | _ -> failf "unknown patch op %S" op

let batch_of_json (j : J.t) : patch_batch =
  { generation = jint_opt "generation" j
  ; ops =
      (match jreq "ops" j with
       | `List ops -> List.map patch_op_of_json ops
       | _ -> failf "\"ops\" must be a list") }

(* ---------- event decoding (dispatch step) ---------- *)

let mods_int mods =
  (if List.mem "ctrl" mods then 1 else 0)
  lor (if List.mem "shift" mods then 2 else 0)
  lor (if List.mem "alt" mods then 4 else 0)
  lor (if List.mem "meta" mods then 8 else 0)

let detail_of_json (j : J.t) : pointer_detail =
  { x = jfloat "x" 0. j
  ; y = jfloat "y" 0. j
  ; modifiers =
      (match jget "modifiers" j with
       | Some (`Int m) -> m
       | Some (`List l) -> mods_int (List.map J.Util.to_string l)
       | _ -> 0)
  ; button = jint_opt "button" j
  ; target_class =
      (match jget "target-class" j with
       | Some s -> J.Util.to_string s
       | None -> "") }

let event_of_json ctx (j : J.t) : event =
  let kind = jstr "kind" j in
  let node () = resolve_ref ctx (jreq "node" j) in
  let detail () = detail_of_json j in
  match kind with
  | "press" -> Press (node ())
  | "long-press" -> LongPress (node ())
  | "double-press" -> DoublePress (node ())
  | "text-changed" -> TextChanged (node (), jstr "text" j)
  | "submit" -> Submit (node ())
  | "toggle-changed" ->
    ToggleChanged (node (), J.Util.to_bool (jreq "checked" j))
  | "change" -> Change (node ())
  | "value-changed" -> ValueChanged (node (), jfloat "value" 0. j)
  | "dismiss" -> Dismiss (node ())
  | "appear" -> Appear (node ())
  | "scroll-completed" ->
    ScrollCompleted (node (), jint_opt "token" j, jstr "outcome" j)
  | "visible-range" ->
    VisibleRange (node (), jint_opt "first" j, jint_opt "last" j)
  | "picked" -> Picked (node (), jstr "payload" j)
  | "press-modifiers" -> PressModifiers (node (), jint_opt "modifiers" j)
  | "press-detail" -> PressDetail (node (), detail ())
  | "pointer-down" -> PointerDown (node (), detail ())
  | "pointer-up" -> PointerUp (node (), detail ())
  | "pointer-enter" -> PointerEnter (node ())
  | "pointer-leave" -> PointerLeave (node ())
  | "context-menu-press" -> ContextMenuPress (node (), detail ())
  | "load" -> Load (node ())
  | "navigation-key" ->
    NavigationKey (node (),jstr "key" j,J.Util.to_bool (jreq "shift" j))
  | "extension-event" ->
    let json_values =
      match jget "json" j with
      | Some (`Assoc fields) ->
        List.fold_left
          (fun m (k, v) -> String_map.add k (wire_of_json v) m)
          String_map.empty fields
      | _ -> String_map.empty
    in
    ExtensionEvent
      (node (), jstr "identifier" j, jstr "name" j, json_values)
  | _ -> failf "unknown event kind %S" kind

(* ---------- input decoding ---------- *)

let key_of_string (s : string) : Lui_window.Input.key =
  match String.lowercase_ascii s with
  | "return" | "enter" -> Lui_window.Input.Return
  | "escape" | "esc" -> Lui_window.Input.Escape
  | "backspace" -> Lui_window.Input.Backspace
  | "delete" -> Lui_window.Input.Delete
  | "tab" -> Lui_window.Input.Tab
  | "space" -> Lui_window.Input.Space
  | "arrow-left" | "arrow_left" | "left" -> Lui_window.Input.Arrow_left
  | "arrow-right" | "arrow_right" | "right" ->
    Lui_window.Input.Arrow_right
  | "arrow-up" | "arrow_up" | "up" -> Lui_window.Input.Arrow_up
  | "arrow-down" | "arrow_down" | "down" -> Lui_window.Input.Arrow_down
  | "home" -> Lui_window.Input.Home
  | "end" -> Lui_window.Input.End
  | "page-up" | "page_up" -> Lui_window.Input.Page_up
  | "page-down" | "page_down" -> Lui_window.Input.Page_down
  | s ->
    (try Lui_window.Input.Other (int_of_string s)
     with _ -> failf "unknown key %S" s)

let button_of_string (s : string) : Lui_window.Input.mouse_button =
  match String.lowercase_ascii s with
  | "left" -> Lui_window.Input.Left
  | "middle" -> Lui_window.Input.Middle
  | "right" -> Lui_window.Input.Right
  | s ->
    (try Lui_window.Input.Other (int_of_string s)
     with _ -> failf "unknown mouse button %S" s)

let input_mods (j : J.t) : Lui_window.Input.mods =
  let names = jstr_list "mods" j in
  { Lui_window.Input.ctrl = List.mem "ctrl" names
  ; shift = List.mem "shift" names
  ; alt = List.mem "alt" names
  ; meta = List.mem "meta" names }

(* ---------- rects / pointer plumbing ---------- *)

let rects_of ctx : Lui_window.Rects.t =
  let rects = Lui_window.Rects.create () in
  let store = store ctx in
  List.iter
    (fun n ->
      let id = Lui_store.node_id n in
      match
        Lui_host.layout_rect (Lui_e2e.E2e_harness.host ctx.h) id
      with
      | Some r -> Hashtbl.replace rects id r
      | None -> ())
    (Lui_store.all_nodes store);
  rects

let center_of ctx id : float * float =
  let r = Lui_e2e.E2e_harness.rect_of ctx.h id in
  (r.x +. r.w /. 2., r.y +. r.h /. 2.)

(* ---------- action delivery ---------- *)

let deliver_actions ctx (acts : Lui_window.action list) =
  List.iter
    (fun a ->
      Queue.add (action_json a) ctx.events;
      match a with
      | Lui_window.Dispatch e ->
        (match ctx.app with
         | Some app ->
           if not (app.E2e_json_apps.dispatch e) then
             failf "app rejected event %s" (J.to_string (event_json e))
         | None -> ())
      | Lui_window.Resize_host (w, h) ->
        Lui_e2e.E2e_harness.resize ctx.h ~width:w ~height:h
          ~scale:ctx.scale
      | _ -> ())
    acts

(* After every step: flush the app (its update may emit a patch batch),
   run Ui.store_changed to surface side-effect dispatches (appear,
   visible-range...), deliver those back into the app, and repaint when
   the host wants one. Bounded fixed-point since app flushes can dirty
   the store again. *)
let settle ctx =
  let rec round n =
    let acts = Lui_window.Ui.store_changed ctx.ui (store ctx) in
    deliver_actions ctx acts;
    let flushed =
      match ctx.app with
      | Some app -> app.E2e_json_apps.flush ()
      | None -> false
    in
    if (acts <> [] || flushed) && n > 0 then round (n - 1)
  in
  ignore
    (match ctx.app with
     | Some app -> app.E2e_json_apps.flush ()
     | None -> false);
  round 4;
  if Lui_e2e.E2e_harness.wants_repaint ctx.h then
    ignore (Lui_e2e.E2e_harness.repaint ctx.h);
  Lui_window.Ui.frame_done ctx.ui

let run_input ctx input =
  deliver_actions
    ctx
    (Lui_window.Ui.handle ctx.ui (store ctx) (rects_of ctx) input);
  settle ctx

(* ---------- steps ---------- *)

let click ctx (j : J.t) ~(button : string) ~(count : int) =
  let id = resolve_ref ctx j in
  let x, y = center_of ctx id in
  let btn = button_of_string button in
  let mods = input_mods j in
  run_input ctx (Lui_window.Input.Move (x, y));
  run_input ctx
    (Lui_window.Input.Button_down (x, y, btn, count, mods));
  run_input ctx (Lui_window.Input.Button_up (x, y, btn, mods))

let step_apply ctx j =
  let batch = batch_of_json j in
  if not (Lui_e2e.E2e_harness.apply_batch ctx.h batch) then
    failf "apply_batch rejected generation %d" batch.generation;
  settle ctx

let step_click ctx j ~right ~double =
  (* click value is a bare ref, or {"node": ref, "mods": [...]} *)
  let target =
    match j with
    | `Assoc a when List.mem_assoc "node" a -> jreq "node" j
    | _ -> j
  in
  click ctx target
    ~button:(if right then "right" else "left")
    ~count:(if double then 2 else 1)

let step_hover ctx j =
  let id = resolve_ref ctx j in
  let x, y = center_of ctx id in
  run_input ctx (Lui_window.Input.Move (x, y))

let step_drag ctx j =
  (* {"drag": {"from": ref, "to": {"x":..,"y":..} | ref}} *)
  let from = resolve_ref ctx (jreq "from" j) in
  let fx, fy = center_of ctx from in
  let tx, ty =
    match jreq "to" j with
    | `Assoc _ as t when
        (match jget "x" t with Some _ -> true | None -> false) ->
      (jfloat "x" 0. t, jfloat "y" 0. t)
    | t -> center_of ctx (resolve_ref ctx t)
  in
  let mods = input_mods j in
  run_input ctx (Lui_window.Input.Move (fx, fy));
  run_input ctx
    (Lui_window.Input.Button_down (fx, fy, Lui_window.Input.Left, 1, mods));
  run_input ctx (Lui_window.Input.Move (tx, ty));
  run_input ctx
    (Lui_window.Input.Button_up (tx, ty, Lui_window.Input.Left, mods))

let step_input ctx j =
  let s = J.Util.to_string j in
  run_input ctx (Lui_window.Input.Text_input s)

let step_key ctx j =
  let key, mods, repeat =
    match j with
    | `String s -> (key_of_string s, input_mods j, false)
    | `Assoc _ ->
      ( key_of_string (jstr "key" j)
      , input_mods j
      , (match jget "repeat" j with
         | Some b -> J.Util.to_bool b
         | None -> false) )
    | _ -> failf "invalid key step %s" (J.to_string j)
  in
  run_input ctx (Lui_window.Input.Key_down (key, mods, repeat))

let step_ime ctx j =
  match jget "mark" j, jget "commit" j, jget "caret" j with
  | Some m, _, _ ->
    let s = jstr "text" m in
    run_input ctx
      (Lui_window.Input.Text_editing
         (s, jint_opt "start" m, jint_opt "len" m))
  | _, Some c, _ -> run_input ctx (Lui_window.Input.Text_input (J.Util.to_string c))
  | _, _, Some c ->
    run_input ctx
      (Lui_window.Input.Caret
         (rect (jfloat "x" 0. c) (jfloat "y" 0. c) (jfloat "w" 0. c)
            (jfloat "h" 0. c)))
  | _ -> failf "ime step needs \"mark\", \"commit\" or \"caret\""

let step_scroll ctx j =
  let id = resolve_ref ctx (jreq "node" j) in
  let x, y = center_of ctx id in
  let dx = jfloat "dx" 0. j and dy = jfloat "dy" 0. j in
  run_input ctx (Lui_window.Input.Move (x, y));
  (match jget "mods" j with
   | Some _ ->
     run_input ctx
       (Lui_window.Input.Wheel_mods (dx, dy, input_mods j))
   | None -> run_input ctx (Lui_window.Input.Wheel (dx, dy)))

let step_scroll_to ctx j ~by =
  let id = resolve_ref ctx (jreq "node" j) in
  let axis, v =
    match jget "x" j, jget "y" j with
    | Some x, _ -> (Lui_window.Ui.X, J.Util.to_number x)
    | _, Some y -> (Lui_window.Ui.Y, J.Util.to_number y)
    | _ -> failf "scroll step needs \"x\" or \"y\""
  in
  let acts =
    if by then
      Lui_window.Ui.scroll_by ~axis ctx.ui (store ctx) id v
    else Lui_window.Ui.scroll_to ~axis ctx.ui (store ctx) id v
  in
  deliver_actions ctx acts;
  settle ctx

let step_drop ctx j =
  match jget "file" j, jget "text" j with
  | Some f, _ ->
    run_input ctx (Lui_window.Input.Drop_file (J.Util.to_string f))
  | _, Some t ->
    run_input ctx (Lui_window.Input.Drop_text (J.Util.to_string t))
  | _ -> failf "drop step needs \"file\" or \"text\""

let step_dispatch ctx j =
  match ctx.app with
  | None -> failf "dispatch step requires an app"
  | Some app ->
    let e = event_of_json ctx j in
    Queue.add (event_json e) ctx.events;
    if not (app.E2e_json_apps.dispatch e) then
      failf "app rejected event %s" (J.to_string (event_json e));
    settle ctx

let step_resize ctx j =
  let w = jint_opt "width" j and h = jint_opt "height" j in
  run_input ctx (Lui_window.Input.Resize (w, h))

let step_paste ctx j =
  run_input ctx (Lui_window.Input.Paste (J.Util.to_string j))

(* ---------- expectations ---------- *)

let node_json ctx id : J.t =
  let store = store ctx in
  match Lui_store.find_opt store id with
  | None -> `Null
  | Some n ->
    let props =
      List.filter_map
        (fun p ->
          let name = Lui_wire_schema.property_name p in
          match Lui_store.node_prop n name with
          | Some v -> Some (name, wire_json v)
          | None -> None)
        Lui_wire_schema.all_properties
    in
    `Assoc
      [ ("id", `Int id)
      ; ("kind", `String (Lui_store.node_kind n))
      ; ( "parent"
        , (match Lui_store.node_parent n with
           | Some p -> `Int p
           | None -> `Null) )
      ; ( "children"
        , `List
            (List.map (fun c -> `Int c) (Lui_store.node_children n)) )
      ; ( "ext-id"
        , (match Lui_store.node_ext_id n with
           | Some e -> `String e
           | None -> `Null) )
      ; ("props", `Assoc props) ]

let expect_events ctx (exps : J.t) =
  let expected =
    match exps with
    | `List l -> l
    | `String "*" ->
      (* drain the recorded stream without asserting its contents *)
      Queue.clear ctx.events;
      []
    | _ -> failf "expect-events must be a list or \"*\""
  in
  let actual = List.of_seq (Queue.to_seq ctx.events) in
  if List.length actual <> List.length expected then
    failf
      "expected %d events, got %d\n  expected: %s\n  actual:   %s"
      (List.length expected) (List.length actual)
      (J.to_string (`List expected))
      (J.to_string (`List actual));
  List.iter2
    (fun e a -> jmatch_at ~what:"event" e a)
    expected actual;
  Queue.clear ctx.events

let expect_store ctx (j : J.t) =
  let store = store ctx in
  (match jget "node-count" j with
   | Some e ->
     jmatch_at ~what:"store node-count" e
       (`Int (Lui_store.node_count store))
   | None -> ());
  (match jget "generation" j with
   | Some e ->
     jmatch_at ~what:"store generation" e
       (`Int (Lui_store.generation store))
   | None -> ());
  (match jget "roots" j with
   | Some (`List es) ->
     let actual =
       List.sort compare (Lui_store.root_ids store)
     in
     let expected = List.sort compare (List.map (resolve_ref ctx) es) in
     if actual <> expected then
       failf "store roots mismatch: expected [%s], got [%s]"
         (String.concat ";" (List.map string_of_int expected))
         (String.concat ";" (List.map string_of_int actual))
   | Some _ -> failf "\"roots\" must be a list"
   | None -> ());
  (match jget "absent" j with
   | Some (`List es) ->
     List.iter
       (fun e ->
         (* an unresolvable ref proves absence on its own *)
         match
           (try Some (resolve_ref ctx e) with Fail _ -> None)
         with
         | Some id when Lui_store.mem store id ->
           failf "node %d should be absent but exists" id
         | _ -> ())
       es
   | Some _ -> failf "\"absent\" must be a list"
   | None -> ());
  (match jget "nodes" j with
   | Some (`List specs) ->
     List.iter
       (fun spec ->
         let id = resolve_ref ctx (jreq "id" spec) in
         let actual = node_json ctx id in
         (* children listed as refs resolve to ids *)
         let spec =
           match spec with
           | `Assoc fields ->
             `Assoc
               (List.map
                  (fun (k, v) ->
                    match k, v with
                    | "id", _ -> (k, `Int id)
                    | "children", `List cs ->
                      (k, `List (List.map (fun c -> `Int (resolve_ref ctx c)) cs))
                    | "parent", p when p <> `Null ->
                      (k, `Int (resolve_ref ctx p))
                    | _ -> (k, v))
                  fields)
           | j -> j
         in
         jmatch_at ~what:(Printf.sprintf "node %d" id) spec actual)
       specs
   | Some _ -> failf "\"nodes\" must be a list"
   | None -> ());
  match jget "dirty" j with
  | Some (`String "*") ->
    ignore (Lui_store.drain_dirty store)
  | Some (`List es) ->
    (* drain_dirty consumes the flag — like the handwritten tests, a
       dirty assertion is a checkpoint, not a precondition. *)
    let actual = List.sort compare (Lui_store.drain_dirty store) in
    let expected = List.sort compare (List.map (resolve_ref ctx) es) in
    if actual <> expected then
      failf "store dirty mismatch: expected [%s], got [%s]"
        (String.concat ";" (List.map string_of_int expected))
        (String.concat ";" (List.map string_of_int actual))
  | Some _ -> failf "\"dirty\" must be a list"
  | None -> ()

let expect_frame ctx (j : J.t) =
  let cap = Lui_e2e.E2e_harness.cap ctx.h in
  (match jget "ops" j with
   | Some (`List names) ->
     let actual =
       `List
         (List.map
            (fun s -> `String s)
            (Lui_e2e.E2e_harness.op_names cap.Lui_e2e.E2e_harness.ops))
     in
     jmatch_at ~what:"frame ops" (`List names) actual
   | Some _ -> failf "\"ops\" must be a list"
   | None -> ());
  (match jget "frames" j with
   | Some e -> jmatch_at ~what:"frame frames" e (`Int cap.Lui_e2e.E2e_harness.frames)
   | None -> ());
  (match jget "bytes" j with
   | Some e -> jmatch_at ~what:"frame bytes" e (`Int cap.Lui_e2e.E2e_harness.bytes)
   | None -> ());
  (match jget "wants-repaint" j with
   | Some e ->
     jmatch_at ~what:"wants-repaint" e
       (`Bool (Lui_e2e.E2e_harness.wants_repaint ctx.h))
   | None -> ());
  (match jget "scene" j with
   | Some e ->
     let scene = Lui_e2e.E2e_harness.scene ctx.h in
     jmatch_at ~what:"scene" e
       (`Assoc
          [ ("width", `Int scene.width)
          ; ("height", `Int scene.height)
          ; ("scale", `Float scene.scale) ])
   | None -> ());
  (match jget "op-count" j with
   | Some (`Assoc specs) ->
     let names = Lui_e2e.E2e_harness.op_names cap.Lui_e2e.E2e_harness.ops in
     List.iter
       (fun (name, e) ->
         let count =
           List.length (List.filter (fun n -> n = name) names)
         in
         jmatch_at
           ~what:(Printf.sprintf "op-count %S" name)
           e (`Int count))
       specs
   | Some _ -> failf "\"op-count\" must be an object"
   | None -> ());
  (match jget "match" j with
   | Some (`List specs) ->
     (* ordered subsequence: each spec matches an op at-or-after the
        previous match *)
     let ops = List.map op_json cap.Lui_e2e.E2e_harness.ops in
     let _ =
       List.fold_left
         (fun start spec ->
           let rec find i =
             if i >= List.length ops then
               failf "no frame op at index >= %d matching %s" start
                 (J.to_string spec)
             else if jmatch spec (List.nth ops i) then i + 1
             else find (i + 1)
           in
           find start)
         0 specs
     in
     ()
   | Some _ -> failf "\"match\" must be a list"
   | None -> ());
  match jget "find" j with
  | Some specs ->
    let specs = match specs with `List l -> l | s -> [ s ] in
    List.iter
      (fun spec ->
        let rect_of_node =
          match jget "rect-of" spec with
          | Some r -> Some (resolve_ref ctx r)
          | None -> None
        in
        let fields =
          match spec with
          | `Assoc a -> List.remove_assoc "rect-of" a
          | _ -> [ ("kind", spec) ]
        in
        let found =
          List.exists
            (fun o ->
              let oj = op_json o in
              jmatch (`Assoc fields) oj
              &&
              match rect_of_node, jget "rect" oj with
              | Some id, Some rj ->
                jmatch rj (rect_json (Lui_e2e.E2e_harness.rect_of ctx.h id))
              | None, _ -> true
              | _ -> false)
            cap.Lui_e2e.E2e_harness.ops
        in
        if not found then
          failf "no frame op matches %s" (J.to_string spec))
      specs
  | None -> ()

let expect_bounds ctx (j : J.t) =
  let id = resolve_ref ctx (jreq "node" j) in
  match jget "absent" j with
  | Some (`Bool true) ->
    let r = Lui_e2e.E2e_harness.rect_of ctx.h id in
    if r.w <> 0. || r.h <> 0. then
      failf "node %d should have no bounds but is %gx%g" id r.w r.h
  | _ ->
    (match jget "rect" j with
     | Some spec ->
       let r = Lui_e2e.E2e_harness.rect_of ctx.h id in
       let spec =
         match spec with
         | `Assoc fields ->
           `Assoc
             (List.map
                (fun (k, v) ->
                  match k with
                  | "left" -> ("x", v)
                  | "top" -> ("y", v)
                  | "right" ->
                    ("__right", v)
                  | "bottom" -> ("__bottom", v)
                  | _ -> (k, v))
                fields)
         | j -> j
       in
       let actual =
         match jget "rect" j with
         | Some (`Assoc fields)
           when List.mem_assoc "right" fields
              || List.mem_assoc "bottom" fields ->
           `Assoc
             ( ("x", `Float r.x) :: ("y", `Float r.y)
             :: ("w", `Float r.w) :: ("h", `Float r.h)
             :: ("__right", `Float (r.x +. r.w))
             :: ("__bottom", `Float (r.y +. r.h))
             :: [] )
         | _ -> rect_json r
       in
       jmatch_at ~what:"bounds" spec actual
     | None -> ())

let expect_focused ctx (j : J.t) =
  let actual = Lui_window.Ui.focused ctx.ui in
  match j with
  | `Assoc a when List.mem_assoc "none" a ->
    if actual <> 0 then
      failf "expected no focused node, focused=%d" actual
  | _ ->
    let id = resolve_ref ctx j in
    if actual <> id then
      failf "expected focused=%d, got %d" id actual

let expect_scroll ctx (j : J.t) =
  let id = resolve_ref ctx (jreq "node" j) in
  (match jget "x" j with
   | Some e ->
     jmatch_at ~what:"scroll x" e
       (`Float (Lui_window.Ui.scroll_offset_x ctx.ui id))
   | None -> ());
  match jget "y" j with
  | Some e ->
    jmatch_at ~what:"scroll y" e
      (`Float (Lui_window.Ui.scroll_offset ctx.ui id))
  | None -> ()

let expect_marked ctx (j : J.t) =
  let expected = J.Util.to_string j in
  let actual = Lui_window.Ui.marked ctx.ui in
  if actual <> expected then
    failf "expected marked=%S, got %S" expected actual

let expect_drop ctx (j : J.t) =
  match Lui_window.Ui.last_drop ctx.ui with
  | None -> failf "expected a drop, got none"
  | Some (id, payload, _seq) ->
    (match jget "target" j with
     | Some e ->
       let expected = resolve_ref ctx e in
       if id <> expected then
         failf "drop target: expected %d, got %d" expected id
     | None -> ());
    match jget "payload" j with
    | Some e -> jmatch_at ~what:"drop payload" e (`String payload)
    | None -> ()

let expect_hit ctx (j : J.t) =
  let x = jfloat "x" 0. j and y = jfloat "y" 0. j in
  (match jget "node" j with
   | Some e ->
     let expected = resolve_ref ctx e in
     (match
        Lui_window.hit (store ctx) (rects_of ctx) ~x ~y
      with
      | Some id when id = expected -> ()
      | Some id ->
        failf "hit at (%g,%g): expected %d, got %d" x y expected id
      | None -> failf "hit at (%g,%g): expected %d, got none" x y expected)
   | None -> ());
  match jget "path" j with
  | Some (`List es) ->
    let expected = List.map (resolve_ref ctx) es in
    let actual =
      Lui_window.hit_path (store ctx) (rects_of ctx) ~x ~y
    in
    if actual <> expected then
      failf "hit path at (%g,%g): expected [%s], got [%s]" x y
        (String.concat ";" (List.map string_of_int expected))
        (String.concat ";" (List.map string_of_int actual))
  | Some _ -> failf "\"path\" must be a list"
  | None -> ()

let expect_ui ctx (j : J.t) =
  let check name j =
    match jget name j with
    | Some e ->
      let actual =
        match name with
        | "hovered" -> Lui_window.Ui.hovered ctx.ui
        | "pressed" -> Lui_window.Ui.pressed ctx.ui
        | "focused" -> Lui_window.Ui.focused ctx.ui
        | "open-menu" -> Lui_window.Ui.open_menu ctx.ui
        | "overlay-top" -> Lui_window.Ui.overlay_top ctx.ui
        | _ -> -1
      in
      (match e with
       | `Null ->
         if actual <> 0 then failf "ui %s: expected none, got %d" name actual
       | _ ->
         let id = resolve_ref ctx e in
         if actual <> id then
           failf "ui %s: expected %d, got %d" name id actual)
    | None -> ()
  in
  List.iter
    (fun name -> check name j)
    [ "hovered"; "pressed"; "focused"; "open-menu"; "overlay-top" ];
  (match jget "drag-active" j with
   | Some e ->
     jmatch_at ~what:"drag-active" e
       (`Bool (Lui_window.Ui.drag_active ctx.ui))
   | None -> ());
  match jget "marked" j with
  | Some e -> jmatch_at ~what:"marked" e (`String (Lui_window.Ui.marked ctx.ui))
  | None -> ()

(* ---------- step table ---------- *)

let run_step ctx (step : J.t) =
  match step with
  | `Assoc ((k, v) :: _) ->
    (match k with
     | "apply" -> step_apply ctx v
     | "click" -> step_click ctx v ~right:false ~double:false
     | "right-click" -> step_click ctx v ~right:true ~double:false
     | "double-click" -> step_click ctx v ~right:false ~double:true
     | "hover" -> step_hover ctx v
     | "drag" -> step_drag ctx v
     | "input" -> step_input ctx v
     | "key" -> step_key ctx v
     | "keys" -> step_key ctx v
     | "ime" -> step_ime ctx v
     | "scroll" -> step_scroll ctx v
     | "scroll-to" -> step_scroll_to ctx v ~by:false
     | "scroll-by" -> step_scroll_to ctx v ~by:true
     | "drop" -> step_drop ctx v
     | "dispatch" -> step_dispatch ctx v
     | "app-dispose" ->
       (match ctx.app with
        | Some app ->
          if not (app.E2e_json_apps.dispose ()) then
            failf "app dispose returned false";
          settle ctx
        | None -> failf "app-dispose requires an app")
     | "resize" -> step_resize ctx v
     | "paste" -> step_paste ctx v
     | "repaint" ->
       ignore (Lui_e2e.E2e_harness.repaint ctx.h);
       Lui_window.Ui.frame_done ctx.ui
     | "expect-events" -> expect_events ctx v
     | "expect-store" -> expect_store ctx v
     | "expect-frame" -> expect_frame ctx v
     | "expect-bounds" -> expect_bounds ctx v
     | "expect-focused" -> expect_focused ctx v
     | "expect-scroll" -> expect_scroll ctx v
     | "expect-marked" -> expect_marked ctx v
     | "expect-drop" -> expect_drop ctx v
     | "expect-hit" -> expect_hit ctx v
     | "expect-ui" -> expect_ui ctx v
     | _ -> failf "unknown step %S" k)
  | _ -> failf "step must be an object: %s" (J.to_string step)

(* ---------- entry point ---------- *)

let run (j : J.t) =
  let name =
    match jget "name" j with
    | Some s -> J.Util.to_string s
    | None -> "unnamed"
  in
  (* the e2e convention: "test.hole" extensions paint a Hole op at
     their rect — same stub the handwritten suite registers *)
  Lui_paint.register_extension ~identifier:"test.hole"
    { Lui_paint.paint =
        (fun _hooks _store _node r ->
          [ Hole
              { hrect = r; hradii = (0., 0., 0., 0.);
                hcontinuous = false; hopacity = 1. } ]) };
  let width =
    match jget "width" j with
    | Some (`Int w) -> w
    | _ -> 320
  in
  let height =
    match jget "height" j with
    | Some (`Int h) -> h
    | _ -> 240
  in
  let scale = jfloat "scale" 1. j in
  let h = Lui_e2e.E2e_harness.create ~width ~height () in
  let ui = Lui_window.Ui.create () in
  Lui_window.Ui.set_scale ui scale;
  let ctx =
    { h; ui; app = None; events = Queue.create (); scale; name }
  in
  (try
     (match jget "app" j with
      | Some (`String app_name) ->
        (match
           E2e_json_apps.make app_name
             (Lui_e2e.E2e_harness.backend ctx.h
                (Lui_protocol.generic_profile ()))
         with
         | Some make ->
           let app = make () in
           ctx.app <- Some app;
           if not (app.E2e_json_apps.start ()) then
             failf "app %S failed to start" app_name;
           settle ctx
         | None -> failf "unknown app %S" app_name)
      | _ -> ());
     let steps =
       match jreq "steps" j with
       | `List s -> s
       | _ -> failf "\"steps\" must be a list"
     in
     List.iteri
       (fun i step ->
         try run_step ctx step
         with
         | Fail m ->
           failf "scenario %S step %d (%s):\n%s" name (i + 1)
             (J.to_string step) m)
       steps
   with
   | Fail m -> failf "%s" m)

let run_file path =
  let j =
    try J.from_file path
    with e ->
      failf "cannot parse %s: %s" path (Printexc.to_string e)
  in
  try run j
  with
  | Fail m -> failf "%s\n  file: %s" m path
