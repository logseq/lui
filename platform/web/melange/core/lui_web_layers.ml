module W = Webapi.Dom

external window_inner_width : W.Window.t -> float = "innerWidth" [@@mel.get]
external parse_float : string -> float = "parseFloat" [@@mel]
external element_style : Dom.element -> W.CssStyleDeclaration.t = "style"
  [@@mel.get]

type visual_viewport
type navigator
external visual_viewport : W.Window.t -> visual_viewport option = "visualViewport"
  [@@mel.get] [@@mel.return nullable]
external viewport_height : visual_viewport -> float = "height" [@@mel.get]
external viewport_top : visual_viewport -> float = "offsetTop" [@@mel.get]
external viewport_left : visual_viewport -> float = "offsetLeft" [@@mel.get]
external viewport_scale : visual_viewport -> float = "scale" [@@mel.get]
external viewport_listen : visual_viewport -> string -> (Dom.event -> unit) -> unit
  = "addEventListener" [@@mel.send]
external viewport_unlisten : visual_viewport -> string -> (Dom.event -> unit) -> unit
  = "removeEventListener" [@@mel.send]
external document_listen :
  W.Document.t -> string -> (Dom.event -> unit) -> bool -> unit
  = "addEventListener" [@@mel.send]
external document_unlisten :
  W.Document.t -> string -> (Dom.event -> unit) -> bool -> unit
  = "removeEventListener" [@@mel.send]
external window_inner_height : W.Window.t -> float = "innerHeight" [@@mel.get]
external window_navigator : W.Window.t -> navigator = "navigator" [@@mel.get]
external navigator_platform : navigator -> string = "platform" [@@mel.get]
external navigator_touch_points : navigator -> int = "maxTouchPoints" [@@mel.get]

let touch_ios window =
  let navigator = window_navigator window in
  navigator_touch_points navigator > 0
  && List.mem (navigator_platform navigator)
       [ "iPhone"; "iPad"; "iPod"; "MacIntel" ]

type modal_policy =
  | Nonblocking
  | Blocking

type layer = {
  id : int;
  mutable owner : int option;
  mutable trigger : Dom.element option;
  mutable content : Dom.element;
  mutable style_targets : Dom.element list;
  mutable policy : modal_policy;
  mutable dismiss : unit -> unit;
  mutable close : unit -> unit;
  mutable key_handler : Dom.keyboardEvent -> unit;
  mutable open_ : bool;
  mutable present : bool;
  mutable transition : int;
  mutable order : int;
  mutable inert_snapshot : (Dom.element * bool) list;
}

type document_lock = {
  document : Dom.document;
  window : W.Window.t;
  root : Dom.element;
  body : Dom.element;
  root_styles : (string * string * string) list;
  body_styles : (string * string * string) list;
  scroll_x : float;
  scroll_y : float;
  mutable stop_viewport : unit -> unit;
  mutable owners : int;
}

type t = {
  layers : (int, layer) Hashtbl.t;
  mutable next_order : int;
  mutable key_listener : (Dom.keyboardEvent -> unit) option;
  mutable pointer_listener : (Dom.event -> unit) option;
  mutable focus_listener : (Dom.event -> unit) option;
  mutable listeners_installed : bool;
  mutable scroll_lock_held : bool;
  mutable is_descendant : (int -> int -> bool) option;
  (* capture-phase pointer tracking: the element under the currently
     held pointer button. press handlers fire inside this pointerdown's
     dispatch — before focus lands — so a popover's mount reads this
     (not activeElement) to learn its real trigger *)
  mutable down_target : Dom.element option;
  mutable target_listeners : (Dom.event -> unit) list;
}

let style_properties =
  [ "overflow"; "overflow-x"; "overflow-y"; "padding-right"; "position";
    "top"; "left"; "right"; "width"; "scroll-behavior";
    "--lui-visual-height"; "--lui-visual-top";
    "--lui-keyboard-inset-limit" ]

let inline_style element =
  element_style element

let style_snapshot element =
  let style = inline_style element in
  List.map
    (fun property ->
      ( property,
        W.CssStyleDeclaration.getPropertyValue property style,
        W.CssStyleDeclaration.getPropertyPriority property style ))
    style_properties

let restore_style element snapshot =
  let style = inline_style element in
  List.iter
    (fun (property, value, priority) ->
      if value = "" then ignore (W.CssStyleDeclaration.removeProperty property style)
      else
        W.CssStyleDeclaration.setProperty property value priority style)
    snapshot

let set_layer_style element order =
  W.Element.setAttribute "data-lui-layer-order" (string_of_int order) element;
  W.CssStyleDeclaration.setProperty "--lui-layer-index" (string_of_int order)
    ""
    (inline_style element)

let set_layer_inert layer inert =
  if inert then begin
    if layer.inert_snapshot = [] then
      layer.inert_snapshot <-
        List.map
          (fun element ->
            (element, W.Element.hasAttribute "inert" element))
          layer.style_targets;
    List.iter (fun element -> W.Element.setAttribute "inert" "" element)
      layer.style_targets
  end
  else begin
    List.iter
      (fun (element, was_inert) ->
        if was_inert then W.Element.setAttribute "inert" "" element
        else W.Element.removeAttribute "inert" element)
      layer.inert_snapshot;
    layer.inert_snapshot <- []
  end

let rec find_lock document = function
  | [] -> None
  | lock :: rest ->
      if W.Node.isSameNode (W.Element.asNode lock.root)
           (W.Element.asNode (W.Document.documentElement document))
      then Some lock
      else find_lock document rest

let locks : document_lock list ref = ref []

let acquire_scroll_lock document =
  match find_lock document !locks with
  | Some lock ->
      lock.owners <- lock.owners + 1
  | None -> (
      match
        ( W.Document.documentElement document,
          W.HtmlDocument.body (W.Document.unsafeAsHtmlDocument document),
          W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document) )
      with
      | root, Some body, Some window ->
          let lock =
            { document;
              window;
              root;
              body;
              root_styles = style_snapshot root;
              body_styles = style_snapshot body;
              scroll_x = W.Window.scrollX window;
              scroll_y = W.Window.scrollY window;
              stop_viewport = (fun () -> ());
              owners = 1 }
          in
          let scrollbar_width =
            max 0.
              (window_inner_width window
               -. float_of_int (W.Element.clientWidth root))
          in
          if scrollbar_width > 0. then begin
            let computed_padding =
              W.CssStyleDeclaration.getPropertyValue "padding-right"
                (W.Window.getComputedStyle body window)
              |> parse_float
            in
            W.CssStyleDeclaration.setProperty "padding-right"
              (Printf.sprintf "%.3fpx" (computed_padding +. scrollbar_width))
              "" (inline_style body)
          end;
          W.CssStyleDeclaration.setProperty "overflow" "hidden" ""
            (inline_style root);
          W.CssStyleDeclaration.setProperty "overflow" "hidden" ""
            (inline_style body);
          let ios = touch_ios window in
          let update_viewport () =
            let viewport = visual_viewport window in
            let height, top, left =
              match viewport with
              | Some viewport when viewport_scale viewport = 1. ->
                  viewport_height viewport, viewport_top viewport,
                  viewport_left viewport
              | _ -> window_inner_height window, 0., 0.
            in
            let root_style = inline_style root in
            W.CssStyleDeclaration.setProperty "--lui-visual-height"
              (Js.Float.toString height ^ "px") "" root_style;
            W.CssStyleDeclaration.setProperty "--lui-visual-top"
              (Js.Float.toString top ^ "px") "" root_style;
            W.CssStyleDeclaration.setProperty "--lui-keyboard-inset-limit"
              (if window_inner_height window -. height > 80. then "0px"
               else "100dvh") "" root_style;
            if ios then begin
              let body_style = inline_style body in
              W.CssStyleDeclaration.setProperty "position" "fixed" "important" body_style;
              W.CssStyleDeclaration.setProperty "top"
                (Js.Float.toString (-.lock.scroll_y +. floor top) ^ "px")
                "important" body_style;
              W.CssStyleDeclaration.setProperty "left"
                (Js.Float.toString (-.lock.scroll_x +. floor left) ^ "px")
                "important" body_style;
              W.CssStyleDeclaration.setProperty "right" "0" "important" body_style
            end
          in
          update_viewport ();
          (match visual_viewport window with
           | Some viewport ->
               let listener _event = update_viewport () in
               viewport_listen viewport "resize" listener;
               viewport_listen viewport "scroll" listener;
               lock.stop_viewport <- (fun () ->
                 viewport_unlisten viewport "resize" listener;
                 viewport_unlisten viewport "scroll" listener)
           | None -> ());
          locks := lock :: !locks
      | _ -> ())

let release_scroll_lock document =
  match find_lock document !locks with
  | None -> ()
  | Some lock ->
      lock.owners <- lock.owners - 1;
      if lock.owners <= 0 then begin
        lock.stop_viewport ();
        restore_style lock.root lock.root_styles;
        restore_style lock.body lock.body_styles;
        W.CssStyleDeclaration.setProperty "scroll-behavior" "auto" "important"
          (inline_style lock.root);
        W.Window.scrollTo lock.scroll_x lock.scroll_y lock.window;
        restore_style lock.root lock.root_styles;
        locks :=
          List.filter
            (fun other ->
              not
                (W.Node.isSameNode (W.Element.asNode other.root)
                   (W.Element.asNode lock.root)))
            !locks
      end

let create () =
  { layers = Hashtbl.create 16;
    next_order = 0;
    key_listener = None;
    pointer_listener = None;
    focus_listener = None;
    listeners_installed = false;
    scroll_lock_held = false;
    is_descendant = None;
    down_target = None;
    target_listeners = [] }

let layer_at registry id = Hashtbl.find_opt registry.layers id

let down_target registry = registry.down_target

let layer_contains layer element =
  W.Element.contains (W.Element.asNode element) layer.content
  || List.exists
       (fun target -> W.Element.contains (W.Element.asNode element) target)
       layer.style_targets
  || match layer.trigger with
     | Some trigger ->
         W.Element.contains (W.Element.asNode element) trigger
     | None -> false

let owner_contains is_descendant parent child =
  match child.owner with
  | Some owner -> owner = parent.id || is_descendant parent.id owner
  | None -> false

let owned_target registry is_descendant layer target =
  layer_contains layer target
  || Hashtbl.fold
       (fun _ other found ->
         found
         || (other.open_ && other.present
            && owner_contains is_descendant layer other
            && layer_contains other target))
       registry.layers false

let owns_target registry id target =
  match layer_at registry id, registry.is_descendant with
  | Some layer, Some is_descendant ->
      owned_target registry is_descendant layer target
  | _ -> false

let sorted_open_layers registry =
  Hashtbl.fold
    (fun _ layer result ->
      if layer.open_ && layer.present then layer :: result else result)
    registry.layers []
  |> List.sort (fun left right -> compare right.order left.order)

let topmost registry =
  match sorted_open_layers registry with
  | layer :: _ -> Some layer
  | [] -> None

let topmost_blocking registry =
  List.find_opt
    (fun layer -> layer.policy = Blocking)
    (sorted_open_layers registry)

let has_blocking_present registry =
  Hashtbl.fold
    (fun _ layer result ->
      result || (layer.policy = Blocking && layer.present))
    registry.layers false

let refresh_order registry =
  List.iter
    (fun layer -> List.iter (fun target -> set_layer_style target layer.order)
       layer.style_targets)
    (sorted_open_layers registry)

let update_inert registry =
  let top = topmost_blocking registry in
  Hashtbl.iter
    (fun _ layer ->
      if layer.policy = Blocking && layer.present then
        set_layer_inert layer
          (match top with Some active -> layer.id <> active.id | None -> true))
    registry.layers

let update_scroll_lock registry document =
  let wanted = has_blocking_present registry in
  if wanted && not registry.scroll_lock_held then begin
    acquire_scroll_lock document;
    registry.scroll_lock_held <- true
  end
  else if not wanted && registry.scroll_lock_held then begin
    release_scroll_lock document;
    registry.scroll_lock_held <- false
  end

let sync_listeners registry document =
  let wanted =
    Hashtbl.fold
      (fun _ layer present -> present || layer.open_ || layer.present)
      registry.layers false
  in
  if wanted && not registry.listeners_installed then begin
    (match registry.key_listener with
     | Some listener -> W.Document.addKeyDownEventListener listener document
     | None -> ());
    (match registry.pointer_listener with
     | Some listener ->
         W.Document.addEventListener "pointerdown" listener document
     | None -> ());
    (match registry.focus_listener with
     | Some listener -> W.Document.addEventListener "focusin" listener document
     | None -> ());
    List.iter2
      (fun name listener ->
        document_listen document name listener true)
      [ "pointerdown"; "pointerup" ] registry.target_listeners;
    registry.listeners_installed <- true
  end
  else if not wanted && registry.listeners_installed then begin
    (match registry.key_listener with
     | Some listener ->
         W.Document.removeKeyDownEventListener listener document
     | None -> ());
    (match registry.pointer_listener with
     | Some listener ->
         W.Document.removeEventListener "pointerdown" listener document
     | None -> ());
    (match registry.focus_listener with
     | Some listener ->
         W.Document.removeEventListener "focusin" listener document
     | None -> ());
    List.iter2
      (fun name listener ->
        document_unlisten document name listener true)
      [ "pointerdown"; "pointerup" ] registry.target_listeners;
    registry.listeners_installed <- false
  end

let refresh registry document =
  sync_listeners registry document;
  refresh_order registry;
  update_inert registry;
  update_scroll_lock registry document

let dispatch_key registry (event : Dom.keyboardEvent) =
  if
    W.KeyboardEvent.defaultPrevented event
    || W.KeyboardEvent.isComposing event
  then ()
  else
    match topmost registry with
    | None -> ()
    | Some layer ->
        let key = W.KeyboardEvent.key event in
        if key = "Escape" then
          W.KeyboardEvent.stopImmediatePropagation event;
        layer.key_handler event;
        if key = "Escape" && not (W.KeyboardEvent.defaultPrevented event) then
          begin
          W.KeyboardEvent.preventDefault event;
          layer.dismiss ()
        end
        else if key = "Tab" && not (W.KeyboardEvent.defaultPrevented event) then
          match topmost_blocking registry with
          | Some modal when modal.id <> layer.id -> modal.key_handler event
          | _ -> ()

let dispatch_pointer registry is_descendant event_target_to_element
    (event : Dom.event) =
  let target = event_target_to_element (W.Event.target event) in
  match topmost registry with
  | None -> ()
  | Some layer ->
      if not (owned_target registry is_descendant layer target) then
        layer.dismiss ()

let focus_layer_content layer =
  W.HtmlElement.focusPreventScroll
    (W.Element.unsafeAsHtmlElement layer.content)

let dispatch_focus registry is_descendant event_target_to_element
    (event : Dom.event) =
  let target = event_target_to_element (W.Event.target event) in
  let dismiss_layers =
    List.filter
      (fun layer ->
        layer.policy = Nonblocking
        && not (owned_target registry is_descendant layer target))
      (sorted_open_layers registry)
  in
  List.iter (fun layer -> layer.dismiss ()) dismiss_layers;
  match topmost_blocking registry with
  | Some layer
    when not (owned_target registry is_descendant layer target) ->
      focus_layer_content layer
  | _ -> ()

let install registry _document is_descendant event_target_to_element =
  registry.is_descendant <- Some is_descendant;
  let key_listener = fun event -> dispatch_key registry event in
  let pointer_listener =
    fun event ->
      dispatch_pointer registry is_descendant event_target_to_element event
  in
  let focus_listener =
    fun event ->
      dispatch_focus registry is_descendant event_target_to_element event
  in
  registry.key_listener <- Some key_listener;
  registry.pointer_listener <- Some pointer_listener;
  registry.focus_listener <- Some focus_listener;
  registry.target_listeners <-
    [ (fun event ->
          registry.down_target <-
            Some (event_target_to_element (W.Event.target event)));
      (fun _event -> registry.down_target <- None) ]

let register registry ~document ~id ~owner ~trigger ~content ~style_targets ~policy
    ~dismiss ~close ~key_handler ~present ~open_ =
  let order = registry.next_order in
  registry.next_order <- order + 1;
  let layer =
    match layer_at registry id with
    | Some layer ->
        layer.owner <- owner;
        layer.trigger <- trigger;
        layer.content <- content;
        layer.style_targets <- style_targets;
        layer.policy <- policy;
        layer.dismiss <- dismiss;
        layer.close <- close;
        layer.key_handler <- key_handler;
        layer.open_ <- open_;
        layer.present <- present;
        layer.transition <- layer.transition + 1;
        layer.order <- order;
        layer
    | None ->
        { id;
          owner;
          trigger;
          content;
          style_targets;
          policy;
          dismiss;
          close;
          key_handler;
          open_;
          present;
          transition = 0;
          order;
          inert_snapshot = [] }
  in
  Hashtbl.replace registry.layers id layer;
  List.iter (fun target -> set_layer_style target order) style_targets;
  refresh registry document

let reconcile_owner registry document id owner =
  match layer_at registry id with
  | Some layer ->
      layer.owner <- owner;
      refresh registry document
  | None -> ()

let set_policy registry document id policy =
  match Hashtbl.find_opt registry.layers id with
  | Some layer ->
      layer.policy <- policy;
      refresh registry document
  | None -> ()

let reconcile_trigger registry document id trigger =
  match layer_at registry id with
  | Some layer ->
      layer.trigger <- trigger;
      refresh registry document
  | None -> ()

let open_layer registry document id =
  match layer_at registry id with
  | Some layer ->
      set_layer_inert layer false;
      layer.open_ <- true;
      layer.present <- true;
      layer.transition <- layer.transition + 1;
      layer.order <- registry.next_order;
      registry.next_order <- registry.next_order + 1;
      refresh registry document
  | None -> ()

let close_layer registry document id =
  match layer_at registry id with
  | Some layer ->
      if layer.open_ then begin
        layer.open_ <- false;
        layer.transition <- layer.transition + 1;
        set_layer_inert layer true;
        let is_descendant =
          match registry.is_descendant with
          | Some predicate -> predicate
          | None -> fun _ _ -> false
        in
        let descendants =
          Hashtbl.fold
            (fun _ child result ->
              if
                child.id <> id && child.open_ && child.present
                && owner_contains is_descendant layer child
              then child :: result
              else result)
            registry.layers []
        in
        List.iter
          (fun child ->
            child.open_ <- false;
            child.transition <- child.transition + 1;
            set_layer_inert child true)
          descendants;
        List.iter (fun child -> child.close ()) descendants
      end;
      refresh registry document;
      layer.transition
  | None -> 0

let is_open registry id =
  match layer_at registry id with
  | Some layer -> layer.open_
  | None -> false

let is_present registry id =
  match layer_at registry id with
  | Some layer -> layer.present
  | None -> false

let transition registry id =
  match layer_at registry id with
  | Some layer -> layer.transition
  | None -> -1

let focus_roots registry id =
  match layer_at registry id with
  | None -> []
  | Some root ->
      let descendants =
        match registry.is_descendant with
        | None -> []
        | Some is_descendant ->
            Hashtbl.fold
              (fun _ layer result ->
                if
                  layer.open_ && layer.present && layer.id <> root.id
                  && owner_contains is_descendant root layer
                then layer.content :: result
                else result)
              registry.layers []
      in
      root.content :: descendants

let finish_present registry document id token =
  match layer_at registry id with
  | Some layer when layer.transition = token && not layer.open_ ->
      layer.present <- false;
      set_layer_inert layer false;
      refresh registry document
  | _ -> ()

let remove registry document id =
  (match layer_at registry id with
   | Some layer -> set_layer_inert layer false
   | None -> ());
  Hashtbl.remove registry.layers id;
  refresh registry document
