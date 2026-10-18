(* Low-level DOM helpers shared by every web-backend feature module.
   Nothing here reads the retained store. *)

open Lui_web_types

module W = Webapi.Dom

type surface_animation
type animation_effect
type animation_timing

external element_animations : W.Element.t -> surface_animation array
  = "getAnimations" [@@mel.send]
external animation_finished : surface_animation -> unit Js.Promise.t
  = "finished" [@@mel.get]
external animation_effect : surface_animation -> animation_effect Js.Nullable.t
  = "effect" [@@mel.get]
external effect_timing : animation_effect -> animation_timing
  = "getComputedTiming" [@@mel.send]
external timing_end : animation_timing -> float = "endTime" [@@mel.get]
external animation_cancel : surface_animation -> unit = "cancel" [@@mel.send]
external animation_play_state : surface_animation -> string = "playState"
  [@@mel.get]
external animation_transition_property :
  surface_animation -> string Js.Nullable.t = "transitionProperty"
  [@@mel.get]
external media_query_matches : W.Window.mediaQueryList -> bool = "matches"
  [@@mel.get]
external event_type : Dom.event -> string = "type" [@@mel.get]
external event_is_trusted : Dom.event -> bool = "isTrusted" [@@mel.get]
external event_property_name : Dom.event -> string = "propertyName" [@@mel.get]
external transition_property : W.CssStyleDeclaration.t -> string
  = "transitionProperty" [@@mel.get]
external transition_duration : W.CssStyleDeclaration.t -> string
  = "transitionDuration" [@@mel.get]

let transition_event_from target event =
  W.Element.isSameNode
    (W.Element.asNode
       (W.EventTarget.unsafeAsElement (W.Event.target event)))
    target

let finite_surface_animations target =
  Array.fold_left
    (fun pending animation ->
      let finite =
        match Js.Nullable.toOption (animation_effect animation) with
        | None -> false
        | Some motion_effect ->
            Float.is_finite (timing_end (effect_timing motion_effect))
      in
      if finite then animation :: pending else pending)
    [] (element_animations target)

let duration_token_is_zero token =
  let token = String.trim token in
  let length = String.length token in
  let bare =
    if length > 2 && String.sub token (length - 2) 2 = "ms" then
      String.sub token 0 (length - 2)
    else if length > 1 && token.[length - 1] = 's' then
      String.sub token 0 (length - 1)
    else token
  in
  match Float.of_string_opt (String.trim bare) with
  | Some value -> value = 0.
  | None -> false

let computed_transition document target =
  match
    W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document)
  with
  | None -> None
  | Some window ->
      let style = W.Window.getComputedStyle target window in
      Some
        ( String.trim (transition_property style),
          String.split_on_char ',' (transition_duration style) )

(* A real transition whose every duration is zero never stays in
   getAnimations long enough to await. [transition: none] is not this
   case: it has no property, so the historical fallback timer still
   owns it. *)
let zero_motion_transition document target =
  match computed_transition document target with
  | Some (property, durations)
    when property <> "" && property <> "none" && durations <> [] ->
      List.for_all duration_token_is_zero durations
  | _ -> false

let positive_motion_transition document target =
  match computed_transition document target with
  | Some (property, durations)
    when property <> "" && property <> "none" ->
      List.exists (fun token -> not (duration_token_is_zero token)) durations
  | _ -> false

(* Positive longhands declared on the element. [None] means the property
   and duration lists do not line up, so the caller must wait a frame
   before deciding the set is complete. *)
let declared_positive_properties document target =
  match computed_transition document target with
  | Some (property, durations) when property <> "" && property <> "none" ->
      let properties =
        List.map String.trim (String.split_on_char ',' property)
      in
      let durations = List.map String.trim durations in
      if List.length properties <> List.length durations then None
      else
        Some
          (List.filter_map
             (fun (name, duration) ->
               if duration_token_is_zero duration then None else Some name)
             (List.combine properties durations))
  | _ -> Some []

let animation_is_active animation =
  match animation_play_state animation with
  | "running" | "paused" -> true
  | _ -> false

let transition_property_matches animation property =
  match Js.Nullable.toOption (animation_transition_property animation) with
  | Some name -> name = property
  | None -> false

(* Wait out a surface exit. Reduced motion finishes immediately. Finite
   tracks release together when the last one settles, so a short opacity
   fade cannot drop a card that still has a transform. A zero-duration
   transition releases on the next frame. [transition: none] keeps
   [fallback] instead of releasing synchronously. One transitioncancel
   settles only the named track; the wait ends immediately when that was
   the last active track, which is how a modal shell test dismisses from
   a single cancel. *)
let after_surface_motion document targets ?(finish_on_cancel = false) ~fallback
    complete =
  let reduced_motion =
    match W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document) with
    | Some window ->
        media_query_matches
          (W.Window.matchMedia "(prefers-reduced-motion: reduce)" window)
    | None -> false
  in
  if reduced_motion then ignore (complete ())
  else
    let finished = ref false in
    let timer = ref None in
    let detach = ref [] in
    let tracks = ref [] in
    let settled = ref 0 in
    let finish () =
      if not !finished then begin
        finished := true;
        (match !timer with
         | Some timer_id -> Js.Global.clearTimeout timer_id
         | None -> ());
        List.iter (fun remove -> remove ()) !detach;
        detach := [];
        ignore (complete ())
      end
    in
    let seen = ref false in
    let any_active () = List.exists animation_is_active !tracks in
    let missing_positive_track () =
      List.exists
        (fun target ->
          match declared_positive_properties document target with
          | None -> true
          | Some properties ->
              List.exists
                (fun name ->
                  not
                    (List.exists
                       (fun animation ->
                         transition_property_matches animation name)
                       !tracks))
                properties)
        targets
    in
    let settle_if_complete () =
      (* A promise can resolve before the next frame reveals a delayed
         transform. When every declared positive property already has a
         track, the current set is complete and can release immediately.
         Otherwise wait for that frame, then release once every adopted
         track has settled. *)
      if
        !settled >= List.length !tracks
        && (not (any_active ()))
        && (!seen || not (missing_positive_track ()))
      then finish ()
    in
    let watch_track animation =
      if not (List.exists (fun existing -> existing == animation) !tracks) then begin
        tracks := animation :: !tracks;
        ignore
          (animation_finished animation
          |> Js.Promise.catch (fun _ -> Js.Promise.resolve ())
          |> Js.Promise.then_ (fun _ ->
                 settled := !settled + 1;
                 settle_if_complete ();
                 Js.Promise.resolve ()))
      end
    in
    let watch_cancel target =
      let handler event =
        if
          transition_event_from target event
          && event_type event = "transitioncancel"
        then
          if not (event_is_trusted event) then
            (* A script-dispatched cancel dismisses the whole shell. Browser
               cancels name one property and must leave the other tracks. *)
            finish ()
          else begin
            let property = event_property_name event in
            if property <> "" then begin
              List.iter
                (fun animation ->
                  if
                    transition_property_matches animation property
                    && animation_is_active animation
                  then animation_cancel animation)
                !tracks;
              if not (any_active ()) then finish ()
            end
          end
      in
      W.Element.addEventListener "transitioncancel" handler target;
      detach :=
        (fun () ->
           W.Element.removeEventListener "transitioncancel" handler target)
        :: !detach
    in
    if finish_on_cancel then List.iter watch_cancel targets;
    List.iter
      (fun target -> List.iter watch_track (finite_surface_animations target))
      targets;
    match !tracks with
    | [] ->
        if
          List.exists (zero_motion_transition document) targets
          && not (List.exists (positive_motion_transition document) targets)
        then Webapi.requestAnimationFrame (fun _ -> finish ())
        else
          (* transition: none never produces a track. The historical
             fallback keeps the exiting surface mounted until that timer,
             which is what submenu tests advance with a fake clock. *)
          timer := Some (Js.Global.setTimeout ~f:finish fallback)
    | _ ->
        (* A running or already-finished finite track owns the exit. The
           fallback must not cut off a longer or paused track. Look once
           more on the next frame so a delayed transform that was not in
           the first snapshot is adopted before any shorter track can
           release the surface. *)
        Webapi.requestAnimationFrame (fun _ ->
            if not !finished then begin
              List.iter
                (fun target ->
                  List.iter watch_track (finite_surface_animations target))
                targets;
              seen := true;
              settle_if_complete ()
            end)


(* The DOM is untyped: a "pointerdown" listener receives a Dom.event whose
   runtime representation is a PointerEvent. melange-webapi performs the same
   narrowing with its own %identity externals (EventTarget.asEventTarget,
   Element.unsafeAsHtmlElement); these are the webapi-shaped equivalents for
   the subtypes it does not export. *)
external as_pointer_event : Dom.event -> Dom.pointerEvent = "%identity"
external as_mouse_event : Dom.event -> Dom.mouseEvent = "%identity"
external event_target_to_element : Dom.eventTarget -> Dom.element = "%identity"
external element_to_event_target : Dom.element -> Dom.eventTarget = "%identity"
external node_to_element : Dom.node -> Dom.element = "%identity"
external element_to_html_element : Dom.element -> Dom.htmlElement = "%identity"

external pointer_type_raw : Dom.pointerEvent -> string = "pointerType" [@@mel.get]
external pointer_id_raw : Dom.pointerEvent -> int = "pointerId" [@@mel.get]

let pointer_mouse_event (event : Dom.event) : Dom.mouseEvent = as_mouse_event event
let pointer_type (event : Dom.event) : string = pointer_type_raw (as_pointer_event event)
let pointer_id (event : Dom.event) : int = pointer_id_raw (as_pointer_event event)

external class_name_raw : Dom.element -> string = "className" [@@mel.get]
external client_x : Dom.mouseEvent -> float = "clientX" [@@mel.get]
external client_y : Dom.mouseEvent -> float = "clientY" [@@mel.get]

(* The class list of the deepest element hit by an event. Non-element
   targets (e.g. text nodes) and SVG elements — whose className is an
   SVGAnimatedString, not a string — yield "". *)
let event_target_class_name event =
  let name =
    class_name_raw (event_target_to_element (W.Event.target event))
  in
  if Js.typeof name = "string" then name else ""

external click_detail : Dom.event -> int = "detail" [@@mel.get]

let record_click_open_method element event =
  W.Element.setAttribute "data-lui-open-method"
    (if click_detail event = 0 then "keyboard" else "mouse") element

(* Client-space payload shared by the pointer-detail events. [modifiers]
   uses the PressModifiers bitmask (1=ctrl, 2=shift, 4=meta, 8=secondary
   button); [target_class] is the deepest hit element's class list. *)
let pointer_detail_of event : Lui_protocol.pointer_detail =
  let mouse = pointer_mouse_event event in
  let button = W.MouseEvent.button mouse in
  { x = client_x mouse;
    y = client_y mouse;
    modifiers =
      (if W.MouseEvent.ctrlKey mouse then 1 else 0)
      lor (if W.MouseEvent.shiftKey mouse then 2 else 0)
      lor (if W.MouseEvent.metaKey mouse then 4 else 0)
      lor (if button = 2 then 8 else 0);
    button;
    target_class = event_target_class_name event }

(* Element construction. [attributes] is (name, value) pairs applied before
   children are appended, matching the original element/5 helper. *)
let element document tag class_name attributes children =
  let node = W.Document.createElement tag document in
  List.iter
    (fun (name, value) -> W.Element.setAttribute name value node)
    attributes;
  W.Element.setClassName node class_name;
  List.iter (fun child -> W.Element.appendChild (W.Element.asNode child) node) children;
  node

let child_element dom_node index =
  match W.HtmlCollection.item index (W.Element.children dom_node) with
  | Some child -> child
  | None ->
      invalid_arg
        ("DOM node child is missing: " ^ W.Element.tagName dom_node ^ "."
        ^ W.Element.className dom_node ^ "[" ^ string_of_int index ^ "] of "
        ^ string_of_int
            (W.HtmlCollection.length (W.Element.children dom_node)))

let text_control_node dom_node =
  let tag_name = W.Element.tagName dom_node in
  let candidate =
    if tag_name = "INPUT" || tag_name = "TEXTAREA" then dom_node
    else child_element dom_node 0
  in
  let candidate_tag_name = W.Element.tagName candidate in
  if candidate_tag_name <> "INPUT" && candidate_tag_name <> "TEXTAREA" then
    invalid_arg "DOM node is not a text control";
  match W.HtmlInputElement.ofNode (W.Element.asNode candidate) with
  | Some control -> control
  | None -> invalid_arg "DOM node is not a text control"

let toggle_label_node dom_node = child_element dom_node 1

let owned_child dom_node selector =
  match W.Element.querySelector selector dom_node with
  | Some child -> child
  | None -> invalid_arg ("DOM control slot is missing: " ^ selector)

let button_icon_node dom_node =
  owned_child dom_node
    ":scope > :is(.lui-button-icon, .lui-menu-item-icon, .lui-link-icon)"

let button_label_node dom_node =
  owned_child dom_node ":scope > :is(.lui-button-label, .lui-menu-item-label)"

let menu_item_check_node dom_node =
  owned_child dom_node ":scope > .lui-menu-item-check"

let node_dom_id node = "lui-node-" ^ string_of_int node

let accordion_trigger_node dom_node = child_element dom_node 0
let accordion_panel_node dom_node = child_element dom_node 1
let accordion_label_node dom_node = child_element (accordion_trigger_node dom_node) 0

let initialize_accordion_semantics node dom_node =
  let trigger = accordion_trigger_node dom_node in
  let panel = accordion_panel_node dom_node in
  let trigger_id = node_dom_id node ^ "-trigger" in
  let panel_id = node_dom_id node ^ "-panel" in
  W.Element.setAttribute "id" trigger_id trigger;
  W.Element.setAttribute "id" panel_id panel;
  W.Element.setAttribute "aria-controls" panel_id trigger;
  W.Element.setAttribute "aria-labelledby" trigger_id panel

let insert_dom_child parent child index =
  let children = W.Element.children parent in
  let length = W.HtmlCollection.length children in
  if index = length then
    W.Element.appendChild (W.Element.asNode child) parent
  else
    match W.HtmlCollection.item index children with
    | Some reference ->
        ignore
          (W.Element.insertBefore
             (W.Element.asNode child)
             (W.Element.asNode reference)
             parent)
    | None -> invalid_arg "DOM child index is out of bounds"

let document_body renderer =
  let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
  match W.HtmlDocument.body document with
  | Some body -> body
  | None -> invalid_arg "document body is unavailable"

let modal_layer_node surface =
  match W.Element.parentElement surface with
  | Some layer -> layer
  | None -> invalid_arg "modal surface requires a portal layer"

let bottom_tab_trigger_id node = "lui-bottom-tab-" ^ string_of_int node
let bottom_tabs_pages_node dom_node = child_element dom_node 0
let bottom_tabs_bar_node dom_node = child_element dom_node 1

let focus_element element =
  let html_element = W.Element.unsafeAsHtmlElement element in
  W.HtmlElement.focus html_element

let focus_element_without_scroll element =
  let html_element = W.Element.unsafeAsHtmlElement element in
  W.HtmlElement.focusPreventScroll html_element

let set_style scope name value =
  W.CssStyleDeclaration.setProperty name value "" scope

let set_state_attribute dom_node attribute enabled =
  if enabled then W.Element.setAttribute attribute "" dom_node
  else W.Element.removeAttribute attribute dom_node

let css_url url =
  let buffer = Buffer.create (String.length url + 8) in
  Buffer.add_string buffer "url(\"";
  String.iter
    (fun c ->
       if c = '\\' || c = '"' then Buffer.add_char buffer '\\';
       Buffer.add_char buffer c)
    url;
  Buffer.add_string buffer "\")";
  Buffer.contents buffer

let semantic_color_names =
  [ "background"; "foreground"; "card"; "card-foreground"; "primary";
    "primary-foreground"; "secondary"; "secondary-foreground"; "accent";
    "accent-foreground"; "muted-foreground"; "destructive";
    "destructive-foreground"; "success"; "success-foreground"; "warning";
    "warning-foreground"; "error"; "error-foreground"; "input"; "ring";
    "border" ]

let web_color_value color =
  if color = "transparent" then "transparent"
  (* Material names (Apple glass/bar surfaces) have no CSS equivalent;
     approximate with a translucent theme surface. *)
  else if color = "glass" || color = "glass-container" || color = "bar" then
    "color-mix(in srgb, var(--color-background) 80%, transparent)"
  else if List.mem color semantic_color_names then "var(--color-" ^ color ^ ")"
  else color

(* Shadow wire values embed a color that may be a semantic token; resolve
   bare identifier tokens to the corresponding --color-* CSS var exactly
   like [web_color_value]. Tokens inside parentheses (rgb/oklch/var/
   color-mix arguments) are left untouched, and already-resolved var
   references pass through. *)
let web_shadow_value shadow =
  let buf = Buffer.create (String.length shadow + 16) in
  let word = Buffer.create 16 in
  let depth = ref 0 in
  let flush () =
    if Buffer.length word > 0 then begin
      let token = Buffer.contents word in
      Buffer.clear word;
      if List.mem token semantic_color_names then
        Buffer.add_string buf ("var(--color-" ^ token ^ ")")
      else Buffer.add_string buf token
    end
  in
  String.iter
    (fun c ->
      if !depth > 0 then begin
        Buffer.add_char buf c;
        if c = '(' then incr depth else if c = ')' then decr depth
      end
      else
        match c with
        | '(' ->
            incr depth;
            flush ();
            Buffer.add_char buf c
        | 'a' .. 'z' | 'A' .. 'Z' | '-' -> Buffer.add_char word c
        | c ->
            flush ();
            Buffer.add_char buf c)
    shadow;
  flush ();
  Buffer.contents buf

(* Which element actually receives children for a given node kind. Several
   components keep their content in a wrapper child (dropdown menu surface,
   split panes, modal layers, accordion panels). *)
let content_container kind dom_node =
  match kind with
  | Lui_protocol.DropdownMenu | Lui_protocol.Popover | Lui_protocol.Split ->
      child_element dom_node 0
  | Lui_protocol.Link -> child_element dom_node 1
  | Lui_protocol.Alert -> child_element dom_node 1
  | Lui_protocol.Bubble -> child_element dom_node 0
  | Lui_protocol.Accordion -> accordion_panel_node dom_node
  | kind when Lui_protocol.modal_surface kind -> child_element dom_node 1
  | _ -> dom_node

let set_optional_text element value =
  W.Element.setTextContent element value;
  if value = "" then W.Element.setAttribute "hidden" "" element
  else W.Element.removeAttribute "hidden" element

let some_node value = Some value
