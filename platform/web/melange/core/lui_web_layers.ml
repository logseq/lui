module W = Webapi.Dom

external window_inner_width : W.Window.t -> float = "innerWidth" [@@mel.get]
external parse_float : string -> float = "parseFloat" [@@mel]
external element_style : Dom.element -> W.CssStyleDeclaration.t = "style"
  [@@mel.get]

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
  mutable owners : int;
}

type t = {
  layers : (int, layer) Hashtbl.t;
  mutable next_order : int;
  mutable key_listener : (Dom.keyboardEvent -> unit) option;
  mutable pointer_listener : (Dom.event -> unit) option;
  mutable scroll_lock_held : bool;
  mutable is_descendant : (int -> int -> bool) option;
}

let style_properties =
  [ "overflow"; "overflow-x"; "overflow-y"; "padding-right"; "position";
    "top"; "left"; "right"; "width" ]

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
          locks := lock :: !locks
      | _ -> ())

let release_scroll_lock document =
  match find_lock document !locks with
  | None -> ()
  | Some lock ->
      lock.owners <- lock.owners - 1;
      if lock.owners <= 0 then begin
        restore_style lock.root lock.root_styles;
        restore_style lock.body lock.body_styles;
        W.Window.scrollTo lock.scroll_x lock.scroll_y lock.window;
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
    scroll_lock_held = false;
    is_descendant = None }

let layer_at registry id = Hashtbl.find_opt registry.layers id

let layer_contains layer element =
  W.Element.contains (W.Element.asNode layer.content) element
  || List.exists
       (fun target -> W.Element.contains (W.Element.asNode target) element)
       layer.style_targets
  || match layer.trigger with
     | Some trigger ->
         W.Element.contains (W.Element.asNode trigger) element
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

let refresh registry document =
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

let install registry document is_descendant event_target_to_element =
  registry.is_descendant <- Some is_descendant;
  let key_listener = fun event -> dispatch_key registry event in
  let pointer_listener =
    fun event ->
      dispatch_pointer registry is_descendant event_target_to_element event
  in
  registry.key_listener <- Some key_listener;
  registry.pointer_listener <- Some pointer_listener;
  W.Document.addKeyDownEventListener key_listener document;
  W.Document.addEventListener "pointerdown" pointer_listener
    document

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
