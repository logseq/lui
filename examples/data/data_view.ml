module Edn = Melange_edn
module P = Lui_protocol
module U = Lui_ui
module S = Lui_wire_schema

type expression = Literal of Edn.any | Binding of Edn.any list
type target = Standard of P.node_kind | Extension of string
type property = Standard_property of P.property | Extension_property of string

type action = {
  event_name : string;
  action_name : string;
  arguments : expression list;
}

type node =
  | Element of target * (property * expression) list * action list * node list
  | When of expression * node
  | Each of expression * string * Edn.any list * node
  | Component of (string * expression) list * node

type t = node

exception Invalid_view of string

let fail message = raise (Invalid_view message)
let keyword name = Edn.any (Edn.keyword name)

let name (Edn.Any value) =
  match value with
  | Edn.Keyword name -> Edn.keyword_to_string name
  | _ -> fail "expected a keyword"

let vector (Edn.Any value) =
  match value with
  | Edn.Vector items -> Array.to_list items
  | _ -> fail "expected a vector"

let fields (Edn.Any value) =
  match value with
  | Edn.Map entries ->
      let seen = Hashtbl.create (Array.length entries) in
      Array.to_list
        (Array.map
           (fun (key, value) ->
             let key = name key in
             if Hashtbl.mem seen key then fail ("duplicate key: " ^ key);
             Hashtbl.add seen key ();
             (key, value))
           entries)
  | _ -> fail "expected a map"

let required key entries =
  match List.assoc_opt key entries with
  | Some value -> value
  | None -> fail ("missing :" ^ key)

let only allowed entries =
  List.iter
    (fun (key, _) ->
      if not (List.mem key allowed) then fail ("unknown field :" ^ key))
    entries

let expression (Edn.Any value as data) =
  match value with
  | Edn.Map _ ->
      let entries = fields data in
      only [ "bind" ] entries;
      let path = vector (required "bind" entries) in
      if path = [] then fail "binding path must include a scope";
      Binding path
  | _ -> Literal data

let rec lookup data = function
  | [] -> data
  | key :: rest ->
      let next =
        match (data, key) with
        | Edn.Any (Edn.Map entries), _ -> (
            match
              Array.find_opt (fun (candidate, _) -> candidate = key) entries
            with
            | Some (_, value) -> value
            | None -> fail ("missing binding key " ^ Edn.to_edn_string key))
        | Edn.Any (Edn.Vector items), Edn.Any (Edn.Int index)
          when index >= 0L && index < Int64.of_int (Array.length items) ->
            items.(Int64.to_int index)
        | _ -> fail "binding path does not match model data"
      in
      lookup next rest

let evaluate environment = function
  | Literal data -> data
  | Binding [] -> fail "empty binding"
  | Binding (scope :: path) -> lookup (required (name scope) environment) path

let boolean (Edn.Any value) =
  match value with
  | Edn.Bool value -> value
  | _ -> fail "condition must be an OCaml-projected boolean"

let scalar (Edn.Any value) =
  match value with
  | Edn.String value -> Some (P.StringValue value)
  | Edn.Keyword value -> Some (P.StringValue (Edn.keyword_to_string value))
  | Edn.Bool value -> Some (P.BoolValue value)
  | Edn.Int value
    when value >= Int64.of_int min_int && value <= Int64.of_int max_int ->
      Some (P.IntValue (Int64.to_int value))
  | Edn.Float value when P.is_finite value -> Some (P.FloatValue value)
  | Edn.Nil -> None
  | _ -> fail "property requires a finite wire scalar (or nil to remove it)"

let wire property value =
  let decoded = scalar value in
  match (property, decoded) with
  | Standard_property property, Some value ->
      let value =
        match value with
        | P.IntValue number when not (P.property_value_supported property value)
          ->
            P.FloatValue (float_of_int number)
        | _ -> value
      in
      if not (P.property_value_supported property value) then
        fail ("invalid value for :" ^ S.property_name property);
      Some value
  | _ -> decoded

let pointer = { P.x = 0.; y = 0.; modifiers = 0; button = 0; target_class = "" }

let event_specs =
  [
    ("press", P.Press 0, [ P.PressEnabled; P.PointerEnabled ]);
    ("input", P.TextChanged (0, ""), [ P.PointerEnabled ]);
    ("submit", P.Submit 0, [ P.SubmitEnabled; P.PointerEnabled ]);
    ("toggle", P.ToggleChanged (0, false), [ P.ToggleEnabled; P.PointerEnabled ]);
    ("change", P.Change 0, [ P.ChangeEnabled; P.PointerEnabled ]);
    ("value", P.ValueChanged (0, 0.), [ P.PointerEnabled ]);
    ("dismiss", P.Dismiss 0, []);
    ("long-press", P.LongPress 0, [ P.LongPressEnabled; P.PointerEnabled ]);
    ("double-press", P.DoublePress 0, [ P.DoublePressEnabled; P.PointerEnabled ]);
    ("appear", P.Appear 0, [ P.AppearEnabled ]);
    ("pointer-down", P.PointerDown (0, pointer), [ P.PointerEnabled ]);
    ("pointer-up", P.PointerUp (0, pointer), [ P.PointerEnabled ]);
    ("pointer-enter", P.PointerEnter 0, [ P.PointerEnabled ]);
    ("pointer-leave", P.PointerLeave 0, [ P.PointerEnabled ]);
    ("context-menu", P.ContextMenuPress (0, pointer), [ P.PointerEnabled ]);
    ("press-detail", P.PressDetail (0, pointer), [ P.PointerEnabled ]);
    ( "press-modifiers",
      P.PressModifiers (0, 0),
      [ P.PressEnabled; P.PointerEnabled ] );
    ("load", P.Load 0, []);
    ("navigate-previous", P.NavigatePrevious 0, [ P.NavigateEnabled ]);
    ("navigate-next", P.NavigateNext 0, [ P.NavigateEnabled ]);
    ("navigation-key", P.NavigationKey (0, "", false), [ P.NavigateEnabled ]);
    ("scroll-completed", P.ScrollCompleted (0, 0, ""), []);
    ("visible-range", P.VisibleRange (0, 0, 0), [ P.TrackVisibleRange ]);
    ("picked", P.Picked (0, ""), []);
  ]

let event_name = function
  | P.Press _ -> "press"
  | P.LongPress _ -> "long-press"
  | P.TextChanged _ -> "input"
  | P.Submit _ -> "submit"
  | P.ToggleChanged _ -> "toggle"
  | P.Change _ -> "change"
  | P.ValueChanged _ -> "value"
  | P.Dismiss _ -> "dismiss"
  | P.DoublePress _ -> "double-press"
  | P.Appear _ -> "appear"
  | P.ScrollCompleted _ -> "scroll-completed"
  | P.VisibleRange _ -> "visible-range"
  | P.Picked _ -> "picked"
  | P.PressModifiers _ -> "press-modifiers"
  | P.PressDetail _ -> "press-detail"
  | P.PointerDown _ -> "pointer-down"
  | P.PointerUp _ -> "pointer-up"
  | P.PointerEnter _ -> "pointer-enter"
  | P.PointerLeave _ -> "pointer-leave"
  | P.ContextMenuPress _ -> "context-menu"
  | P.Load _ -> "load"
  | P.NavigatePrevious _ -> "navigate-previous"
  | P.NavigateNext _ -> "navigate-next"
  | P.NavigationKey _ -> "navigation-key"
  | P.ExtensionEvent (_, _, name, _) -> name

let kind_table = Hashtbl.create 128
let property_table = Hashtbl.create 256

let () =
  List.iter
    (fun kind -> Hashtbl.add kind_table (S.node_kind_name kind) kind)
    S.all_node_kinds;
  List.iter
    (fun property ->
      Hashtbl.add property_table (S.property_name property) property)
    S.all_properties

let target tag =
  if String.starts_with ~prefix:"ext/" tag then
    Extension (String.sub tag 4 (String.length tag - 4))
  else
    match Hashtbl.find_opt kind_table tag with
    | Some P.Root -> fail "root is owned by Lui_app"
    | Some kind -> Standard kind
    | None -> fail ("unknown component :" ^ tag)

let property target name =
  match target with
  | Extension _ -> Extension_property name
  | Standard kind -> (
      match Hashtbl.find_opt property_table name with
      | Some property when P.property_supported kind property ->
          Standard_property property
      | _ ->
          fail ("unsupported property :" ^ name ^ " on " ^ S.node_kind_name kind)
      )

let flags kind actions =
  List.fold_left
    (fun values action ->
      match
        List.find_opt (fun (name, _, _) -> name = action.event_name) event_specs
      with
      | None -> fail ("unknown event :" ^ action.event_name)
      | Some (_, _, flags) ->
          List.fold_left
            (fun values flag ->
              if P.property_supported kind flag then
                P.Property_map.add flag (P.BoolValue true) values
              else values)
            values flags)
    P.Property_map.empty actions

let validate_properties kind actions properties =
  let values =
    List.fold_left
      (fun values (property, value) ->
        match (property, value) with
        | Standard_property property, Some value ->
            if not (P.property_value_supported_for_kind kind property value)
            then fail ("invalid property for " ^ S.node_kind_name kind);
            P.Property_map.add property value values
        | _ -> values)
      (flags kind actions) properties
  in
  if not (P.node_properties_supported kind values) then
    fail ("incompatible properties on " ^ S.node_kind_name kind);
  List.iter
    (fun action ->
      let _, probe, _ =
        List.find (fun (name, _, _) -> name = action.event_name) event_specs
      in
      if not (P.event_supported_for_properties kind values probe) then
        fail
          ("unsupported event :" ^ action.event_name ^ " on "
         ^ S.node_kind_name kind))
    actions

let child_supported parent child =
  match (parent, child) with
  | Some (Standard parent), Standard child
    when not (P.child_kind_supported parent child) ->
      fail
        ("invalid child " ^ S.node_kind_name child ^ " in "
       ^ S.node_kind_name parent)
  | _ -> ()

let compile ~actions source =
  let rec node components stack parent depth data =
    if depth > 128 then fail "view nesting exceeds 128";
    let descend = node components stack parent (depth + 1) in
    match vector data with
    | [ tag; test; child ] when name tag = "when" ->
        When (expression test, descend child)
    | [ tag; options; child ] when name tag = "for" ->
        let options = fields options in
        only [ "items"; "as"; "key" ] options;
        let alias = name (required "as" options) in
        if List.mem alias [ "model"; "props" ] then fail "reserved loop alias";
        Each
          ( expression (required "items" options),
            alias,
            vector (required "key" options),
            descend child )
    | [ tag; component; props ] when name tag = "use" ->
        let component = name component in
        if List.mem component stack then
          fail ("recursive component :" ^ component);
        Component
          ( List.map (fun (key, value) -> (key, expression value)) (fields props),
            node components (component :: stack) parent (depth + 1)
              (required component components) )
    | tag :: rest ->
        let target = target (name tag) in
        child_supported parent target;
        let props, children =
          match rest with
          | (Edn.Any (Edn.Map _) as props) :: children ->
              (fields props, children)
          | children -> ([], children)
        in
        let events =
          match List.assoc_opt "on" props with
          | None -> []
          | Some value ->
              List.map
                (fun (event_name, action) ->
                  let action_name, arguments =
                    match action with
                    | Edn.Any (Edn.Keyword _) -> (name action, [])
                    | _ -> (
                        match vector action with
                        | action :: arguments ->
                            (name action, List.map expression arguments)
                        | [] -> fail "empty action")
                  in
                  if not (List.mem action_name actions) then
                    fail ("unregistered OCaml action :" ^ action_name);
                  { event_name; action_name; arguments })
                (fields value)
        in
        let props =
          List.filter_map
            (fun (key, value) ->
              if key = "on" then None
              else
                let property = property target key in
                let value = expression value in
                (match value with
                | Literal value -> ignore (wire property value)
                | Binding _ -> ());
                Some (property, value))
            props
        in
        (match target with
        | Standard kind -> ignore (flags kind events)
        | Extension _ -> ());
        Element
          ( target,
            props,
            events,
            List.map (node components stack (Some target) (depth + 1)) children
          )
    | [] -> fail "empty view"
  in
  try
    if String.length source > 1_048_576 then fail "view source exceeds 1 MiB";
    let data =
      match Edn.of_edn_string_all source with
      | [ data ] -> data
      | _ -> fail "expected exactly one EDN document"
    in
    let components, view =
      match data with
      | Edn.Any (Edn.Map _) ->
          let document = fields data in
          only [ "version"; "components"; "view" ] document;
          (match required "version" document with
          | Edn.Any (Edn.Int 1L) -> ()
          | _ -> fail "unsupported view version");
          let components =
            match List.assoc_opt "components" document with
            | Some value -> fields value
            | None -> []
          in
          (components, required "view" document)
      | _ -> ([], data)
    in
    Ok (node components [] None 0 view)
  with Invalid_view message | Edn.Parse_error message -> Error message

let component_environment environment props =
  ( "props",
    Edn.any
      (Edn.map
         (List.map
            (fun (key, value) -> (keyword key, evaluate environment value))
            props)) )
  :: List.remove_assoc "props" environment

let items environment source alias key =
  let seen = Hashtbl.create 16 in
  List.map
    (fun item ->
      let id = lookup item key in
      (match id with
      | Edn.Any (Edn.String _ | Edn.Keyword _ | Edn.Int _) -> ()
      | _ -> fail "list key must be a string, keyword or integer");
      let id = Edn.to_edn_string id in
      if Hashtbl.mem seen id then fail ("duplicate list key " ^ id);
      Hashtbl.add seen id ();
      (id, (alias, item) :: List.remove_assoc alias environment))
    (vector (evaluate environment source))

let rec validate environment = function
  | Element (target, properties, actions, children) ->
      let properties =
        List.map
          (fun (property, value) ->
            (property, wire property (evaluate environment value)))
          properties
      in
      (match target with
      | Standard kind -> validate_properties kind actions properties
      | Extension _ -> ());
      List.iter (validate environment) children
  | When (condition, child) ->
      if boolean (evaluate environment condition) then
        validate environment child
  | Each (source, alias, key, child) ->
      List.iter
        (fun (_, environment) -> validate environment child)
        (items environment source alias key)
  | Component (props, child) ->
      validate (component_environment environment props) child

(* Interpreter-owned conversions share the mount scope; caller sources are borrowed. *)
let derive context f source =
  Signal.own_signal context.U.ui_scope (Signal.map f source)

let rec mount ~dispatch source node context parent =
  match node with
  | Element (target, properties, actions, children) ->
      let id =
        match target with
        | Standard kind -> U.create context kind
        | Extension name -> U.extension context name
      in
      List.iter
        (fun (property, expression) ->
          let apply value =
            match (property, wire property value) with
            | Standard_property property, Some value ->
                U.value_property context id property value
            | Standard_property property, None ->
                Lui_runtime.remove_prop context.U.ui_application id property
            | Extension_property property, Some value ->
                U.extension_property context id property value
            | Extension_property property, None ->
                Lui_runtime.remove_extension_prop context.U.ui_application id
                  property
          in
          match expression with
          | Literal value -> apply value
          | Binding _ ->
              ignore
                (Signal.own context.U.ui_scope
                   (Signal.observe
                      (derive context
                         (fun environment -> evaluate environment expression)
                         source)
                      apply)))
        properties;
      (match target with
      | Standard kind ->
          P.Property_map.iter (U.value_property context id) (flags kind actions)
      | Extension _ -> ());
      if actions <> [] then
        U.on_event context id (fun event ->
            match
              List.find_opt
                (fun action -> action.event_name = event_name event)
                actions
            with
            | None -> ()
            | Some action ->
                dispatch action.action_name
                  (List.map (evaluate (Signal.sample source)) action.arguments)
                  event);
      Option.iter (fun parent -> U.append context parent id) parent;
      List.iter
        (fun child -> ignore (mount ~dispatch source child context (Some id)))
        children;
      id
  | When (condition, child) ->
      Lui_elements.dynamic
        (fun context parent ->
          let test =
            derive context
              (fun environment -> boolean (evaluate environment condition))
              source
          in
          Lui_dynamic.conditional context parent test (fun context ->
              mount ~dispatch source child context None))
        context parent
  | Each (expression, alias, key, child) ->
      Lui_elements.dynamic
        (fun context parent ->
          let rows =
            derive context
              (fun environment -> items environment expression alias key)
              source
          in
          Lui_dynamic.keyed context parent rows fst String.compare
            (fun context row ->
              let source = derive context snd row in
              mount ~dispatch source child context None))
        context parent
  | Component (props, child) ->
      let source =
        derive context
          (fun environment -> component_environment environment props)
          source
      in
      mount ~dispatch source child context parent

let render document ~model ~project ~dispatch context parent =
  let source =
    derive context
      (fun model ->
        let environment = [ ("model", project model) ] in
        validate environment document;
        environment)
      model
  in
  mount ~dispatch source document context parent
