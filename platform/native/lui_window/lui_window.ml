(* Pure-OCaml core of the SDL window host: CLI parsing, backend-neutral
   input events, protocol event mapping with the same admission rules
   [Lui_runtime.dispatch] applies, rect hit testing, a deterministic
   layout stub, per-frame interaction state, the dark theme palette
   and the headless-loop checksum. SDL/GL/text-engine free so every
   piece is unit-testable. *)

open Lui_scene
open Lui_protocol

type config = {
  width : int;
  height : int;
  headless_frames : int option;
}

let default_config = { width = 960; height = 640; headless_frames = None }

let parse_args argv =
  let rec loop cfg = function
    | "--width" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with width = n } tl
       | _ -> Error ("invalid --width " ^ v))
    | "--height" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with height = n } tl
       | _ -> Error ("invalid --height " ^ v))
    | "--headless" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with headless_frames = Some n } tl
       | _ -> Error ("invalid --headless " ^ v))
    | ("--width" | "--height" | "--headless") :: [] ->
      Error "missing value for flag"
    | arg :: _ -> Error ("unknown argument " ^ arg)
    | [] -> Ok cfg
  in
  loop default_config argv

module Input = struct
  type key =
    | Return
    | Escape
    | Backspace
    | Delete
    | Tab
    | Arrow_left
    | Arrow_right
    | Arrow_up
    | Arrow_down
    | Home
    | End
    | Other of int

  type mouse_button =
    | Left
    | Middle
    | Right
    | Other of int

  let button_to_int = function
    | Left -> 0
    | Middle -> 1
    | Right -> 2
    | Other n -> n

  type mods = {
    ctrl : bool;
    shift : bool;
    alt : bool;
    meta : bool;
  }

  let mods_none = { ctrl = false; shift = false; alt = false; meta = false }

  (* Same bitmask the web backend emits: 1 ctrl, 2 shift, 4 meta. The
     secondary-button bit 8 is set by the detail builder on right
     clicks, matching press_detail's modifiers field. *)
  let mods_to_int m =
    (if m.ctrl then 1 else 0)
    lor (if m.shift then 2 else 0)
    lor (if m.meta then 4 else 0)

  type t =
    | Move of float * float
    | Button_down of float * float * mouse_button * int * mods
    | Button_up of float * float * mouse_button * mods
    | Text_input of string
    | Text_editing of string * int * int
    | Caret of rect
    | Key_down of key * mods * bool
    | Resize of int * int
    | Wheel of float * float
    | Quit_input

  (* SDL_Scancode integer constants, kept in this module (not the
     driver) so the table is unit-testable without SDL linked. *)
  let key_of_sdl_scancode = function
    | 40 | 88 -> Return (* return, keypad-enter *)
    | 41 -> Escape
    | 42 -> Backspace
    | 76 -> Delete
    | 43 -> Tab
    | 74 -> Home
    | 77 -> End
    | 80 -> Arrow_left
    | 79 -> Arrow_right
    | 81 -> Arrow_down
    | 82 -> Arrow_up
    | n -> Other n

  (* SDL_BUTTON_* integer constants: 1 left, 2 middle, 3 right. *)
  let button_of_sdl = function
    | 1 -> Left
    | 2 -> Middle
    | 3 -> Right
    | n -> Other n
end

type action =
  | Dispatch of Lui_protocol.event
  | Resize_host of int * int
  | Focus_changed of int
  | Ime_rect of rect
  | Quit

module Rects = struct
  type t = (int, rect) Hashtbl.t

  let create () = Hashtbl.create 128
  let zero = rect 0. 0. 0. 0.
  let get t id = match Hashtbl.find_opt t id with Some r -> r | None -> zero
end

let kind_name store id = Lui_store.kind store id

let kind_table =
  let t = Hashtbl.create 97 in
  List.iter
    (fun k -> Hashtbl.replace t (Lui_wire_schema.node_kind_name k) k)
    Lui_wire_schema.all_node_kinds;
  t

let kind_of store id = Hashtbl.find_opt kind_table (Lui_store.kind store id)

(* Enabled unless the prop explicitly says otherwise — mirrors the
   paint pipeline's disabled fold (BoolValue false or "false"). *)
let node_enabled store id =
  match Lui_store.prop store id "enabled" with
  | Some (BoolValue false) -> false
  | Some (StringValue "false") -> false
  | _ -> true

let pointer_enabled store id = Lui_store.bool_prop store id "pointer-enabled"

let bool_prop store id name = Lui_store.bool_prop store id name

let string_prop store id name =
  match Lui_store.string_prop store id name with
  | Some s -> s
  | None -> ""

(* The only properties dispatch admission consults. *)
let gate_properties =
  [ AppearEnabled; PressEnabled; PointerEnabled; ChangeEnabled;
    ToggleEnabled; RoleValue ]

let event_supported store id event =
  match kind_of store id with
  | None -> false
  | Some kind ->
    let props =
      List.fold_left
        (fun acc p ->
           match Lui_store.prop store id (Lui_wire_schema.property_name p) with
           | Some v -> Property_map.add p v acc
           | None -> acc)
        Property_map.empty gate_properties
    in
    Lui_protocol.event_supported_for_properties kind props event

let hit_path store rects ~x ~y =
  let visible id =
    match Lui_store.prop store id "visible" with
    | Some (BoolValue false) -> false
    | _ -> true
  in
  let rec walk id path =
    if not (visible id) then path
    else
      let path =
        let r = Rects.get rects id in
        if not (rect_empty r) && rect_contains r x y then id :: path else path
      in
      (* Children paint after their parent, so prepending while walking
         leaves the node visited last — visually topmost — at the head. *)
      List.fold_left
        (fun acc c -> walk c acc)
        path (Lui_store.child_ids store id)
  in
  (* The head is the node visited last in paint order: visually
     topmost. *)
  List.fold_left
    (fun acc id -> walk id acc)
    [] (Lui_store.root_ids store)

let hit store rects ~x ~y =
  match hit_path store rects ~x ~y with
  | id :: _ -> Some id
  | [] -> None

module Layout = struct
  type measure = Lui_store.t -> int -> scale:float -> float * float

  let default_measure _store _id ~scale:_ = (0., 0.)

  (* Props arrive as IntValue for frame props (see apply_universal);
     accept FloatValue and "Npx"-style strings too. *)
  let parse_len s =
    let n = String.length s in
    let stop =
      let rec find i =
        if i >= n then n
        else
          match s.[i] with
          | '0' .. '9' | '.' | '-' | '+' -> find (i + 1)
          | _ -> i
      in
      find 0
    in
    if stop = 0 then None
    else
      try Some (float_of_string (String.sub s 0 stop))
      with _ -> None

  let len_prop store id name ~scale =
    match Lui_store.prop store id name with
    | Some (FloatValue f) -> Some (f *. scale)
    | Some (IntValue i) -> Some (float i *. scale)
    | Some (StringValue s) ->
      Option.map (fun v -> v *. scale) (parse_len s)
    | _ -> None

  type axis = Vertical | Horizontal

  let direction store id =
    match Lui_store.kind store id with
    | "row" -> Horizontal
    | _ -> Vertical

  let pad_axis store id ~scale axis =
    let uniform =
      Option.value ~default:0. (len_prop store id "padding" ~scale)
    in
    let name =
      match axis with
      | Vertical -> "padding-vertical"
      | Horizontal -> "padding-horizontal"
    in
    Option.value ~default:uniform (len_prop store id name ~scale)

  let gap_px store id ~scale =
    Option.value ~default:0. (len_prop store id "gap" ~scale)

  let grow_weight store id =
    match Lui_store.float_prop store id "grow" with
    | Some w when w > 0. -> w
    | _ ->
      (* A bare spacer always absorbs free space. *)
      if Lui_store.kind store id = "spacer" then 1. else 0.

  (* Logical-pixel default leaf heights; width defaults to "fill". *)
  let leaf_height = function
    | "button" | "toggle-button" | "text-field" | "secure-field"
    | "input" | "search-field" -> 32.
    | "textarea" -> 64.
    | "divider" -> 1.
    | "progress" -> 6.
    | "checkbox" | "switch" | "radio" -> 22.
    | "slider" | "number-stepper" -> 24.
    | "image" | "file-image" -> 64.
    | "spacer" -> 8.
    | "icon" -> 20.
    | _ -> 24.

  let leaf_extent store id ~scale =
    (0., leaf_height (Lui_store.kind store id) *. scale)

  let rec natural_main store measure scale dir id =
    let prop_name =
      match dir with Vertical -> "height" | Horizontal -> "width"
    in
    match len_prop store id prop_name ~scale with
    | Some v -> v
    | None ->
      (match Lui_store.child_ids store id with
       | [] ->
         (* Leaf: ask the text engine first, fall back to the table. *)
         let mw, mh = measure store id ~scale in
         let dw, dh = leaf_extent store id ~scale in
         (match dir with
          | Vertical -> if mh > 0. then mh else dh
          | Horizontal -> if mw > 0. then mw else max dw 24.)
       | children ->
         let pm = 2. *. pad_axis store id ~scale dir in
         let gap = gap_px store id ~scale in
         let n = List.length children in
         let sum =
           List.fold_left
             (fun acc c -> acc +. natural_main store measure scale dir c)
             0. children
         in
         pm +. sum +. gap *. float (max 0 (n - 1)))

  let cross_extent store id ~scale dir avail =
    let name =
      match dir with Vertical -> "width" | Horizontal -> "height"
    in
    match len_prop store id name ~scale with
    | Some v -> min v avail
    | None -> avail

  let rec layout_node store measure scale rects id (r : rect) =
    Hashtbl.replace rects id r;
    match Lui_store.child_ids store id with
    | [] -> ()
    | children ->
      let dir = direction store id in
      let gap = gap_px store id ~scale in
      let pm = pad_axis store id ~scale dir in
      let pc =
        pad_axis store id ~scale
          (match dir with Vertical -> Horizontal | Horizontal -> Vertical)
      in
      let cx, cy, cw, ch =
        match dir with
        | Vertical ->
          ( r.x +. pc, r.y +. pm,
            max 0. (r.w -. (2. *. pc)), max 0. (r.h -. (2. *. pm)) )
        | Horizontal ->
          ( r.x +. pm, r.y +. pc,
            max 0. (r.w -. (2. *. pm)), max 0. (r.h -. (2. *. pc)) )
      in
      let n = List.length children in
      let entries =
        List.map
          (fun c ->
             let w = grow_weight store c in
             ( c, w,
               if w > 0. then 0.
               else natural_main store measure scale dir c ))
          children
      in
      let fixed =
        List.fold_left (fun a (_, _, s) -> a +. s) 0. entries
      in
      let grow_total =
        List.fold_left (fun a (_, w, _) -> a +. w) 0. entries
      in
      let main = match dir with Vertical -> ch | Horizontal -> cw in
      let leftover =
        max 0. (main -. fixed -. (gap *. float (max 0 (n - 1))))
      in
      let start = match dir with Vertical -> cy | Horizontal -> cx in
      ignore
        (List.fold_left
           (fun pos (c, w, s) ->
              let m =
                if w > 0. && grow_total > 0. then
                  leftover *. w /. grow_total
                else s
              in
              let child_r =
                match dir with
                | Vertical ->
                  rect cx pos (cross_extent store c ~scale dir cw) m
                | Horizontal ->
                  rect pos cy m (cross_extent store c ~scale dir ch)
              in
              layout_node store measure scale rects c child_r;
              pos +. m +. gap)
           start entries)

  let refresh store rects ~width ~height ~scale ~measure =
    Hashtbl.reset rects;
    let w = float width *. scale and h = float height *. scale in
    List.iter
      (fun id -> layout_node store measure scale rects id (rect 0. 0. w h))
      (Lui_store.root_ids store)
end

module Ui = struct
  type t = {
    mutable scale : float;
    mutable hovered : int;
    mutable hover_detail : int;
    mutable pressed : int;
    mutable press_detail : int;
    mutable focused : int;
    mutable caret : int;
    (* Latest text value as the app sees it: the store prop lags one
       frame behind the events we dispatch, so rapid edits splice onto
       this shadow instead of the stale prop. *)
    mutable shadow : string;
    (* IME composition state machine: SDL text-editing/commit events
       feed it; marked text rides here (never dispatched) until the
       commit lands through the normal input path. *)
    mutable ime : Lui_ime.state;
    mutable dirty : bool;
  }

  let create () =
    { scale = 1.; hovered = 0; hover_detail = 0; pressed = 0;
      press_detail = 0; focused = 0; caret = 0; shadow = "";
      ime = Lui_ime.initial; dirty = true }

  let set_scale t s = t.scale <- s
  let hovered t = t.hovered
  let pressed t = t.pressed
  let focused t = t.focused
  let caret t = t.caret
  let shadow t = t.shadow
  let ime t = t.ime
  let marked t = t.ime.Lui_ime.marked_text

  let text_of store id = string_prop store id "text"

  let set_focused t store id =
    if id <> t.focused then begin
      (* Focus loss cancels any in-flight composition first — marked
         text was never dispatched, so clearing it locally is the
         whole rollback. *)
      let st, _ = Lui_ime.feed_event t.ime (`Focus false) in
      let st, _ = Lui_ime.feed_event st (`Focus (id <> 0)) in
      t.ime <- st;
      t.focused <- id;
      t.shadow <- (if id = 0 then "" else text_of store id);
      t.caret <- (if id = 0 then 0 else String.length t.shadow);
      t.dirty <- true
    end

  (* First id in [path] (deepest-first) that is enabled and passes
     [accept]. Pointer events keep bubbling past disabled nodes. *)
  let pick store path accept =
    List.find_opt
      (fun id -> node_enabled store id && accept store id)
      path

  (* First path node satisfying [accept]; if it is disabled it swallows
     the activation — matches web: disabled controls neither activate
     nor let activation fall through to ancestors. *)
  let select_activation store path accept =
    match List.find_opt (fun id -> accept store id) path with
    | Some id -> if node_enabled store id then Some id else None
    | None -> None

  let detail_of store id x y mods button =
    { x; y;
      modifiers =
        Input.mods_to_int mods lor (if button = 2 then 8 else 0);
      button; target_class = string_prop store id "style-class" }

  (* A representative event per family for admission checks; only the
     constructor matters to the gate. *)
  let ev_text n : event = TextChanged (n, "")
  let ev_press n : event = Press n
  let ev_submit n : event = Submit n

  let dummy_detail =
    { x = 0.; y = 0.; modifiers = 0; button = 0; target_class = "" }

  let focus_target store path =
    select_activation store path
      (fun s id -> event_supported s id (ev_text id))

  let press_target store path =
    select_activation store path
      (fun s id -> event_supported s id (ev_press id))

  let detail_target store path make =
    pick store path (fun s id ->
        pointer_enabled s id && event_supported s id (make id))

  (* Click on a pressable node, mirroring the web click dispatch:
     toggle kinds flip their state instead of emitting Press. *)
  let primary_press store id =
    let dispatch e =
      if node_enabled store id && event_supported store id e
      then [ Dispatch e ] else []
    in
    match kind_name store id with
    | "toggle-button" | "toggle" ->
      dispatch (ToggleChanged (id, not (bool_prop store id "selected")))
    | "checkbox" | "switch" ->
      dispatch (ToggleChanged (id, not (bool_prop store id "checked")))
    | "radio" ->
      if event_supported store id (Change id) then [ Dispatch (Change id) ]
      else
        (match dispatch (ToggleChanged (id, true)) with
         | [] -> dispatch (Press id)
         | acts -> acts)
    | "list-item" ->
      let expand =
        if string_prop store id "role" = "treeitem"
           && event_supported store id (ToggleChanged (id, true))
        then
          dispatch (ToggleChanged (id, not (bool_prop store id "expanded")))
        else []
      in
      dispatch (Press id) @ expand
    | _ -> dispatch (Press id)

  let focusables store =
    List.filter
      (fun id ->
         node_enabled store id && event_supported store id (ev_text id))
      (Lui_store.preorder store)

  let next_focusable store cur =
    match focusables store with
    | [] -> 0
    | ids ->
      let rec find = function
        | a :: b :: _ when a = cur -> b
        | _ :: tl -> find tl
        | [] -> List.hd ids
      in
      find ids

  (* UTF-8 aware caret stepping over byte offsets. *)
  let utf8_prev s i =
    let rec back j =
      if j <= 0 then 0
      else if Char.code s.[j] land 0xC0 = 0x80 then back (j - 1)
      else j
    in
    back (i - 1)

  let utf8_next s i =
    let n = String.length s in
    let rec fwd j =
      if j >= n then n
      else if Char.code s.[j] land 0xC0 = 0x80 then fwd (j + 1)
      else j
    in
    fwd (i + 1)

  let submit store id =
    if event_supported store id (ev_submit id) then [ Dispatch (Submit id) ]
    else []

  (* Translate one lui_ime action into window actions plus the Ui
     side effects they imply. `Commit_text splices through the exact
     path raw text input used before composition existed. *)
  let apply_ime t store actions =
    List.filter_map
      (fun a ->
         match a with
         | `Move_candidate r -> Some (Ime_rect r)
         | `Commit_text s ->
           t.dirty <- true;
           (match t.focused with
            | 0 -> None
            | n when node_enabled store n
                     && event_supported store n (ev_text n) ->
              let cur = t.shadow in
              let caret = min t.caret (String.length cur) in
              let next =
                String.sub cur 0 caret ^ s
                ^ String.sub cur caret (String.length cur - caret)
              in
              t.shadow <- next;
              t.caret <- caret + String.length s;
              Some (Dispatch (TextChanged (n, next)))
            | _ -> None)
         | `Begin_composition | `Update_composition _ | `Cancel ->
           t.dirty <- true;
           None)
      actions

  (* Feed one IME event into the state machine and apply what it
     asks for. *)
  let feed_ime t store ev =
    let st, actions = Lui_ime.feed_event t.ime ev in
    t.ime <- st;
    apply_ime t store actions

  let handle t store rects = function
    | Input.Move (x, y) ->
      let path =
        hit_path store rects ~x:(x *. t.scale) ~y:(y *. t.scale)
      in
      let hover = match path with id :: _ -> id | [] -> 0 in
      let detail =
        match
          detail_target store path (fun id -> PointerEnter id)
        with
        | Some id -> id
        | None -> 0
      in
      let actions =
        if detail <> t.hover_detail then
          (if t.hover_detail <> 0
              && node_enabled store t.hover_detail
              && event_supported store t.hover_detail
                   (PointerLeave t.hover_detail)
           then [ Dispatch (PointerLeave t.hover_detail) ]
           else [])
          @ (if detail <> 0 then [ Dispatch (PointerEnter detail) ] else [])
        else []
      in
      if hover <> t.hovered || detail <> t.hover_detail then t.dirty <- true;
      t.hovered <- hover;
      t.hover_detail <- detail;
      actions
    | Input.Button_down (x, y, btn, clicks, mods) ->
      (match btn with
       | Input.Left ->
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         let focus_actions =
           let focus =
             match focus_target store path with
             | Some id -> id
             | None -> 0
           in
           if focus <> t.focused then begin
             set_focused t store focus;
             [ Focus_changed focus ]
           end else []
         in
         let down =
           match
             detail_target store path (fun id ->
                 PointerDown (id, dummy_detail))
           with
           | Some id ->
             t.press_detail <- id;
             [ Dispatch
                 (PointerDown
                    (id, detail_of store id x y mods 0)) ]
           | None ->
             t.press_detail <- 0;
             []
         in
         t.pressed <-
           (match press_target store path with
            | Some id -> id
            | None -> 0);
         let double =
           if clicks = 2 then
             match
               pick store path (fun s id ->
                   event_supported s id (DoublePress id))
             with
             | Some id -> [ Dispatch (DoublePress id) ]
             | None -> []
           else []
         in
         t.dirty <- true;
         focus_actions @ down @ double
       | Input.Right ->
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         (match
            detail_target store path (fun id ->
                ContextMenuPress (id, dummy_detail))
          with
          | Some id ->
            [ Dispatch
                (ContextMenuPress
                   (id, detail_of store id x y mods 2)) ]
          | None -> [])
       | _ -> [])
    | Input.Button_up (x, y, btn, mods) ->
      (match btn with
       | Input.Left ->
         let up =
           if t.press_detail <> 0
              && node_enabled store t.press_detail
              && event_supported store t.press_detail
                   (PointerUp (t.press_detail, dummy_detail))
           then
             [ Dispatch
                 (PointerUp
                    (t.press_detail,
                     detail_of store t.press_detail x y mods 0)) ]
           else []
         in
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         let release =
           match press_target store path with
           | Some id -> id
           | None -> 0
         in
         let click =
           if t.pressed <> 0 && release = t.pressed then begin
             let n = t.pressed in
             let pd =
               if pointer_enabled store n
                  && event_supported store n
                       (PressDetail (n, dummy_detail))
               then
                 [ Dispatch
                     (PressDetail (n, detail_of store n x y mods 0)) ]
               else []
             in
             pd @ primary_press store n
           end else []
         in
         t.pressed <- 0;
         t.press_detail <- 0;
         t.dirty <- true;
         up @ click
       | _ -> [])
    | Input.Text_input s -> feed_ime t store (`Commit s)
    | Input.Text_editing (text, start, len) ->
      feed_ime t store (`Editing (text, start, len))
    | Input.Caret r -> feed_ime t store (`Caret r)
    | Input.Key_down (key, mods, _repeat) ->
      (* While marked text is on screen the keys belong to the IME —
         SDL filters most of them already; this gate is the belt. *)
      if Lui_ime.composing t.ime then []
      else (match key, t.focused with
       | Input.Escape, 0 -> [ Quit ]
       | Input.Escape, _ ->
         set_focused t store 0;
         [ Focus_changed 0 ]
       | Input.Tab, _ ->
         let next =
           if mods.shift then t.focused (* shift-tab unsupported for now *)
           else next_focusable store t.focused
         in
         if next <> t.focused then begin
           set_focused t store next;
           [ Focus_changed next ]
         end else []
       | Input.Return, n when n <> 0 ->
         (match kind_name store n with
          | "textarea" ->
            if (bool_prop store n "submit-on-enter" && not mods.shift)
               || mods.ctrl || mods.meta
            then submit store n
            else []
          | _ -> submit store n)
       | Input.Backspace, n when n <> 0 ->
         let cur = t.shadow in
         let caret = min t.caret (String.length cur) in
         if caret > 0 then begin
           let prev = utf8_prev cur caret in
           let next =
             String.sub cur 0 prev
             ^ String.sub cur caret (String.length cur - caret)
           in
           t.shadow <- next;
           t.caret <- prev;
           t.dirty <- true;
           if next <> cur then [ Dispatch (TextChanged (n, next)) ] else []
         end else []
       | Input.Delete, n when n <> 0 ->
         let cur = t.shadow in
         let caret = min t.caret (String.length cur) in
         if caret < String.length cur then begin
           let nxt = utf8_next cur caret in
           let next =
             String.sub cur 0 caret
             ^ String.sub cur nxt (String.length cur - nxt)
           in
           t.shadow <- next;
           t.dirty <- true;
           if next <> cur then [ Dispatch (TextChanged (n, next)) ] else []
         end else []
       | Input.Arrow_left, n when n <> 0 ->
         t.caret <-
           utf8_prev t.shadow
             (min t.caret (String.length t.shadow));
         []
       | Input.Arrow_right, n when n <> 0 ->
         t.caret <-
           utf8_next t.shadow
             (min t.caret (String.length t.shadow));
         []
       | Input.Home, n when n <> 0 -> t.caret <- 0; []
       | Input.End, n when n <> 0 ->
         t.caret <- String.length t.shadow; []
       | _ -> [])
    | Input.Resize (w, h) -> [ Resize_host (w, h) ]
    | Input.Wheel _ -> []
    | Input.Quit_input -> [ Quit ]

  let state_of t store id =
    { Lui_paint.hovered = t.hovered = id;
      pressed = t.pressed = id;
      focused = t.focused = id;
      selected = bool_prop store id "selected";
      disabled = not (node_enabled store id) }

  let want_frame t host = t.dirty || Lui_host.wants_repaint host
  let frame_done t = t.dirty <- false
end

module Theme = struct
  let color = color

  let palette =
    [ ("background", color 22 23 32 255);
      ("foreground", color 228 230 238 255);
      ("card", color 30 31 44 255);
      ("card-foreground", color 228 230 238 255);
      ("popover", color 30 31 44 255);
      ("popover-foreground", color 228 230 238 255);
      ("primary", color 76 116 246 255);
      ("primary-foreground", color 255 255 255 255);
      ("secondary", color 44 46 62 255);
      ("secondary-foreground", color 228 230 238 255);
      ("muted", color 44 46 62 255);
      ("muted-foreground", color 152 158 178 255);
      ("accent", color 52 55 74 255);
      ("accent-foreground", color 228 230 238 255);
      ("destructive", color 239 68 68 255);
      ("destructive-foreground", color 255 255 255 255);
      ("border", color 56 59 76 255);
      ("input", color 40 42 58 255);
      ("ring", color 76 116 246 255);
      ("selection", color 76 116 246 90) ]

  let color_of_hex s =
    let n = String.length s in
    if n < 2 || s.[0] <> '#' then None
    else
      let hex i = int_of_string ("0x" ^ String.sub s i 2) in
      let dup i =
        let c = String.sub s i 1 in
        int_of_string ("0x" ^ c ^ c)
      in
      try
        (match n - 1 with
         | 3 -> Some (color (dup 1) (dup 2) (dup 3) 255)
         | 4 -> Some (color (dup 1) (dup 2) (dup 3) (dup 4))
         | 6 -> Some (color (hex 1) (hex 3) (hex 5) 255)
         | 8 -> Some (color (hex 1) (hex 3) (hex 5) (hex 7))
         | _ -> None)
      with _ -> None

  let color_of name =
    match List.assoc_opt name palette with
    | Some c -> Some c
    | None -> color_of_hex name
end

module Checksum = struct
  (* FNV-1a 64-bit over a canonical op description, so identical
     scenes on any platform produce the same digest. *)
  type t = { mutable hash : int64 }

  let create () = { hash = 0xcbf29ce484222325L }

  let add_int t v =
    let x = Int64.of_int (v land 0x3fffffff) in
    t.hash <- Int64.mul (Int64.logxor t.hash x) 0x100000001b3L

  let add_float t v = add_int t (int_of_float (v *. 64.))

  let add_color t (c : color) =
    add_int t c.r; add_int t c.g; add_int t c.b; add_int t c.a

  let add_rect t (r : rect) =
    add_float t r.x; add_float t r.y; add_float t r.w; add_float t r.h

  let add_paint t = function
    | Solid -> add_int t 0
    | Linear -> add_int t 1
    | Oklab -> add_int t 2
    | Stripes -> add_int t 3

  let add_radii t (a, b, c, d) =
    add_float t a; add_float t b; add_float t c; add_float t d

  let add_bool t b = add_int t (if b then 1 else 0)

  let add_op t = function
    | Fill o ->
      add_int t 10;
      add_rect t o.frect;
      add_radii t o.fradii;
      add_bool t o.fcontinuous;
      add_color t o.fcolor;
      add_paint t o.fpaint;
      add_color t o.fcolor2;
      add_radii t o.fgradient;
      add_radii t o.fborder;
      add_color t o.fborder_color;
      add_bool t o.fdashed;
      add_int t o.fwide;
      add_float t o.fopacity
    | Shadow o ->
      add_int t 11;
      add_rect t o.srect;
      add_radii t o.sradii;
      add_bool t o.scontinuous;
      add_color t o.scolor;
      add_float t o.sblur;
      add_bool t o.sinset;
      add_rect t o.scast;
      add_radii t o.scast_radii;
      add_bool t o.scast_continuous;
      add_int t o.swide;
      add_float t o.sopacity
    | Glyphs o ->
      add_int t 20;
      add_int t o.gstart; add_int t o.gend;
      add_paint t o.gpaint;
      add_color t o.gcolor; add_color t o.gcolor2;
      add_radii t o.ggradient;
      add_int t o.gwide2; add_float t o.gopacity
    | Image o ->
      add_int t 30;
      add_rect t o.irect2;
      add_radii t o.iradii;
      add_bool t o.icontinuous;
      add_int t o.iimage.iid; add_int t o.iimage.iversion;
      add_rect t o.isrc;
      add_bool t o.igrayscale;
      add_float t o.iopacity
    | Push_clip o ->
      add_int t 1;
      add_rect t o.crect;
      add_radii t o.cradii;
      add_bool t o.ccontinuous
    | Pop_clip -> add_int t 2
    | Effect o ->
      add_int t 40;
      add_rect t o.edrect;
      add_radii t o.edradii;
      add_bool t o.edcontinuous;
      add_int t o.edindex;
      add_float t o.edopacity
    | Hole o ->
      add_int t 50;
      add_rect t o.hrect;
      add_radii t o.hradii;
      add_bool t o.hcontinuous;
      add_float t o.hopacity

  let add_scene t (s : Lui_scene.t) =
    add_int t s.width;
    add_int t s.height;
    List.iter (add_op t) s.ops;
    List.iter
      (fun g ->
        add_float t g.gx; add_float t g.gy;
        add_float t g.gw; add_float t g.gh;
        add_color t g.gcolor;
        add_int t (if g.gcolored then 1 else 0))
      s.glyphs

  let value t = t.hash
end
