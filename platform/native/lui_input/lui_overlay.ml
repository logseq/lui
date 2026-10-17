(* Overlay and menu interaction state — see lui_overlay.mli for the
   contract. Tracks the topmost presented overlay, its focus ownership, the
   trigger-owned open menu and the focus an owning surface saved. Pure
   transitions: they read the store and return actions the driver
   performs. *)

open Lui_protocol

type state = {
  top : int;
      (* topmost overlay-kind node currently tracked (0 = none) *)
  focus_owned : bool;   (* modal or ordinary-action menu owns initial focus *)
  open_menu : int;      (* trigger-owned menu panel currently open *)
  laid_out_menu : int;  (* open_menu as of the last layout pass *)
  saved_focus : int;
      (* earliest focus an owning surface saves and restores on close *)
}

let initial =
  { top = 0; focus_owned = false; open_menu = 0; laid_out_menu = 0;
    saved_focus = 0 }

let top st = st.top
let open_menu st = st.open_menu
let saved_focus st = st.saved_focus

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
    | _ when Lui_store.inert_in_chain store id -> ()
    | cls -> top := Some (id, cls = `modal, overlay_dismissible store id));
  !top

let inside store ov path =
  List.exists (fun i -> i = ov || Lui_query.is_desc store i ov) path

let inside_anchor store overlay path =
  match Lui_query.kind_name store overlay,
        Lui_store.string_prop store overlay "anchor", Lui_store.parent store overlay with
  | "popover", Some _, Some owner
    when Lui_query.kind_name store owner <> "root"
         && Lui_store.prop store overlay "x" = None
         && Lui_store.prop store overlay "y" = None -> inside store owner path
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

let action_menu_focus store menu =
  let is_menu =
    match Lui_query.kind_name store menu with
    | "dropdown-menu" | "context-menu" -> true
    | "popover" -> Lui_store.string_prop store menu "role" = Some "menu"
    | _ -> false in
  if not is_menu || Lui_gesture.menu_has_items store menu then None
  else
    let rec first id =
      if not (available_focus store id)
         || (id <> menu && Lui_query.presented_overlay store id) then None
      else if id <> menu
              && Lui_query.focus_candidate store id
      then Some id
      else List.find_map first (Lui_store.child_ids store id)
    in
    first menu

(* Store-sync half: dead saved-focus cleanup, then the top-overlay
   change boundary. Modals and ordinary-action menus save return focus.
   Row menus retain their separate keyboard highlight. A modal owns the
   keyboard while it is top: a focus held outside it is saved (once —
   a stacked modal keeps the earliest save) and cleared via a
   [`Focus (0, false)] intent, so text input, IME and the shortcut
   table cannot reach a background field; [`Clear_selection] drops any
   static-text selection held outside the scope for the same reason.
   On release the save is restored if focus has not moved outside the
   closing surface, and reset so a later overlay cannot resurrect a
   stale target. *)
let sync store st ~focused ~kbd =
  let st =
    if st.saved_focus <> 0 && not (available_focus store st.saved_focus)
    then { st with saved_focus = 0 }
    else st
  in
  let ov_id, ov_modal =
    match top_scan store ~open_menu:st.open_menu with
    | Some (id, m, _) -> (id, m)
    | None -> (0, false)
  in
  if ov_id = st.top then (st, [])
  else begin
    let action_focus = if ov_modal then None else action_menu_focus store ov_id in
    let focus_owned = ov_modal || Option.is_some action_focus in
    let outside =
      focused <> 0 && focused <> ov_id
      && not (Lui_query.is_desc store focused ov_id)
    in
    let saved, acts =
      if focus_owned then
        ( (if outside && st.saved_focus = 0 then focused
           else st.saved_focus),
          if ov_modal then
            `Clear_selection :: (if outside then [ `Focus (0, false) ] else [])
          else match action_focus with
            | Some id when outside || focused = 0 -> [ `Focus (id, kbd) ]
            | _ -> [] )
      else (st.saved_focus, [])
    in
    let released_focus = st.focus_owned && not focus_owned in
    let focus_unmoved = focused = 0 || focused = st.top
      || Lui_query.is_desc store focused st.top in
    let st = { st with saved_focus = saved; top = ov_id; focus_owned } in
    if released_focus then
      if st.saved_focus <> 0 && focus_unmoved then
        ({ st with saved_focus = 0 },
         acts @ [ `Focus (st.saved_focus, false) ])
      else ({ st with saved_focus = 0 }, acts)
    else (st, acts)
  end

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
