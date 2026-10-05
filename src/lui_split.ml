(* Bonsplit-style tabbed split panes as LUI extension components.

   The application owns the split tree as ordinary data; each platform
   backend renders it natively and owns gesture-time visuals (tab drag
   tracking, drop indicators, divider feedback, animations) while reporting
   semantic events back so the app can patch the tree.

   Tree shape:
     split_view
       split_branch ~orientation ~ratio [ left; right ]
         split_pane ~pane_id [ split_tab ~tab_id ~title [content]; ... ]
   A bare split_pane may be mounted directly under split_view for a
   single-pane surface.

   Identity is app-assigned: [~pane_id] and [~tab_id] are stable strings the
   app uses to track selection and resolve events. *)

open Lui_protocol

let profiles =
  [
    { profile_os = MacOS; profile_host = SwiftUIHost };
    { profile_os = IOS; profile_host = SwiftUIHost };
    { profile_os = LinuxOS; profile_host = QMLHost };
    { profile_os = MacOS; profile_host = QMLHost };
    { profile_os = WindowsOS; profile_host = QMLHost };
    { profile_os = AndroidOS; profile_host = FlutterHost };
    { profile_os = IOS; profile_host = FlutterHost };
    { profile_os = LinuxOS; profile_host = FlutterHost };
    { profile_os = MacOS; profile_host = FlutterHost };
    { profile_os = WindowsOS; profile_host = FlutterHost };
    { profile_os = WindowsOS; profile_host = WinUIHost };
    { profile_os = MacOS; profile_host = GPUIHost };
    { profile_os = LinuxOS; profile_host = GPUIHost };
    { profile_os = WindowsOS; profile_host = GPUIHost };
    { profile_os = WebOS; profile_host = WebHost };
  ]

let accessibility_identifier_property =
  Lui_extension.property "accessibility-identifier" Lui_extension.StringScalar
    false None

let split_view_schema =
  Lui_extension.component "split-view" profiles false
    [ "split-branch"; "split-pane" ]
    [
      Lui_extension.property "divider-thickness" Lui_extension.FloatScalar
        false None;
      Lui_extension.property "animation" Lui_extension.BoolScalar false None;
      accessibility_identifier_property;
    ]
    []

let split_branch_schema =
  Lui_extension.component "split-branch" profiles false
    [ "split-branch"; "split-pane" ]
    [
      Lui_extension.property "orientation" Lui_extension.StringScalar true
        None;
      Lui_extension.property "ratio" Lui_extension.FloatScalar true None;
    ]
    [
      Lui_extension.event "ratio-changed"
        [ Lui_extension.event_field "ratio" Lui_extension.FloatScalar true ];
    ]

let split_pane_schema =
  Lui_extension.component "split-pane" profiles false [ "split-tab" ]
    [
      Lui_extension.property "pane-id" Lui_extension.StringScalar true None;
      Lui_extension.property "selected" Lui_extension.StringScalar false None;
      Lui_extension.property "focused" Lui_extension.BoolScalar false None;
      accessibility_identifier_property;
    ]
    [
      Lui_extension.event "tab-selected"
        [ Lui_extension.event_field "tab" Lui_extension.StringScalar true ];
      Lui_extension.event "tab-closed"
        [ Lui_extension.event_field "tab" Lui_extension.StringScalar true ];
      Lui_extension.event "tab-moved"
        [
          Lui_extension.event_field "tab" Lui_extension.StringScalar true;
          Lui_extension.event_field "index" Lui_extension.IntScalar true;
          Lui_extension.event_field "from-pane" Lui_extension.StringScalar true;
        ];
      Lui_extension.event "pane-focused" [];
      Lui_extension.event "navigate"
        [
          Lui_extension.event_field "direction" Lui_extension.StringScalar true;
        ];
      Lui_extension.event "split-requested"
        [
          Lui_extension.event_field "orientation" Lui_extension.StringScalar
            true;
        ];
      Lui_extension.event "split-drop"
        [
          Lui_extension.event_field "tab" Lui_extension.StringScalar true;
          Lui_extension.event_field "from-pane" Lui_extension.StringScalar true;
          Lui_extension.event_field "edge" Lui_extension.StringScalar true;
        ];
      Lui_extension.event "pane-closed" [];
    ]

let split_tab_schema =
  Lui_extension.component "split-tab" profiles true []
    [
      Lui_extension.property "tab-id" Lui_extension.StringScalar true None;
      Lui_extension.property "title" Lui_extension.StringScalar true None;
      Lui_extension.property "icon" Lui_extension.StringScalar false None;
      Lui_extension.property "dirty" Lui_extension.BoolScalar false None;
      Lui_extension.property "closable" Lui_extension.BoolScalar false None;
      accessibility_identifier_property;
    ]
    []

let register_into registry =
  Lui_extension.register_component registry split_view_schema;
  Lui_extension.register_component registry split_branch_schema;
  Lui_extension.register_component registry split_pane_schema;
  Lui_extension.register_component registry split_tab_schema

let registry () =
  let registry = Lui_extension.registry () in
  register_into registry;
  Lui_extension.freeze registry;
  registry

type split_branch_ratio_changed = {
  event_node : int;
  ratio : float;
}

type split_pane_tab_selected = {
  event_node : int;
  tab : string;
}

type split_pane_tab_closed = {
  event_node : int;
  tab : string;
}

type split_pane_tab_moved = {
  event_node : int;
  tab : string;
  index : int;
  from_pane : string;
}

type split_pane_focused = { event_node : int }

type split_pane_navigate = {
  event_node : int;
  direction : string;
}

type split_pane_split_requested = {
  event_node : int;
  orientation : string;
}

type split_pane_split_drop = {
  event_node : int;
  tab : string;
  from_pane : string;
  edge : string;
}

type split_pane_pane_closed = { event_node : int }

let decode_split_branch_ratio_changed = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "ratio-changed"
         && String.equal identifier "split-branch" -> (
      match String_map.find_opt "ratio" values with
      | Some (FloatValue ratio) -> Some { event_node = node; ratio }
      | _ -> None)
  | _ -> None

let decode_split_pane_tab_selected = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "tab-selected"
         && String.equal identifier "split-pane" -> (
      match String_map.find_opt "tab" values with
      | Some (StringValue tab) ->
        Some ({ event_node = node; tab } : split_pane_tab_selected)
      | _ -> None)
  | _ -> None

let decode_split_pane_tab_closed = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "tab-closed"
         && String.equal identifier "split-pane" -> (
      match String_map.find_opt "tab" values with
      | Some (StringValue tab) ->
        Some ({ event_node = node; tab } : split_pane_tab_closed)
      | _ -> None)
  | _ -> None

let decode_split_pane_tab_moved = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "tab-moved"
         && String.equal identifier "split-pane" -> (
      match
        ( String_map.find_opt "tab" values,
          String_map.find_opt "index" values,
          String_map.find_opt "from-pane" values )
      with
      | Some (StringValue tab), Some (IntValue index), Some (StringValue from_pane)
        ->
        Some { event_node = node; tab; index; from_pane }
      | _ -> None)
  | _ -> None

let decode_split_pane_pane_focused = function
  | ExtensionEvent (node, identifier, event_name, _values)
    when String.equal event_name "pane-focused"
         && String.equal identifier "split-pane" ->
    Some ({ event_node = node } : split_pane_focused)
  | _ -> None

let decode_split_pane_navigate = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "navigate"
         && String.equal identifier "split-pane" -> (
      match String_map.find_opt "direction" values with
      | Some (StringValue direction) ->
        Some { event_node = node; direction }
      | _ -> None)
  | _ -> None

let decode_split_pane_split_requested = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "split-requested"
         && String.equal identifier "split-pane" -> (
      match String_map.find_opt "orientation" values with
      | Some (StringValue orientation) ->
        Some { event_node = node; orientation }
      | _ -> None)
  | _ -> None

let decode_split_pane_split_drop = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name "split-drop"
         && String.equal identifier "split-pane" -> (
      match
        ( String_map.find_opt "tab" values,
          String_map.find_opt "from-pane" values,
          String_map.find_opt "edge" values )
      with
      | Some (StringValue tab), Some (StringValue from_pane),
        Some (StringValue edge) ->
        Some { event_node = node; tab; from_pane; edge }
      | _ -> None)
  | _ -> None

let decode_split_pane_pane_closed = function
  | ExtensionEvent (node, identifier, event_name, _values)
    when String.equal event_name "pane-closed"
         && String.equal identifier "split-pane" ->
    Some ({ event_node = node } : split_pane_pane_closed)
  | _ -> None

let on_event context node decode handler =
  Lui_ui.on_event context node (fun raw ->
      match decode raw with
      | Some event -> handler event
      | None -> ())

let split_view ?key ?divider_thickness ?divider_thickness_signal ?animation
    ?animation_signal ?accessibility_identifier
    ?accessibility_identifier_signal (children : Lui_elements.t list) :
    Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context "split-view" in
  Option.iter (Lui_ui.key context node) key;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "divider-thickness"
        (FloatValue value))
    divider_thickness;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "divider-thickness"
        (Signal.map (fun value -> FloatValue value) signal))
    divider_thickness_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "animation" (BoolValue value))
    animation;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "animation"
        (Signal.map (fun value -> BoolValue value) signal))
    animation_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "accessibility-identifier"
        (StringValue value))
    accessibility_identifier;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "accessibility-identifier"
        (Signal.map (fun value -> StringValue value) signal))
    accessibility_identifier_signal;
  Lui_elements.attach context parent node;
  Lui_elements.mount_children context node children;
  node

let split_branch ?key ~orientation ~ratio ?ratio_signal ?on_ratio_changed
    (children : Lui_elements.t list) : Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context "split-branch" in
  Option.iter (Lui_ui.key context node) key;
  Lui_ui.extension_property context node "orientation"
    (StringValue
       (match orientation with
       | `horizontal -> "horizontal"
       | `vertical -> "vertical"));
  Lui_ui.extension_property context node "ratio" (FloatValue ratio);
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "ratio"
        (Signal.map (fun value -> FloatValue value) signal))
    ratio_signal;
  Option.iter
    (on_event context node decode_split_branch_ratio_changed)
    on_ratio_changed;
  Lui_elements.attach context parent node;
  Lui_elements.mount_children context node children;
  node

let split_pane ?key ~pane_id ?selected ?selected_signal ?focused
    ?focused_signal ?accessibility_identifier ?on_tab_selected ?on_tab_closed
    ?on_tab_moved ?on_pane_focused ?on_navigate ?on_split_requested
    ?on_split_drop ?on_pane_closed (children : Lui_elements.t list) :
    Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context "split-pane" in
  Option.iter (Lui_ui.key context node) key;
  Lui_ui.extension_property context node "pane-id" (StringValue pane_id);
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "selected" (StringValue value))
    selected;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "selected"
        (Signal.map (fun value -> StringValue value) signal))
    selected_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "focused" (BoolValue value))
    focused;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "focused"
        (Signal.map (fun value -> BoolValue value) signal))
    focused_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "accessibility-identifier"
        (StringValue value))
    accessibility_identifier;
  Option.iter
    (on_event context node decode_split_pane_tab_selected)
    on_tab_selected;
  Option.iter
    (on_event context node decode_split_pane_tab_closed)
    on_tab_closed;
  Option.iter
    (on_event context node decode_split_pane_tab_moved)
    on_tab_moved;
  Option.iter
    (on_event context node decode_split_pane_pane_focused)
    on_pane_focused;
  Option.iter (on_event context node decode_split_pane_navigate) on_navigate;
  Option.iter
    (on_event context node decode_split_pane_split_requested)
    on_split_requested;
  Option.iter
    (on_event context node decode_split_pane_split_drop)
    on_split_drop;
  Option.iter
    (on_event context node decode_split_pane_pane_closed)
    on_pane_closed;
  Lui_elements.attach context parent node;
  Lui_elements.mount_children context node children;
  node

let split_tab ?key ~tab_id ~title ?title_signal ?icon ?icon_signal ?dirty
    ?dirty_signal ?closable ?accessibility_identifier
    (children : Lui_elements.t list) : Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context "split-tab" in
  Option.iter (Lui_ui.key context node) key;
  Lui_ui.extension_property context node "tab-id" (StringValue tab_id);
  Lui_ui.extension_property context node "title" (StringValue title);
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "title"
        (Signal.map (fun value -> StringValue value) signal))
    title_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "icon" (StringValue value))
    icon;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "icon"
        (Signal.map (fun value -> StringValue value) signal))
    icon_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "dirty" (BoolValue value))
    dirty;
  Option.iter
    (fun signal ->
      Lui_ui.extension_property_signal context node "dirty"
        (Signal.map (fun value -> BoolValue value) signal))
    dirty_signal;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "closable" (BoolValue value))
    closable;
  Option.iter
    (fun value ->
      Lui_ui.extension_property context node "accessibility-identifier"
        (StringValue value))
    accessibility_identifier;
  Lui_elements.attach context parent node;
  Lui_elements.mount_children context node children;
  node

(* The shared controller: owns the split tree as data, applies pointer/keyboard
   events to it, and renders it back into extension nodes. Platform backends
   emit events; [Model] is the policy — identical behavior on every host. *)
module Model = struct
  type direction =
    [ `left
    | `right
    | `up
    | `down
    ]

  type orientation =
    [ `horizontal
    | `vertical
    ]

  (* Drop edges are physical sides of a pane; navigation directions differ. *)
  type edge =
    [ `left
    | `right
    | `top
    | `bottom
    ]

  type tab = {
    tab_id : string;
    tab_title : string;
    tab_icon : string option;
    tab_dirty : bool;
    tab_closable : bool;
  }

  let tab ?icon ?(dirty = false) ?(closable = true) ~tab_id ~title () =
    {
      tab_id;
      tab_title = title;
      tab_icon = icon;
      tab_dirty = dirty;
      tab_closable = closable;
    }

  type pane = {
    pane_id : string;
    pane_tabs : tab list;
    pane_selected : string option;
  }

  let pane ?selected ~pane_id tabs = { pane_id; pane_tabs = tabs; pane_selected = selected }

  type node =
    | Leaf of pane
    | Split of {
        split_id : string;
        split_orientation : orientation;
        split_ratio : float;
        split_first : node;
        split_second : node;
      }

  type t = {
    root : node;
    focused : string option;
    next_id : int;
  }

  let create ?focused root =
    { root; focused; next_id = 0 }

  let root state = state.root

  let focused state = state.focused

  let fresh_id state prefix =
    let id = Printf.sprintf "%s-%d" prefix state.next_id in
    (id, { state with next_id = state.next_id + 1 })

  type action =
    | Select_tab of string * string
    | Close_tab of string * string
    | Move_tab of {
        move_tab : string;
        move_from : string;
        move_to : string;
        move_index : int;
      }
    | Split_drop of {
        drop_tab : string;
        drop_from : string;
        drop_target : string;
        drop_edge : edge;
      }
    | Close_pane of string
    | Focus_pane of string
    | Navigate of string * direction
    | Request_split of string * orientation
    | Set_ratio of string * float

  let pane_selected_id p =
    match p.pane_selected with
    | Some id when List.exists (fun t -> String.equal t.tab_id id) p.pane_tabs ->
      id
    | _ -> (
        match p.pane_tabs with
        | first :: _ -> first.tab_id
        | [] -> "")

  let rec map_panes f = function
    | Leaf p -> f p
    | Split s ->
      Split
        {
          s with
          split_first = map_panes f s.split_first;
          split_second = map_panes f s.split_second;
        }

  let find_pane pane_id node =
    let found = ref None in
    ignore
      (map_panes
         (fun p ->
           if String.equal p.pane_id pane_id then found := Some p;
           Leaf p)
         node);
    !found

  (* Remove a pane and collapse a split whose child vanished. [`Removed] at
     the root means the last pane was closed; callers decide whether to keep
     an empty root pane or leave the state untouched. *)
  let rec remove_pane pane_id = function
    | Leaf p when String.equal p.pane_id pane_id -> `Removed p
    | Leaf p -> `Keep (Leaf p)
    | Split s -> (
        match
          (remove_pane pane_id s.split_first, remove_pane pane_id s.split_second)
        with
        | `Removed _, `Keep keep -> `Keep keep
        | `Keep keep, `Removed _ -> `Keep keep
        | `Keep first, `Keep second ->
          `Keep (Split { s with split_first = first; split_second = second })
        | `Removed a, `Removed _ -> `Removed a)

  let replace_pane pane_id f node =
    map_panes
      (fun p -> if String.equal p.pane_id pane_id then f p else Leaf p)
      node

  let detach_tab pane_id tab_id node =
    let taken = ref None in
    let node' =
      map_panes
        (fun p ->
          if String.equal p.pane_id pane_id then
            let remaining =
              List.filter
                (fun t ->
                  if String.equal t.tab_id tab_id then begin
                    taken := Some t;
                    false
                  end
                  else true)
                p.pane_tabs
            in
            Leaf
              {
                p with
                pane_tabs = remaining;
                pane_selected =
                  (match p.pane_selected with
                  | Some s when String.equal s tab_id -> None
                  | other -> other);
              }
          else Leaf p)
        node
    in
    (!taken, node')

  (* Drop a pane left empty by a move/detach; the root's last pane stays. *)
  let prune pane_id node =
    match find_pane pane_id node with
    | Some { pane_tabs = []; _ } -> (
        match remove_pane pane_id node with
        | `Removed last -> Leaf { last with pane_tabs = [] }
        | `Keep pruned -> pruned)
    | _ -> node

  let clamp_ratio v = Float.max 0.0 (Float.min 1.0 v)

  let insert_tab pane_id tab index node =
    replace_pane pane_id
      (fun p ->
        let index =
          if index < 0 then 0
          else if index > List.length p.pane_tabs then List.length p.pane_tabs
          else index
        in
        let rec split_at n items =
          if n <= 0 then ([], items)
          else
            match items with
            | x :: rest ->
              let prefix, suffix = split_at (n - 1) rest in
              (x :: prefix, suffix)
            | [] -> ([], [])
        in
        let prefix, suffix = split_at index p.pane_tabs in
        Leaf
          {
            p with
            pane_tabs = prefix @ tab :: suffix;
            pane_selected = Some tab.tab_id;
          })
      node

  let edge_orientation = function
    | `left | `right -> `horizontal
    | `top | `bottom -> `vertical

  let edge_is_first = function
    | `left | `top -> true
    | `right | `bottom -> false

  let direction_of_string = function
    | "left" -> Some `left
    | "right" -> Some `right
    | "up" -> Some `up
    | "down" -> Some `down
    | _ -> None

  let edge_of_string = function
    | "left" -> Some `left
    | "right" -> Some `right
    | "top" -> Some `top
    | "bottom" -> Some `bottom
    | _ -> None

  let orientation_of_string = function
    | "horizontal" -> `horizontal
    | _ -> `vertical

  (* Pane ancestry, innermost split first. *)
  let ancestry pane_id root =
    let rec go acc = function
      | Leaf p -> if String.equal p.pane_id pane_id then Some acc else None
      | Split s -> (
          match
            go
              ((`first, s.split_orientation, s.split_first, s.split_second)
               :: acc)
              s.split_first
          with
          | Some _ as hit -> hit
          | None ->
            go
              ((`second, s.split_orientation, s.split_first, s.split_second)
               :: acc)
              s.split_second)
    in
    go [] root

  let nearest_leaf side node =
    let rec descend = function
      | Leaf p -> p.pane_id
      | Split s -> (
          match side with
          | `first -> descend s.split_first
          | `second -> descend s.split_second)
    in
    descend node

  let navigate pane_id direction state =
    let axis : orientation =
      match direction with
      | `left | `right -> `horizontal
      | `up | `down -> `vertical
    in
    match ancestry pane_id state.root with
    | None | Some [] -> state
    | Some path ->
      let rec climb = function
        | [] -> None
        | (side, orientation, first, second) :: rest ->
          if orientation = axis then
            match direction, side with
            | `left, `second | `up, `second ->
              Some (nearest_leaf `second first)
            | `right, `first | `down, `first ->
              Some (nearest_leaf `first second)
            | _ -> climb rest
          else climb rest
      in
      (match climb path with
      | Some target -> { state with focused = Some target }
      | None -> state)

  let update state action =
    match action with
    | Select_tab (pane_id, tab_id) ->
      {
        state with
        root =
          replace_pane pane_id
            (fun p ->
              if List.exists (fun t -> String.equal t.tab_id tab_id) p.pane_tabs
              then Leaf { p with pane_selected = Some tab_id }
              else Leaf p)
            state.root;
        focused = Some pane_id;
      }
    | Focus_pane pane_id -> { state with focused = Some pane_id }
    | Set_ratio (split_id, ratio) ->
      let rec apply = function
        | Leaf p -> Leaf p
        | Split s ->
          if String.equal s.split_id split_id then
            Split
              { s with split_ratio = clamp_ratio ratio }
          else
            Split
              {
                s with
                split_first = apply s.split_first;
                split_second = apply s.split_second;
              }
      in
      { state with root = apply state.root }
    | Close_tab (pane_id, tab_id) -> (
        let closable =
          match find_pane pane_id state.root with
          | Some pane ->
            (match
               List.find_opt
                 (fun (t : tab) -> String.equal t.tab_id tab_id)
                 pane.pane_tabs
             with
            | Some t -> t.tab_closable
            | None -> false)
          | None -> false
        in
        if not closable then state
        else
          let _, root = detach_tab pane_id tab_id state.root in
          let root = prune pane_id root in
          let state = { state with root } in
          (match state.focused with
          | Some f when Option.is_none (find_pane f state.root) ->
            { state with focused = None }
          | _ -> state))
    | Close_pane pane_id -> (
        match remove_pane pane_id state.root with
        | `Removed last ->
          (* The last pane cannot close — keep it, emptied of tabs. *)
          {
            state with
            root = Leaf { last with pane_tabs = [] };
            focused = Some pane_id;
          }
        | `Keep root ->
          let state = { state with root } in
          (match state.focused with
          | Some f when Option.is_none (find_pane f state.root) ->
            { state with focused = None }
          | _ -> state))
    | Move_tab { move_tab; move_from; move_to; move_index } -> (
        match find_pane move_to state.root with
        | None -> state
        | Some _ ->
          if String.equal move_from move_to then
        match find_pane move_from state.root with
        | None -> state
        | Some source ->
          let from_index =
            List.find_index
              (fun t -> String.equal t.tab_id move_tab)
              source.pane_tabs
          in
          (match from_index with
          | None -> state
          | Some from_index ->
            let index =
              if move_index > from_index then move_index - 1 else move_index
            in
            let tab, root = detach_tab move_from move_tab state.root in
            (match tab with
            | None -> state
            | Some tab ->
              { state with root = insert_tab move_to tab index root }))
          else (
        let tab, root = detach_tab move_from move_tab state.root in
        match tab with
        | None -> state
        | Some tab ->
          let root = prune move_from root in
          { state with root = insert_tab move_to tab move_index root }))
    | Split_drop { drop_tab; drop_from; drop_target; drop_edge } -> (
        match find_pane drop_from state.root with
        | None -> state
        | Some source
          when String.equal drop_from drop_target
               && List.length source.pane_tabs <= 1 ->
          (* Splitting a pane by dragging its only tab onto itself is a no-op. *)
          state
        | Some _ -> (
            let tab, root = detach_tab drop_from drop_tab state.root in
            match tab with
            | None -> state
            | Some tab ->
              let root = prune drop_from root in
              let new_pane_id, state = fresh_id state "pane" in
              let new_pane =
                Leaf
                  {
                    pane_id = new_pane_id;
                    pane_tabs = [ tab ];
                    pane_selected = Some tab.tab_id;
                  }
              in
              let split_id, state = fresh_id state "split" in
              let orientation = edge_orientation drop_edge in
              let first_is_new = edge_is_first drop_edge in
              (* The dropped edge gets the smaller share, like Bonsplit's
                 edgeRatio. *)
              let ratio = if first_is_new then 0.25 else 0.75 in
              let root =
                replace_pane drop_target
                  (fun p ->
                    Split
                      {
                        split_id;
                        split_orientation = orientation;
                        split_ratio = ratio;
                        split_first =
                          (if first_is_new then new_pane else Leaf p);
                        split_second =
                          (if first_is_new then Leaf p else new_pane);
                      })
                  root
              in
              { state with root; focused = Some new_pane_id }))
    | Request_split (pane_id, orientation) -> (
        let split_id, state = fresh_id state "split" in
        let new_pane_id, state = fresh_id state "pane" in
        match find_pane pane_id state.root with
        | None -> state
        | Some _ ->
          let root =
            replace_pane pane_id
              (fun p ->
                Split
                  {
                    split_id;
                    split_orientation = orientation;
                    split_ratio = 0.5;
                    split_first = Leaf p;
                    split_second =
                      Leaf
                        {
                          pane_id = new_pane_id;
                          pane_tabs = [];
                          pane_selected = None;
                        };
                  })
              state.root
          in
          { state with root; focused = Some new_pane_id })
    | Navigate (pane_id, direction) -> navigate pane_id direction state

  (* Decode a backend event into an action, tagging it with the pane/branch
     identity the caller knows at mount time. *)
  let pane_action pane_id raw =
    match raw with
    | ExtensionEvent (_node, identifier, name, _values)
      when String.equal identifier "split-pane" -> (
        match name with
        | "tab-selected" ->
          Option.map
            (fun (e : split_pane_tab_selected) -> Select_tab (pane_id, e.tab))
            (decode_split_pane_tab_selected raw)
        | "tab-closed" ->
          Option.map
            (fun (e : split_pane_tab_closed) -> Close_tab (pane_id, e.tab))
            (decode_split_pane_tab_closed raw)
        | "tab-moved" ->
          Option.map
            (fun (e : split_pane_tab_moved) ->
               Move_tab
                 {
                   move_tab = e.tab;
                   move_from = e.from_pane;
                   move_to = pane_id;
                   move_index = e.index;
                 })
            (decode_split_pane_tab_moved raw)
        | "pane-focused" -> Some (Focus_pane pane_id)
        | "navigate" ->
          Option.bind
            (decode_split_pane_navigate raw)
            (fun (e : split_pane_navigate) ->
               Option.map
                 (fun direction -> Navigate (pane_id, direction))
                 (direction_of_string e.direction))
        | "split-requested" ->
          Option.map
            (fun (e : split_pane_split_requested) ->
               Request_split (pane_id, orientation_of_string e.orientation))
            (decode_split_pane_split_requested raw)
        | "split-drop" ->
          Option.bind
            (decode_split_pane_split_drop raw)
            (fun (e : split_pane_split_drop) ->
               Option.map
                 (fun edge ->
                    Split_drop
                      {
                        drop_tab = e.tab;
                        drop_from = e.from_pane;
                        drop_target = pane_id;
                        drop_edge = edge;
                      })
                 (edge_of_string e.edge))
        | "pane-closed" -> Some (Close_pane pane_id)
        | _ -> None)
    | _ -> None

  (* Render the tree. [build] supplies each tab's content children; [dispatch]
     receives decoded actions — feed them to your model's update, then back
     through [update]. *)
  let render ?key ?divider_thickness ?animation ~build ~dispatch state :
      Lui_elements.t =
    let with_handler element handle context parent =
      let node = element context parent in
      Lui_ui.on_event context node handle;
      node
    in
    let render_node node =
      let rec go = function
        | Leaf p ->
          with_handler
            (split_pane ~pane_id:p.pane_id ~selected:(pane_selected_id p)
               ~focused:
                 (match state.focused with
                 | Some f -> String.equal f p.pane_id
                 | None -> false)
               (List.map
                  (fun t ->
                     split_tab ~tab_id:t.tab_id ~title:t.tab_title
                       ?icon:t.tab_icon ~dirty:t.tab_dirty
                       ~closable:t.tab_closable (build t))
                  p.pane_tabs))
            (fun raw ->
              match pane_action p.pane_id raw with
              | Some action -> dispatch action
              | None -> ())
        | Split s ->
          with_handler
            (split_branch ~orientation:s.split_orientation
               ~ratio:s.split_ratio
               [ go s.split_first; go s.split_second ])
            (fun raw ->
              match decode_split_branch_ratio_changed raw with
              | Some event -> dispatch (Set_ratio (s.split_id, event.ratio))
              | None -> ())
      in
      go node
    in
    split_view ?key ?divider_thickness ?animation [ render_node state.root ]
end
