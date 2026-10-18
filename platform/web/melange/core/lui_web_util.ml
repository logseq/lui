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

(* CSS repeats the shorter transition list to match the longer one.
   [transition-duration: 150ms] with [opacity, transform] is two 150ms
   longhands, not a mismatch. *)
let repeat_to_length items count =
  let length = List.length items in
  if count = 0 || length = 0 then []
  else
    let rec take index remaining acc =
      if remaining = 0 then List.rev acc
      else
        let item = List.nth items (index mod length) in
        take (index + 1) (remaining - 1) (item :: acc)
    in
    take 0 count []

let align_transition_lists properties durations =
  let property_count = List.length properties in
  let duration_count = List.length durations in
  if property_count = 0 || duration_count = 0 then None
  else if property_count = duration_count then Some (properties, durations)
  else if property_count > duration_count then
    Some (properties, repeat_to_length durations property_count)
  else Some (repeat_to_length properties duration_count, durations)

(* Positive longhands declared on the element. [None] means the lists were
   empty, so the caller must wait a frame before deciding the set is
   complete. *)
let declared_positive_properties document target =
  match computed_transition document target with
  | Some (property, durations) when property <> "" && property <> "none" ->
      let properties =
        List.map String.trim (String.split_on_char ',' property)
      in
      let durations = List.map String.trim durations in
      (match align_transition_lists properties durations with
       | None -> None
       | Some (properties, durations) ->
           Some
             (List.filter_map
                (fun (name, duration) ->
                  if duration_token_is_zero duration then None else Some name)
                (List.combine properties durations)))
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
   fade cannot drop a card that still has a transform. A declared property
   that already has a track does not wait for the next frame: finishing
   that track (including [animation.finish]) releases the surface in the
   same turn. A zero-duration transition releases on the next frame.
   [transition: none] keeps [fallback] instead of releasing synchronously.
   One transitioncancel settles only the named track; the wait ends
   immediately when that was the last active track, which is how a modal
   shell test dismisses from a single cancel. *)
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
    let pending = ref [] in
    let any_active () =
      List.exists (fun (_, animation) -> animation_is_active animation) !tracks
    in
    let forget_property target name =
      pending :=
        List.filter
          (fun (tracked, existing) ->
            not (tracked == target && existing = name))
          !pending
    in
    (* A promise can resolve before the next frame reveals a delayed
       transform. A property that already has a track, or that has already
       fired transitionend, does not block. Anything still missing waits
       for that frame, then the adopted tracks alone own the exit. *)
    let blocking_properties () =
      if !seen then [] else !pending
    in
    let settle_if_complete () =
      if
        !settled >= List.length !tracks
        && (not (any_active ()))
        && blocking_properties () = []
      then finish ()
    in
    let watch_track target animation =
      if
        not (List.exists (fun (_, existing) -> existing == animation) !tracks)
      then begin
        tracks := (target, animation) :: !tracks;
        (match
           Js.Nullable.toOption (animation_transition_property animation)
         with
         | Some name -> forget_property target name
         | None -> ());
        ignore
          (animation_finished animation
          |> Js.Promise.catch (fun _ -> Js.Promise.resolve ())
          |> Js.Promise.then_ (fun _ ->
                 settled := !settled + 1;
                 settle_if_complete ();
                 Js.Promise.resolve ()))
      end
    in
    let watch_transition_end target =
      let handler event =
        if
          transition_event_from target event
          && event_type event = "transitionend"
        then begin
          forget_property target (event_property_name event);
          settle_if_complete ()
        end
      in
      W.Element.addEventListener "transitionend" handler target;
      detach :=
        (fun () ->
           W.Element.removeEventListener "transitionend" handler target)
        :: !detach
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
              forget_property target property;
              List.iter
                (fun (_, animation) ->
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
    let arm_fallback () =
      if (not !finished) && !timer = None then
        timer := Some (Js.Global.setTimeout ~f:finish fallback)
    in
    let adopt_later_tracks () =
      if not !finished then begin
        List.iter
          (fun target ->
            List.iter (watch_track target) (finite_surface_animations target))
          targets;
        seen := true;
        if !tracks = [] then
          (* A positive declaration that never produced a track still uses
             the historical timer. [transition: none] takes that path
             immediately, before this frame. *)
          arm_fallback ()
        else settle_if_complete ()
      end
    in
    if finish_on_cancel then List.iter watch_cancel targets;
    List.iter watch_transition_end targets;
    List.iter
      (fun target ->
        (match declared_positive_properties document target with
         | None -> ()
         | Some properties ->
             pending :=
               List.rev_append
                 (List.rev_map (fun name -> (target, name)) properties)
                 !pending);
        List.iter (watch_track target) (finite_surface_animations target))
      targets;
    if
      !tracks = []
      && List.exists (zero_motion_transition document) targets
      && not (List.exists (positive_motion_transition document) targets)
    then Webapi.requestAnimationFrame (fun _ -> finish ())
    else if !tracks = [] && !pending = [] then
      (* transition: none never produces a track. The historical fallback
         keeps the exiting surface mounted until that timer, which is what
         submenu tests advance with a fake clock. *)
      arm_fallback ()
    else begin
      (* Look once more on the next frame so a delayed transform that was
         not in the first snapshot is adopted before any shorter track can
         release the surface. Declared tracks that are already present can
         release on this turn. *)
      Webapi.requestAnimationFrame (fun _ -> adopt_later_tracks ());
      settle_if_complete ()
    end


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
