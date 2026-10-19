(* Overlay and menu interaction state — see lui_overlay.mli for the
   contract. Tracks the topmost presented overlay, its focus ownership, the
   trigger-owned open menu and the focus an owning surface saved. Pure
   transitions: they read the store and return actions the driver
   performs. *)

open Lui_protocol

type state = {
  top : int;
      (* topmost overlay-kind node currently tracked (0 = none) *)
  open_menu : int;      (* trigger-owned menu panel currently open *)
  laid_out_menu : int;  (* open_menu as of the last layout pass *)
  return_focus : (int * int) list;
      (* owning surfaces and their return targets, innermost first *)
}

let initial =
  { top = 0; open_menu = 0; laid_out_menu = 0; return_focus = [] }

let top st = st.top
let open_menu st = st.open_menu
let saved_focus st =
  List.fold_left (fun saved (_, target) -> if target=0 then saved else target)
    0 st.return_focus

(* ---- store classification ---------------------------------------- *)

let overlay_class store id =
  match Lui_query.kind_name store id with
  | "dialog" | "sheet" -> `modal
  | "drawer" -> (
    (* [selected] marks the inline pane control, not a presented
       modal — those mount without the prop. *)
    match Lui_store.prop store id "selected" with
    | Some _ -> `none
    | None -> `modal)
  | "popover" | "dropdown-menu" | "context-menu" | "toast" -> `light
  | _ -> `none

(* Host-owned menu tracking: menu panels declared under a
   [menu-trigger] stay hidden until the trigger toggles them — the
   view does not re-render for menu state. *)
let menu_panel_kind store id =
  match Lui_query.kind_name store id with
  | "dropdown-menu" | "context-menu" -> true
  | _ -> false

let trigger_owned store id =
  menu_panel_kind store id
  && (match Lui_store.parent store id with
     | Some p -> Lui_query.kind_name store p = "menu-trigger"
     | None -> false)

let menu_panel store id =
  List.find_opt (trigger_owned store) (Lui_store.child_ids store id)

(* Host-owned transient visibility: true for menu panels declared
   under a [menu-trigger] that are not the open one. *)
let hidden store st id = trigger_owned store id && id <> st.open_menu

(* Overlay-layer hosts (the [data-overlay-layer] marker) are
   permanent containers that lift popup children into the floating
   layer — e.g. an app's shared popover stack mount. They stay in
   the overlay list so Escape and modal bookkeeping still see the
   layer, but a press outside must not Dismiss them: with nothing
   presented they would swallow every outside press (and the Escape
   fallthrough) for their children. *)
let overlay_dismissible store id =
  Lui_query.event_supported store id (Dismiss id)
  && Lui_query.data_attr store id "data-overlay-layer" <> Some "true"

(* Topmost overlay = last overlay-kind node in paint (preorder)
   order; returns (id, modal, dismiss-admitted). *)
let top_scan store ~open_menu =
  let top = ref None in
  Lui_store.iter_preorder store (fun id ->
    match overlay_class store id with
    | `none -> ()
    | _ when trigger_owned store id && id <> open_menu -> ()
    | _ when Lui_store.inert_in_chain store id
             || not (Lui_store.anchor_available store id) -> ()
    | cls -> top := Some (id, cls = `modal, overlay_dismissible store id));
  !top

let inside store ov path =
  List.exists (fun i -> i = ov || Lui_query.is_desc store i ov) path

let inside_anchor store overlay path =
  if Lui_query.kind_name store overlay <> "popover"
     || Lui_store.string_prop store overlay "anchor" = None
     || Lui_store.prop store overlay "x" <> None
     || Lui_store.prop store overlay "y" <> None then false
  else
    let owner = match Lui_store.string_prop store overlay "anchor-target" with
      | Some identifier -> Lui_store.find_identifier store identifier
      | None -> Lui_store.parent store overlay in
    match owner with
    | Some target when Lui_query.kind_name store target <> "root" -> inside store target path
    | _ -> false

(* Modal focus-trap scope for focusables/tab order. *)
let modal_scope store st =
  match top_scan store ~open_menu:st.open_menu with
  | Some (ov, true, _) -> Some ov
  | _ -> None

(* ---- transitions --------------------------------------------------- *)

let available_focus store id =
  Lui_store.mem store id && Lui_query.node_enabled store id
  && Lui_focus.chain_visible store id
  && not (Lui_store.inert_in_chain store id)

let ordinary_row_menu store menu =
  (match Lui_query.kind_name store menu with
   | "dropdown-menu" -> true
   | "popover" -> Lui_store.string_prop store menu "role" = Some "menu"
   | _ -> false)
  && Lui_gesture.menu_has_items store menu
  && Lui_query.picker_for_menu store menu = None

let initial_menu_focus store menu ~keyboard =
  let is_menu =
    match Lui_query.kind_name store menu with
    | "dropdown-menu" | "context-menu" -> true
    | "popover" -> Lui_store.string_prop store menu "role" = Some "menu"
    | _ -> false
  in
  if not is_menu then None
  else if Lui_gesture.menu_has_items store menu then
    if ordinary_row_menu store menu then
      let row =
        if keyboard then (Lui_gesture.menu_open store ~menu).hl else 0
      in
      Some (if row = 0 then menu else row)
    else None
  else
    let rec first id =
      if
        (not (available_focus store id))
        || (id <> menu && Lui_query.presented_overlay store id)
      then None
      else if id <> menu && Lui_query.focus_candidate store id then Some id
      else List.find_map first (Lui_store.child_ids store id)
    in
    first menu

(* Focus-owning surfaces save their return targets independently. A
   searchable light popover owns initial focus without trapping Tab or
   swallowing outside presses. Nested closure restores the nearest
   available target; closing the whole stack skips removed controls. *)
let sync store st ~focused ~kbd ~keyboard =
  let ov_id, ov_modal =
    match top_scan store ~open_menu:st.open_menu with
    | Some (id, modal, _) -> (id, modal)
    | None -> (0, false)
  in
  (* Loading surfaces can acquire autofocus after their first store sync. *)
    let present id =
      Lui_store.mem store id
      && (not (Lui_store.inert_in_chain store id))
      && Lui_store.anchor_available store id
      && Lui_focus.chain_visible store id
      && ((not (trigger_owned store id)) || id = st.open_menu)
    in
    let closed =
      List.filter (fun (id, _) -> not (present id)) st.return_focus
    in
    let can_return target =
      available_focus store target
      && not
           (List.exists
              (fun (id, _) -> target = id || Lui_query.is_desc store target id)
              closed)
    in
    let return_target =
      List.find_map
        (fun (_, target) -> if can_return target then Some target else None)
        closed
    in
    let return_focus =
      List.filter (fun (id, _) -> present id) st.return_focus
    in
    let focus_unmoved =
      focused = 0
      || (not (available_focus store focused))
      || focused = st.top
      || Lui_query.is_desc store focused st.top
    in
    let focused, restored =
      match return_target with
      | Some target when focus_unmoved -> (target, [ `Focus (target, false) ])
      | _ -> (focused, [])
    in
    let action_focus =
      if ov_modal then None else initial_menu_focus store ov_id ~keyboard
    in
    let autofocus =
      if ov_id = 0 || Lui_query.kind_name store ov_id <> "popover" then false
      else
        let found = ref false in
        Lui_store.iter_preorder ~root:ov_id
          ~descend:(fun _ -> not !found)
          store
          (fun id ->
            if
              Lui_store.bool_prop store id "autofocus"
              && available_focus store id
            then found := true);
        !found
    in
    let focus_owned = ov_modal || Option.is_some action_focus || autofocus in
    let outside =
      focused <> 0 && focused <> ov_id
      && not (Lui_query.is_desc store focused ov_id)
    in
    let return_focus =
      if
        focus_owned
        && not (List.exists (fun (id, _) -> id = ov_id) return_focus)
      then (ov_id, if outside then focused else 0) :: return_focus
      else return_focus
    in
    let focus_kbd = if ordinary_row_menu store ov_id then keyboard else kbd in
    let initial =
      if ov_id = st.top then []
      else if ov_modal then
        `Clear_selection :: (if outside then [ `Focus (0, false) ] else [])
      else
        match action_focus with
        | Some id when outside || focused = 0 -> [ `Focus (id, focus_kbd) ]
        | _ -> []
    in
    ({ st with top = ov_id; return_focus }, restored @ initial)

(* Press outside the open menu closes it host-side — the owning
   trigger counts as inside so a second click toggles rather than
   close-then-reopen. *)
let close_on_outside_press store st path =
  if st.open_menu <> 0
     && not
          (inside store st.open_menu path
           || List.exists
                (fun i -> Lui_store.parent store st.open_menu = Some i)
                path)
  then ({ st with open_menu = 0 }, [ `Repaint ])
  else (st, [])

(* Overlay press semantics: a press outside the top overlay
   light-dismisses it when its kind admits Dismiss; a modal surface
   swallows the press entirely (focus trap). *)
let press store st path =
  match top_scan store ~open_menu:st.open_menu with
  | Some (oid, true, _) when not (inside store oid path) ->
    (st, `Swallow)
  | Some (oid, false, true)
    when not (inside store oid path || inside_anchor store oid path) ->
    (st, `Proceed [ `Dispatch (Dismiss oid) ])
  | _ -> (st, `Proceed [])

(* A click landing anywhere on a menu trigger toggles its owned panel
   (the trigger itself may not be pressable); activating a node inside
   the open panel closes it after the press. *)
let click_menu store st ~path ~pressed =
  match
    List.find_opt
      (fun i -> Lui_query.kind_name store i = "menu-trigger") path
  with
  | Some trig -> (
    match menu_panel store trig with
    | Some m ->
      ({ st with open_menu = (if st.open_menu = m then 0 else m) },
       [ `Repaint ])
    | None -> (st, []))
  | None ->
    if st.open_menu <> 0
       && Lui_query.is_desc store pressed st.open_menu
    then ({ st with open_menu = 0 }, [ `Repaint ])
    else (st, [])

(* Escape peels one layer at a time: the open menu, then a
   dismissible overlay; a non-dismissible top overlay eats the key.
   [`Pass] leaves focus-clear/quit to the driver. *)
type esc =
  [ `Closed_menu
  | `Dismissed of int
  | `Blocked
  | `Pass ]

let escape store st =
  if st.open_menu <> 0 then ({ st with open_menu = 0 }, `Closed_menu)
  else
    match top_scan store ~open_menu:st.open_menu with
    | Some (oid, _, true) -> (st, `Dismissed oid)
    | Some _ -> (st, `Blocked)
    | None -> (st, `Pass)

(* Repaint pacing: the open menu changing under a fixed layout needs a
   layout invalidation before the next frame. *)
let menu_moved st = st.laid_out_menu <> st.open_menu
let menu_laid_out st = { st with laid_out_menu = st.open_menu }
