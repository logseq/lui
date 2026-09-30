(* Modal surfaces, anchored tooltips, and toasts: the modal open stack,
   inert host attribute, sheet swipe-to-dismiss, modal focus trapping,
   tooltip warm/show/hide timers, and toast swipe/auto-dismiss. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Focus = Lui_web_focus

(* matchMedia exposes an abstract mediaQueryList; "matches" is a plain
   boolean property read — a typed accessor, not a cast. *)
external media_query_matches : W.Window.mediaQueryList -> bool = "matches"
  [@@mel.get]

type selection
external document_selection : Dom.document -> selection option = "getSelection"
  [@@mel.send] [@@mel.return nullable]
external selection_collapsed : selection -> bool = "isCollapsed" [@@mel.get]
external pointer_primary : Dom.event -> bool = "isPrimary" [@@mel.get]
external event_type : Dom.event -> string = "type" [@@mel.get]
external has_pointer_capture : Dom.element -> int -> bool = "hasPointerCapture"
  [@@mel.send]
external release_pointer_capture : Dom.element -> int -> unit = "releasePointerCapture"
  [@@mel.send]

let has_text_selection document =
  match document_selection document with
  | Some selection -> not (selection_collapsed selection)
  | None -> false

(* set-style! in the reference writes element.style.setProperty. *)
let set_style_on element name value =
  Lui_web_util.set_style
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
    name value

let string_includes haystack needle =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  let rec search index =
    if index + nlen > hlen then false
    else if String.sub haystack index nlen = needle then true
    else search (index + 1)
  in
  search 0

(* string/replace in the reference replaces every occurrence. *)
let string_replace_all haystack needle replacement =
  let nlen = String.length needle in
  if nlen = 0 then haystack
  else begin
    let buffer = Buffer.create (String.length haystack) in
    let rec loop index =
      if index + nlen <= String.length haystack
         && String.sub haystack index nlen = needle
      then begin
        Buffer.add_string buffer replacement;
        loop (index + nlen)
      end
      else if index < String.length haystack then begin
        Buffer.add_char buffer haystack.[index];
        loop (index + 1)
      end
    in
    loop 0;
    Buffer.contents buffer
  end

(* LG str on floats follows JS String(x): integral floats print without a
   decimal point, which CSS requires for the swipe custom properties. *)
let js_number_string (value : float) = Js.Float.toString value

let clear_timeout slot =
  (match !slot with
   | Some timer_id -> Js.Global.clearTimeout timer_id
   | None -> ());
  slot := None

(* Retained-node queries keyed by a nodes-map snapshot. *)

let modal_node nodes node =
  match Hashtbl.find_opt nodes node with
  | Some current ->
      (match Store.standard_kind current with
       | Some kind -> modal_surface kind
       | None -> false)
  | None -> false

let modal_node_ = modal_node

let modal_layer_node = Lui_web_util.modal_layer_node

let anchored_tooltip current = Store.anchored_tooltip current
let anchored_tooltip_ = anchored_tooltip

let anchored_tooltip_node nodes node =
  match Hashtbl.find_opt nodes node with
  | Some current -> anchored_tooltip current
  | None -> false

let anchored_tooltip_node_ = anchored_tooltip_node

(* compact-sheet? mirrors the original: a simulated phone is always
   compact; otherwise the document element width decides. *)
let compact_sheet renderer =
  match !(renderer.web_simulator_device) with
  | Some device -> device.simulator_device_form_factor = SimulatorPhone
  | None ->
      let root = W.Document.documentElement renderer.web_document in
      W.Element.clientWidth root <= 640

let document_body_focused renderer =
  let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
  match W.HtmlDocument.activeElement document with
  | Some focused ->
      (match W.HtmlDocument.body document with
       | Some body -> W.Element.isSameNode (W.Element.asNode body) focused
       | None -> false)
  | None -> false

(* Modal open stack. *)

let topmost_modal renderer node =
  match Lui_web_layers.topmost_blocking renderer.web_layers with
  | Some layer -> layer.id = node
  | None -> false

let refresh_modal_host_inert renderer =
  Lui_web_util.set_state_attribute
    renderer.web_host "inert"
    (Lui_web_layers.has_blocking_present renderer.web_layers);
  true

let refresh_modal_host_inert_bang = refresh_modal_host_inert

(* Modal focus trapping. *)

let modal_focus_selector =
  "button,input,textarea,select,a[href],[contenteditable],[tabindex],[autofocus]"

let modal_focus_items renderer parent =
  let roots = Lui_web_layers.focus_roots renderer.web_layers parent in
  let focusables root =
    let nodes = W.Element.querySelectorAll modal_focus_selector root in
    let rec collect index result =
      if index = W.NodeList.length nodes then List.rev result
      else
        match W.NodeList.item index nodes with
        | Some candidate ->
            (match W.Element.ofNode candidate with
             | Some candidate_element ->
                 if
                   (W.Element.hasAttribute "autofocus" candidate_element
                    && Focus.focus_target_available candidate_element)
                   || Focus.sequential_focus_target_available candidate_element
                 then collect (index + 1) (candidate_element :: result)
                 else collect (index + 1) result
             | None -> collect (index + 1) result)
        | None -> collect (index + 1) result
    in
    let candidates = collect 0 [] in
    let explicit, sequential =
      List.partition
        (fun candidate -> W.Element.hasAttribute "autofocus" candidate)
        candidates
    in
    explicit @ sequential
  in
  List.fold_left
    (fun result root -> List.rev_append (focusables root) result)
    [] roots
  |> List.rev

let focused_element_index elements focused =
  let rec scan items index =
    match items with
    | [] -> -1
    | item :: rest ->
        if W.Element.isSameNode (W.Element.asNode item) focused then index
        else scan rest (index + 1)
  in
  scan elements 0

(* Swipe guardrails shared by sheet and toast dismissal. *)

let rec swipe_ignored_target target boundary =
  if W.Element.isSameNode (W.Element.asNode target) boundary then false
  else begin
    let role = W.Element.getAttribute "role" target in
    let class_name = W.Element.getAttribute "class" target in
    let ignored =
      W.Element.hasAttribute "data-lui-swipe-ignore" target
      || W.Element.matches
           "button,input,textarea,select,option,a,[contenteditable]:not([contenteditable=false]),[role=link],[role=slider],[role=checkbox],[role=switch]"
           target
      || W.Element.hasAttribute "type" target
      || W.Element.hasAttribute "href" target
      || role = Some "button"
      ||
      (match class_name with
       | Some value ->
           string_includes value "lui-textarea"
           || string_includes value "lui-input"
       | None -> false)
    in
    if ignored then true
    else
      match W.Element.parentElement target with
      | Some parent -> swipe_ignored_target parent boundary
      | None -> false
  end

let rec sheet_scroll_blocks_swipe target boundary =
  if W.Element.isSameNode (W.Element.asNode target) boundary then false
  else if
    W.Element.scrollHeight target > W.Element.clientHeight target
    && W.Element.scrollTop target > 0.5
  then true
  else
    match W.Element.parentElement target with
    | Some parent -> sheet_scroll_blocks_swipe parent boundary
    | None -> false

(* Popup transitions. *)

let begin_popup_open popup =
  W.Element.removeAttribute "data-closed" popup;
  W.Element.removeAttribute "data-ending-style" popup;
  W.Element.setAttribute "data-open" "" popup;
  W.Element.setAttribute "data-starting-style" "" popup;
  Webapi.requestAnimationFrame
    (fun _time -> W.Element.removeAttribute "data-starting-style" popup);
  true

let begin_popup_open_bang = begin_popup_open

let begin_popup_close popup =
  W.Element.removeAttribute "data-open" popup;
  W.Element.setAttribute "data-closed" "" popup;
  W.Element.setAttribute "data-ending-style" "" popup;
  true

let begin_popup_close_bang = begin_popup_close

let prefers_reduced_motion document =
  let html_document = W.Document.unsafeAsHtmlDocument document in
  match W.HtmlDocument.defaultView html_document with
  | Some window ->
      media_query_matches
        (W.Window.matchMedia "(prefers-reduced-motion: reduce)" window)
  | None -> false

let transition_event_from target event =
  W.Element.isSameNode
    (W.Element.asNode
       (W.EventTarget.unsafeAsElement (W.Event.target event)))
    target

let after_transition document target fallback_duration finish_on_cancel
    complete =
  if prefers_reduced_motion document then begin
    ignore (complete ());
    true
  end
  else begin
    let finished = ref false in
    let timer = ref None in
    let finish_ref = ref (fun () -> true) in
    let transition_handler event =
      if transition_event_from target event then
        ignore (!(finish_ref) ())
    in
    let finish () =
      if not !finished then begin
        finished := true;
        (match !timer with
         | Some timer_id -> Js.Global.clearTimeout timer_id
         | None -> ());
        W.Element.removeEventListener
          "transitionend" transition_handler target;
        if finish_on_cancel then
          W.Element.removeEventListener
            "transitioncancel" transition_handler target;
        ignore (complete ())
      end;
      true
    in
    finish_ref := finish;
    W.Element.addEventListener "transitionend" transition_handler target;
    if finish_on_cancel then
      W.Element.addEventListener
        "transitioncancel" transition_handler target;
    timer :=
      Some
        (Js.Global.setTimeout ~f:(fun () -> ignore (finish ()))
           fallback_duration);
    true
  end

let after_transition_bang = after_transition

let finish_popup_close_after_transition ?(on_finish = fun () -> ()) document
    popup duration =
  ignore
    (after_transition document popup duration true (fun () ->
         if W.Element.getAttribute "data-ending-style" popup = Some ""
         then W.Element.removeAttribute "data-ending-style" popup;
         on_finish ();
         true));
  true

let finish_popup_close_after_transition_bang =
  finish_popup_close_after_transition

let restore_modal_focus renderer node surface =
  match Hashtbl.find_opt renderer.web_modal_focus_returns node with
  | Some target ->
      let available = Lui_web_focus.focus_target_available target in
      if available then
        Lui_web_focus.restore_focus_if_unmoved renderer ~closing:surface
          (Some target);
      if available || not (Lui_web_layers.is_present renderer.web_layers node)
      then Hashtbl.remove renderer.web_modal_focus_returns node
  | None -> ()

let close_modal_shell ?(on_finish = fun () -> ()) renderer node parent layer
    surface kind =
  let token =
    Lui_web_layers.close_layer renderer.web_layers renderer.web_document node
  in
  W.Element.setAttribute "data-lui-modal-state" "closed" layer;
  W.Element.removeAttribute "data-open" layer;
  W.Element.setAttribute "data-closed" "" layer;
  W.Element.setAttribute "data-ending-style" "" layer;
  W.Element.removeAttribute "data-open" surface;
  W.Element.setAttribute "data-closed" "" surface;
  W.Element.setAttribute "data-ending-style" "" surface;
  W.Element.setAttribute "inert" "" layer;
  W.Element.setAttribute "inert" "" surface;
  let transition_target =
    if kind = Some Sheet then surface
    else Lui_web_util.child_element layer 0
  in
  let duration = if kind = Some Sheet then 470 else 170 in
  after_transition renderer.web_document transition_target duration true
    (fun () ->
      if
        Lui_web_layers.transition renderer.web_layers node = token
        && not (Lui_web_layers.is_open renderer.web_layers node)
      then begin
        if W.Element.contains (W.Element.asNode layer) parent then
          ignore (W.Element.removeChild (W.Element.asNode layer) parent);
        Lui_web_layers.finish_present renderer.web_layers
          renderer.web_document node token;
        if Store.node renderer.web_store node = None then
          Lui_web_layers.remove renderer.web_layers renderer.web_document node;
        ignore (refresh_modal_host_inert renderer);
        W.Element.removeAttribute "data-ending-style" surface;
        on_finish ()
      end;
      true)

(* Modal event wiring. *)

type modal_swipe_state = {
  swipe_pointer : int option ref;
  swipe_start_x : float ref;
  swipe_start_y : float ref;
  swipe_current_y : float ref;
  swipe_start_time : float ref;
  swipe_axis : string option ref;
}

type modal_context = {
  modal_renderer : web_renderer;
  modal_node_id : int;
  modal_dom_node : Dom.element;
  modal_layer : Dom.element;
  modal_backdrop : Dom.element;
  modal_sheet : bool;
  modal_swipe : modal_swipe_state;
}

let modal_reset_swipe ctx =
  let state = ctx.modal_swipe in
  let pointer = !(state.swipe_pointer) in
  state.swipe_pointer := None;
  state.swipe_axis := None;
  (match pointer with
   | Some id when has_pointer_capture ctx.modal_dom_node id ->
       release_pointer_capture ctx.modal_dom_node id
   | _ -> ());
  W.Element.removeAttribute "data-swiping" ctx.modal_dom_node;
  W.Element.removeAttribute "data-swipe-direction" ctx.modal_dom_node;
  set_style_on ctx.modal_dom_node "--drawer-swipe-movement-y" "0px";
  set_style_on ctx.modal_backdrop "--drawer-swipe-progress" "1";
  true

let modal_dismiss ctx =
  if
    topmost_modal ctx.modal_renderer ctx.modal_node_id
    && W.Element.getAttribute "data-lui-modal-state" ctx.modal_layer
       = Some "open"
  then
    ignore
      (!(ctx.modal_renderer.web_event_handler)
         (Dismiss ctx.modal_node_id));
  true

let modal_pointer_down ctx event =
  let target = W.EventTarget.unsafeAsElement (W.Event.target event) in
  let compact = compact_sheet ctx.modal_renderer in
  let ignored = swipe_ignored_target target ctx.modal_dom_node in
  let scroll_blocked =
    sheet_scroll_blocks_swipe target ctx.modal_dom_node
  in
  let mouse = Lui_web_util.pointer_mouse_event event in
  if not (pointer_primary event) || !(ctx.modal_swipe.swipe_pointer) <> None
  then ignore (modal_reset_swipe ctx)
  else if
    ctx.modal_sheet && compact
    && Lui_web_util.pointer_type event = "touch"
    && W.MouseEvent.button mouse = 0
    && (not ignored) && not scroll_blocked
    && not (has_text_selection ctx.modal_renderer.web_document)
  then begin
    let x = float_of_int (W.MouseEvent.clientX mouse) in
    let y = float_of_int (W.MouseEvent.clientY mouse) in
    let state = ctx.modal_swipe in
    state.swipe_pointer := Some (Lui_web_util.pointer_id event);
    state.swipe_start_x := x;
    state.swipe_start_y := y;
    state.swipe_current_y := y;
    state.swipe_start_time := W.Event.timeStamp event
  end;
  ()

let modal_pointer_move ctx event =
  let state = ctx.modal_swipe in
  match !(state.swipe_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      let mouse = Lui_web_util.pointer_mouse_event event in
      let delta_x =
        Float.abs
          (float_of_int (W.MouseEvent.clientX mouse)
           -. !(state.swipe_start_x))
      in
      let delta_y =
        float_of_int (W.MouseEvent.clientY mouse)
        -. !(state.swipe_start_y)
      in
      let target = W.EventTarget.unsafeAsElement (W.Event.target event) in
      if
        !(state.swipe_axis) = None
        && max delta_x (Float.abs delta_y) > 8.0
      then begin
        state.swipe_axis :=
          Some
            (if delta_x >= Float.abs delta_y || delta_y <= 0.0
                || sheet_scroll_blocks_swipe target ctx.modal_dom_node
                || has_text_selection ctx.modal_renderer.web_document
             then "rejected"
             else "vertical");
        if !(state.swipe_axis) = Some "vertical" && W.Event.isTrusted event then
          W.Element.setPointerCapture
            (W.PointerEvent.pointerId (Lui_web_util.as_pointer_event event))
            ctx.modal_dom_node
      end;
      if !(state.swipe_axis) = Some "vertical" then begin
        let movement = max 0.0 delta_y in
        W.Event.preventDefault event;
        state.swipe_current_y :=
          float_of_int (W.MouseEvent.clientY mouse);
        W.Element.setAttribute "data-swiping" "" ctx.modal_dom_node;
        W.Element.setAttribute
          "data-swipe-direction" "down" ctx.modal_dom_node;
        set_style_on ctx.modal_dom_node "--drawer-swipe-movement-y"
          (js_number_string movement ^ "px");
        set_style_on ctx.modal_backdrop "--drawer-swipe-progress"
          (js_number_string
             (max 0.0
                (1.0
                 -. movement
                      /. float_of_int
                           (W.Element.clientHeight ctx.modal_dom_node))))
      end
  | _ -> ()

let modal_pointer_end ctx event =
  let state = ctx.modal_swipe in
  match !(state.swipe_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      let delta =
        max 0.0 (!(state.swipe_current_y) -. !(state.swipe_start_y))
      in
      let threshold =
        max 96.0
          (0.25
           *. float_of_int (W.Element.clientHeight ctx.modal_dom_node))
      in
      let duration =
        max 1.0 (W.Event.timeStamp event -. !(state.swipe_start_time))
      in
      let velocity = delta /. duration in
      ignore (modal_reset_swipe ctx);
      if delta > threshold || (delta >= 48.0 && velocity >= 0.5) then
        ignore (modal_dismiss ctx)
  | _ -> ()

let modal_pointer_cancel ctx event =
  match !(ctx.modal_swipe.swipe_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      if event_type event <> "lostpointercapture" then
        ignore (modal_reset_swipe ctx)
      else begin
        let target = W.EventTarget.unsafeAsElement (W.Event.target event) in
        if
          W.Node.isSameNode
            (W.Element.asNode target)
            (W.Element.asNode ctx.modal_dom_node)
          || not (has_pointer_capture ctx.modal_dom_node active_pointer_id)
        then ignore (modal_reset_swipe ctx)
      end
  | _ -> ()

let modal_focus_trap_wrap event items focused backwards =
  let index = focused_element_index items focused in
  if
    items <> []
    && (index = -1
        || (backwards && index = 0)
        || ((not backwards) && index = List.length items - 1))
  then begin
    W.KeyboardEvent.preventDefault event;
    Lui_web_util.focus_element
      (if backwards then List.nth items (List.length items - 1)
       else List.nth items 0)
  end

let modal_key_handler ctx event =
  if topmost_modal ctx.modal_renderer ctx.modal_node_id then begin
    let key = W.KeyboardEvent.key event in
    if key = "Escape" then begin
      W.KeyboardEvent.preventDefault event;
      ignore (modal_dismiss ctx)
    end
    else if key = "Tab" then begin
      let items =
        modal_focus_items ctx.modal_renderer ctx.modal_node_id
      in
      let backwards = W.KeyboardEvent.shiftKey event in
      match items with
      | [] ->
          W.KeyboardEvent.preventDefault event;
          Lui_web_util.focus_element ctx.modal_dom_node
      | _ ->
          let focused =
            W.EventTarget.unsafeAsElement (W.KeyboardEvent.target event)
          in
          modal_focus_trap_wrap event items focused backwards
    end
  end

let attach_modal_events renderer node dom_node =
  let layer = modal_layer_node dom_node in
  let ctx = {
    modal_renderer = renderer;
    modal_node_id = node;
    modal_dom_node = dom_node;
    modal_layer = layer;
    modal_backdrop = Lui_web_util.child_element layer 0;
    modal_sheet =
      (match Store.node renderer.web_store node with
       | Some current -> Store.standard_kind_is current Sheet
       | None -> false);
    modal_swipe = {
      swipe_pointer = ref None;
      swipe_start_x = ref 0.0;
      swipe_start_y = ref 0.0;
      swipe_current_y = ref 0.0;
      swipe_start_time = ref 0.0;
      swipe_axis = ref None;
    };
  } in
  let click_handler _event = ignore (modal_dismiss ctx) in
  let pointer_down_handler event = modal_pointer_down ctx event in
  let pointer_move_handler event = modal_pointer_move ctx event in
  let pointer_end_handler event = modal_pointer_end ctx event in
  let pointer_cancel_handler event = modal_pointer_cancel ctx event in
  let key_handler event = modal_key_handler ctx event in
  let owner =
    match Store.node renderer.web_store node with
    | Some current -> current.retained_parent
    | None -> None
  in
  let kind =
    match Store.node renderer.web_store node with
    | Some current -> Store.standard_kind current
    | None -> None
  in
  ignore
    (Lui_web_layers.register renderer.web_layers
       ~document:renderer.web_document ~id:node ~owner ~trigger:None
       ~content:dom_node ~style_targets:[layer; ctx.modal_backdrop; dom_node]
       ~policy:Lui_web_layers.Blocking
       ~dismiss:(fun () -> ignore (modal_dismiss ctx))
       ~close:(fun () ->
         ignore
           (close_modal_shell
              ~on_finish:(fun () ->
                restore_modal_focus renderer node dom_node)
              renderer node renderer.web_portal_root layer dom_node kind))
       ~key_handler ~present:false ~open_:false);
  W.Element.addEventListener "click" click_handler ctx.modal_backdrop;
  if ctx.modal_sheet then begin
    W.Element.addEventListener "pointerdown" pointer_down_handler dom_node;
    W.Element.addEventListener "pointermove" pointer_move_handler dom_node;
    W.Element.addEventListener "pointerup" pointer_end_handler dom_node;
    W.Element.addEventListener
      "pointercancel" pointer_cancel_handler dom_node;
    W.Element.addEventListener
      "lostpointercapture" pointer_cancel_handler dom_node
  end;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      ignore
        (Lui_web_layers.close_layer renderer.web_layers renderer.web_document
           node);
      W.Element.setAttribute "data-lui-modal-state" "closed" layer;
      W.Element.removeAttribute "data-open" layer;
      W.Element.setAttribute "data-closed" "" layer;
      W.Element.setAttribute "data-ending-style" "" layer;
      W.Element.removeAttribute "data-open" dom_node;
      W.Element.setAttribute "data-closed" "" dom_node;
      W.Element.setAttribute "data-ending-style" "" dom_node;
      W.Element.setAttribute "inert" "" layer;
      ignore (refresh_modal_host_inert renderer);
      W.Element.removeEventListener "click" click_handler
        ctx.modal_backdrop;
      if ctx.modal_sheet then begin
        ignore (modal_reset_swipe ctx);
        W.Element.removeEventListener
          "pointerdown" pointer_down_handler dom_node;
        W.Element.removeEventListener
          "pointermove" pointer_move_handler dom_node;
        W.Element.removeEventListener
          "pointerup" pointer_end_handler dom_node;
        W.Element.removeEventListener
          "pointercancel" pointer_cancel_handler dom_node;
        W.Element.removeEventListener
          "lostpointercapture" pointer_cancel_handler dom_node
      end;
      restore_modal_focus renderer node ctx.modal_dom_node;
      if not (Lui_web_layers.is_present renderer.web_layers node) then
        Lui_web_layers.remove renderer.web_layers renderer.web_document node;
      ignore true)

let attach_modal_events_bang = attach_modal_events

(* Modal lifecycle. *)

let open_modal renderer node dom_node =
  let layer = modal_layer_node dom_node in
  if
    W.Element.getAttribute "data-lui-modal-state" layer <> Some "open"
  then begin
    let return_focus =
      match !(renderer.web_modal_return_focus) with
      | Some element -> Some element
      | None ->
          W.HtmlDocument.activeElement
            (W.Document.unsafeAsHtmlDocument renderer.web_document)
    in
    renderer.web_modal_return_focus := None;
    (match return_focus with
     | Some element ->
         Hashtbl.replace renderer.web_modal_focus_returns node element
     | None -> Hashtbl.remove renderer.web_modal_focus_returns node);
    W.Element.removeAttribute "hidden" layer;
    W.Element.removeAttribute "inert" layer;
    W.Element.removeAttribute "data-closed" layer;
    W.Element.removeAttribute "data-ending-style" layer;
    W.Element.setAttribute "data-open" "" layer;
    W.Element.setAttribute "data-starting-style" "" layer;
    W.Element.removeAttribute "data-closed" dom_node;
    W.Element.removeAttribute "data-ending-style" dom_node;
    W.Element.setAttribute "data-open" "" dom_node;
    W.Element.setAttribute "data-starting-style" "" dom_node;
    W.Element.setAttribute "data-lui-modal-state" "open" layer;
    Lui_web_layers.reconcile_owner renderer.web_layers renderer.web_document
      node
      (match Store.node renderer.web_store node with
       | Some current -> current.retained_parent
       | None -> None);
    Lui_web_layers.open_layer renderer.web_layers renderer.web_document node;
    ignore (refresh_modal_host_inert renderer);
    Webapi.requestAnimationFrame (fun _time ->
        W.Element.removeAttribute "data-starting-style" layer;
        W.Element.removeAttribute "data-starting-style" dom_node;
        if
          W.Element.getAttribute "data-lui-modal-state" layer = Some "open"
        then
          let html_document =
            W.Document.unsafeAsHtmlDocument renderer.web_document
          in
          match W.HtmlDocument.activeElement html_document with
          | Some active
            when Lui_web_layers.owns_target renderer.web_layers node active ->
              ()
          | _ ->
              (match modal_focus_items renderer node with
               | first :: _ ->
                   Lui_web_util.focus_element_without_scroll first
               | [] ->
                   if not (W.Element.hasAttribute "tabindex" dom_node) then
                     W.Element.setAttribute "tabindex" "-1" dom_node;
                   Lui_web_util.focus_element_without_scroll dom_node))
  end;
  ()

let open_modal_bang = open_modal

let remove_modal_layer_after_exit renderer node parent layer surface kind =
  close_modal_shell
    ~on_finish:(fun () -> restore_modal_focus renderer node surface)
    renderer node parent layer surface kind

let remove_modal_layer_after_exit_bang = remove_modal_layer_after_exit

(* Anchored tooltips. *)

let tooltip_delay renderer node = Store.tooltip_delay renderer node

let rec set_tooltip_open renderer node open_flag =
  let tooltip = Lui_web_nodes.dom_node renderer node in
  if open_flag then begin
    (match !(renderer.web_open_tooltip) with
     | Some previous ->
         if previous <> node then
           (match Store.node renderer.web_store previous with
            | Some _current ->
                let previous_tooltip =
                  Lui_web_nodes.dom_node renderer previous
                in
                Lui_web_popup_tracking.stop previous_tooltip;
                let token =
                  Lui_web_layers.close_layer renderer.web_layers
                    renderer.web_document previous
                in
                ignore (begin_popup_close previous_tooltip);
                ignore
                  (finish_popup_close_after_transition
                     ~on_finish:(fun () ->
                       Lui_web_layers.finish_present renderer.web_layers
                         renderer.web_document previous token)
                     renderer.web_document previous_tooltip 120)
            | None -> ())
     | None -> ());
    renderer.web_open_tooltip := Some node;
    Lui_web_layers.reconcile_owner renderer.web_layers renderer.web_document
      node
      (match Store.node renderer.web_store node with
       | Some current -> current.retained_parent
       | None -> None);
    Lui_web_layers.open_layer renderer.web_layers renderer.web_document node;
    ignore (begin_popup_open tooltip);
    ignore (Lui_web_position.position_tooltip renderer node);
    Lui_web_position.track renderer node tooltip
      ~update:(fun () -> Lui_web_position.position_tooltip renderer node)
      ~on_invalid:(fun () -> set_tooltip_open renderer node false)
  end
  else begin
    Lui_web_popup_tracking.stop tooltip;
    let token =
      Lui_web_layers.close_layer renderer.web_layers renderer.web_document node
    in
    ignore (begin_popup_close tooltip);
    ignore
      (finish_popup_close_after_transition
         ~on_finish:(fun () ->
           Lui_web_layers.finish_present renderer.web_layers
             renderer.web_document node token)
         renderer.web_document tooltip 120);
    if !(renderer.web_open_tooltip) = Some node then
      renderer.web_open_tooltip := None
  end;
  ()

let set_tooltip_open_bang = set_tooltip_open

let add_tooltip_description trigger tooltip_id =
  (match W.Element.getAttribute "aria-describedby" trigger with
   | Some current ->
       if
         not
           (string_includes
              (" " ^ current ^ " ") (" " ^ tooltip_id ^ " "))
       then
         W.Element.setAttribute "aria-describedby"
           (current ^ " " ^ tooltip_id) trigger
   | None ->
       W.Element.setAttribute "aria-describedby" tooltip_id trigger);
  true

let remove_tooltip_description trigger tooltip_id =
  (match W.Element.getAttribute "aria-describedby" trigger with
   | Some current ->
       let next =
         String.trim (string_replace_all current tooltip_id "")
       in
       if next = "" then
         W.Element.removeAttribute "aria-describedby" trigger
       else W.Element.setAttribute "aria-describedby" next trigger
   | None -> ());
  true

(* Tooltip timers: show/hide delays plus the "warm" window that skips the
   delay when the user moves between anchored triggers. *)

type tooltip_state = {
  pointer_inside : bool ref;
  origin : string ref;
  show_timer : Js.Global.timeoutId option ref;
  hide_timer : Js.Global.timeoutId option ref;
  warm_timer : Js.Global.timeoutId option ref;
}

type tooltip_context = {
  tooltip_renderer : web_renderer;
  tooltip_node_id : int;
  tooltip_state : tooltip_state;
}

let tooltip_cancel_show ctx = clear_timeout ctx.tooltip_state.show_timer
let tooltip_cancel_hide ctx = clear_timeout ctx.tooltip_state.hide_timer

let tooltip_cancel_warm ctx =
  clear_timeout ctx.tooltip_state.warm_timer;
  ctx.tooltip_renderer.web_tooltip_warm := false

let tooltip_cancel_all ctx =
  tooltip_cancel_show ctx;
  tooltip_cancel_hide ctx

let tooltip_warm ctx =
  tooltip_cancel_warm ctx;
  ctx.tooltip_renderer.web_tooltip_warm := true;
  ctx.tooltip_state.warm_timer :=
    Some
      (Js.Global.setTimeout ~f:(fun () ->
           ctx.tooltip_state.warm_timer := None;
           ctx.tooltip_renderer.web_tooltip_warm := false)
         400)

let tooltip_show ctx next_origin =
  tooltip_cancel_all ctx;
  ctx.tooltip_state.origin := next_origin;
  set_tooltip_open ctx.tooltip_renderer ctx.tooltip_node_id true

let tooltip_hide ctx warm =
  tooltip_cancel_all ctx;
  if warm && !(ctx.tooltip_state.origin) = "pointer" then
    tooltip_warm ctx;
  set_tooltip_open ctx.tooltip_renderer ctx.tooltip_node_id false;
  ctx.tooltip_state.origin := ""

let tooltip_pointer_enter ctx event =
  if Lui_web_util.pointer_type event <> "touch" then begin
    ctx.tooltip_state.pointer_inside := true;
    tooltip_cancel_hide ctx;
    let delay =
      if !(ctx.tooltip_renderer.web_tooltip_warm) then 0
      else tooltip_delay ctx.tooltip_renderer ctx.tooltip_node_id
    in
    if delay = 0 then tooltip_show ctx "pointer"
    else
      ctx.tooltip_state.show_timer :=
        Some
          (Js.Global.setTimeout ~f:(fun () ->
               ctx.tooltip_state.show_timer := None;
               tooltip_show ctx "pointer")
             delay)
  end

let tooltip_pointer_leave ctx _event =
  ctx.tooltip_state.pointer_inside := false;
  tooltip_cancel_show ctx;
  ctx.tooltip_state.hide_timer :=
    Some
      (Js.Global.setTimeout ~f:(fun () ->
           ctx.tooltip_state.hide_timer := None;
           tooltip_hide ctx true)
         50)

let tooltip_focus_in ctx _event = tooltip_show ctx "focus"

let tooltip_focus_out ctx _event =
  tooltip_cancel_hide ctx;
  ctx.tooltip_state.hide_timer :=
    Some
      (Js.Global.setTimeout ~f:(fun () ->
           ctx.tooltip_state.hide_timer := None;
           if not !(ctx.tooltip_state.pointer_inside) then
             tooltip_hide ctx false)
         0)

let tooltip_press ctx _event =
  tooltip_cancel_warm ctx;
  tooltip_hide ctx false

let tooltip_key ctx event =
  if
    W.KeyboardEvent.key event = "Escape"
    && !(ctx.tooltip_renderer.web_open_tooltip)
       = Some ctx.tooltip_node_id
  then begin
    W.KeyboardEvent.preventDefault event;
    tooltip_cancel_warm ctx;
    tooltip_hide ctx false
  end

let mount_tooltip renderer node tooltip =
  let trigger = Lui_web_nodes.dropdown_anchor_node renderer node in
  let tooltip_id = Lui_web_util.node_dom_id node in
  let ctx = {
    tooltip_renderer = renderer;
    tooltip_node_id = node;
    tooltip_state = {
      pointer_inside = ref false;
      origin = ref "";
      show_timer = ref None;
      hide_timer = ref None;
      warm_timer = ref None;
    };
  } in
  let pointer_enter_handler event = tooltip_pointer_enter ctx event in
  let pointer_leave_handler event = tooltip_pointer_leave ctx event in
  let focus_in_handler event = tooltip_focus_in ctx event in
  let focus_out_handler event = tooltip_focus_out ctx event in
  let press_handler event = tooltip_press ctx event in
  let key_handler event = tooltip_key ctx event in
  ignore (add_tooltip_description trigger tooltip_id);
  let owner =
    match Store.node renderer.web_store node with
    | Some current -> current.retained_parent
    | None -> None
  in
  ignore
    (Lui_web_layers.register renderer.web_layers
       ~document:renderer.web_document ~id:node ~owner
       ~trigger:(Some trigger) ~content:tooltip ~style_targets:[tooltip]
       ~policy:Lui_web_layers.Nonblocking ~dismiss:(fun () ->
         tooltip_hide ctx false)
       ~close:(fun () -> set_tooltip_open renderer node false)
       ~key_handler ~present:false ~open_:false);
  W.Element.addEventListener "pointerenter" pointer_enter_handler trigger;
  W.Element.addEventListener "pointerleave" pointer_leave_handler trigger;
  W.Element.addEventListener "focusin" focus_in_handler trigger;
  W.Element.addEventListener "focusout" focus_out_handler trigger;
  W.Element.addEventListener "pointerdown" press_handler trigger;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      Lui_web_popup_tracking.stop tooltip;
      tooltip_cancel_all ctx;
      tooltip_cancel_warm ctx;
      W.Element.removeAttribute "data-open" tooltip;
      if !(renderer.web_open_tooltip) = Some node then
        renderer.web_open_tooltip := None;
      ignore (remove_tooltip_description trigger tooltip_id);
      W.Element.removeEventListener
        "pointerenter" pointer_enter_handler trigger;
      W.Element.removeEventListener
        "pointerleave" pointer_leave_handler trigger;
      W.Element.removeEventListener "focusin" focus_in_handler trigger;
      W.Element.removeEventListener "focusout" focus_out_handler trigger;
      W.Element.removeEventListener "pointerdown" press_handler trigger;
      Lui_web_layers.remove renderer.web_layers renderer.web_document node;
      ignore true)

let mount_tooltip_bang = mount_tooltip

(* Toasts. *)

let toast_duration renderer node = Store.toast_duration renderer node

let first_toast_node renderer toast =
  let children = W.Element.children renderer.web_toast_viewport in
  match W.HtmlCollection.item 0 children with
  | Some first_toast ->
      W.Element.isSameNode (W.Element.asNode first_toast) toast
  | None -> false

let first_toast_node_ = first_toast_node

type toast_state = {
  toast_timer : Js.Global.timeoutId option ref;
  pointer_inside : bool ref;
  focus_inside : bool ref;
  active_pointer : int option ref;
  start_x : int option ref;
  start_y : int option ref;
  current_x : int ref;
  current_y : int ref;
  toast_axis : string option ref;
}

type toast_context = {
  toast_renderer : web_renderer;
  toast_node_id : int;
  toast_element : Dom.element;
  toast_state : toast_state;
}

let toast_reset_swipe ctx =
  let state = ctx.toast_state in
  let toast = ctx.toast_element in
  state.active_pointer := None;
  state.start_x := None;
  state.start_y := None;
  state.toast_axis := None;
  W.Element.removeAttribute "data-swiping" toast;
  W.Element.removeAttribute "data-swipe-direction" toast;
  set_style_on toast "--toast-swipe-movement-x" "0px";
  set_style_on toast "--toast-swipe-movement-y" "0px"

let toast_cancel ctx = clear_timeout ctx.toast_state.toast_timer

let toast_dismiss ctx =
  toast_cancel ctx;
  ignore
    (!(ctx.toast_renderer.web_event_handler) (Dismiss ctx.toast_node_id))

let toast_schedule ctx =
  toast_cancel ctx;
  let duration =
    toast_duration ctx.toast_renderer ctx.toast_node_id
  in
  if duration > 0 then
    ctx.toast_state.toast_timer :=
      Some
        (Js.Global.setTimeout ~f:(fun () ->
             ctx.toast_state.toast_timer := None;
             toast_dismiss ctx)
           duration)

let toast_resume ctx =
  if
    (not !(ctx.toast_state.pointer_inside))
    && not !(ctx.toast_state.focus_inside)
  then toast_schedule ctx

let toast_pointer_enter ctx _event =
  ctx.toast_state.pointer_inside := true;
  toast_cancel ctx

let toast_pointer_leave ctx _event =
  ctx.toast_state.pointer_inside := false;
  toast_resume ctx

let toast_focus_in ctx _event =
  ctx.toast_state.focus_inside := true;
  toast_cancel ctx

let toast_focus_out ctx _event =
  ctx.toast_state.focus_inside := false;
  toast_resume ctx

let toast_pointer_down ctx event =
  let target = W.EventTarget.unsafeAsElement (W.Event.target event) in
  let interactive = swipe_ignored_target target ctx.toast_element in
  let mouse = Lui_web_util.pointer_mouse_event event in
  if W.MouseEvent.button mouse = 0 && not interactive then begin
    let x = W.MouseEvent.clientX mouse in
    let y = W.MouseEvent.clientY mouse in
    let state = ctx.toast_state in
    state.active_pointer := Some (Lui_web_util.pointer_id event);
    state.start_x := Some x;
    state.start_y := Some y;
    state.current_x := x;
    state.current_y := y;
    if W.Event.isTrusted event then
      W.Element.setPointerCapture
        (W.PointerEvent.pointerId (Lui_web_util.as_pointer_event event))
        ctx.toast_element;
    toast_cancel ctx
  end

let toast_swipe_apply ctx event axis x y origin_x origin_y =
  let toast = ctx.toast_element in
  let delta_x = x - origin_x in
  let delta_y = y - origin_y in
  let dampened delta =
    if delta < 0 then
      -int_of_float (Float.sqrt (float_of_int (abs delta)))
    else delta
  in
  if axis = "horizontal" then begin
    let movement = dampened delta_x in
    W.Event.preventDefault event;
    W.Element.setAttribute "data-swiping" "" toast;
    W.Element.setAttribute "data-swipe-direction"
      (if delta_x < 0 then "left" else "right") toast;
    set_style_on toast "--toast-swipe-movement-x"
      (string_of_int movement ^ "px")
  end
  else begin
    let movement = dampened delta_y in
    W.Event.preventDefault event;
    W.Element.setAttribute "data-swiping" "" toast;
    W.Element.setAttribute "data-swipe-direction"
      (if delta_y < 0 then "up" else "down") toast;
    set_style_on toast "--toast-swipe-movement-y"
      (string_of_int movement ^ "px")
  end

let toast_pointer_move ctx event =
  let state = ctx.toast_state in
  match !(state.active_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      (match !(state.start_x), !(state.start_y) with
       | Some origin_x, Some origin_y ->
           let mouse = Lui_web_util.pointer_mouse_event event in
           let x = W.MouseEvent.clientX mouse in
           let y = W.MouseEvent.clientY mouse in
           let delta_x = x - origin_x in
           let delta_y = y - origin_y in
           state.current_x := x;
           state.current_y := y;
           if
             !(state.toast_axis) = None
             && max (abs delta_x) (abs delta_y) > 4
           then
             state.toast_axis :=
               Some
                 (if abs delta_x > abs delta_y then "horizontal"
                  else "vertical");
           (match !(state.toast_axis) with
            | Some axis ->
                toast_swipe_apply ctx event axis x y origin_x origin_y
            | None -> ())
       | _ -> ())
  | _ -> ()

let toast_pointer_up ctx event =
  let state = ctx.toast_state in
  match !(state.active_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      (match !(state.start_x), !(state.start_y) with
       | Some origin_x, Some origin_y ->
           let delta_x = !(state.current_x) - origin_x in
           let delta_y = !(state.current_y) - origin_y in
           let should_dismiss =
             match !(state.toast_axis) with
             | Some axis ->
                 if axis = "horizontal" then delta_x > 40
                 else delta_y > 40
             | None -> false
           in
           state.active_pointer := None;
           state.start_x := None;
           state.start_y := None;
           if should_dismiss then toast_dismiss ctx
           else begin
             toast_reset_swipe ctx;
             toast_resume ctx
           end
       | _ -> ())
  | _ -> ()

let toast_pointer_cancel ctx event =
  match !(ctx.toast_state.active_pointer) with
  | Some active_pointer_id
    when active_pointer_id = Lui_web_util.pointer_id event ->
      toast_reset_swipe ctx;
      toast_resume ctx
  | _ -> ()

let toast_key ctx event =
  if
    W.KeyboardEvent.key event = "F6"
    && first_toast_node ctx.toast_renderer ctx.toast_element
  then begin
    W.KeyboardEvent.preventDefault event;
    W.HtmlElement.focus
      (W.Element.unsafeAsHtmlElement ctx.toast_element)
  end

let mount_toast renderer node toast =
  let document = renderer.web_document in
  let ctx = {
    toast_renderer = renderer;
    toast_node_id = node;
    toast_element = toast;
    toast_state = {
      toast_timer = ref None;
      pointer_inside = ref false;
      focus_inside = ref false;
      active_pointer = ref None;
      start_x = ref None;
      start_y = ref None;
      current_x = ref 0;
      current_y = ref 0;
      toast_axis = ref None;
    };
  } in
  let pointer_enter_handler event = toast_pointer_enter ctx event in
  let pointer_leave_handler event = toast_pointer_leave ctx event in
  let focus_in_handler event = toast_focus_in ctx event in
  let focus_out_handler event = toast_focus_out ctx event in
  let pointer_down_handler event = toast_pointer_down ctx event in
  let pointer_move_handler event = toast_pointer_move ctx event in
  let pointer_up_handler event = toast_pointer_up ctx event in
  let pointer_cancel_handler event = toast_pointer_cancel ctx event in
  let key_handler event = toast_key ctx event in
  let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
  toast_schedule ctx;
  W.Element.addEventListener "pointerenter" pointer_enter_handler toast;
  W.Element.addEventListener "pointerleave" pointer_leave_handler toast;
  W.Element.addEventListener "focusin" focus_in_handler toast;
  W.Element.addEventListener "focusout" focus_out_handler toast;
  W.Element.addEventListener "pointerdown" pointer_down_handler toast;
  W.Element.addEventListener "pointermove" pointer_move_handler toast;
  W.Element.addEventListener "pointerup" pointer_up_handler toast;
  W.Element.addEventListener "pointercancel" pointer_cancel_handler toast;
  W.Document.addKeyDownEventListener key_handler document;
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      (match previous_cleanup with
       | Some cleanup -> cleanup ()
       | None -> ());
      toast_cancel ctx;
      W.Element.removeEventListener
        "pointerenter" pointer_enter_handler toast;
      W.Element.removeEventListener
        "pointerleave" pointer_leave_handler toast;
      W.Element.removeEventListener "focusin" focus_in_handler toast;
      W.Element.removeEventListener "focusout" focus_out_handler toast;
      W.Element.removeEventListener
        "pointerdown" pointer_down_handler toast;
      W.Element.removeEventListener
        "pointermove" pointer_move_handler toast;
      W.Element.removeEventListener
        "pointerup" pointer_up_handler toast;
      W.Element.removeEventListener
        "pointercancel" pointer_cancel_handler toast;
      W.Document.removeKeyDownEventListener key_handler document;
      ignore true)

let mount_toast_bang = mount_toast
