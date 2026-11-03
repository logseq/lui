module Edn = Melange_edn
module P = Lui_protocol
module U = Lui_ui
module S = Lui_wire_schema
module Contract = Data_contract
module Sources = Data_sources
module X = Lui_extension
module M = P.String_map

type expression = Literal of Edn.any | Binding of Edn.any list
type target = Standard of P.node_kind | Extension of Contract.extension_info
type property = Standard_property of P.property | Extension_property of string * X.scalar_kind

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
  | Choice of expression * node * node
  | Platform of (string * node) list
  | Slot of node option

type t = { root : node; contract : Contract.t }

type environment = { values : (string * Edn.any) list; caller : environment option }

exception Invalid_view of string

let fail message = raise (Invalid_view message)
let keyword name = Edn.any (Edn.keyword name)

let view_contract kind =
  match S.view_contract kind with
  | Some contract -> contract
  | None -> fail ("internal node is not a typed view constructor: " ^ S.node_kind_name kind)

let typed_properties = Hashtbl.create 4096

let () =
  List.iter (fun kind ->
    match S.view_contract kind with
    | None -> ()
    | Some contract -> List.iter (fun (property, domain, required) ->
        Hashtbl.add typed_properties (kind, property) (domain, required)) contract.S.view_properties)
    S.all_node_kinds

let property_type target property =
  match target, property with
  | Standard kind, Standard_property property ->
      (match Hashtbl.find_opt typed_properties (kind, property) with
      | Some contract -> contract
      | None -> fail ("property is absent from the typed constructor: " ^ S.node_kind_name kind ^ "/" ^ S.property_name property))
  | Extension info, Extension_property (name, _) ->
      (match List.find_opt (fun (key, _, _) -> key = name) info.Contract.view.S.view_properties with
      | Some (_, domain, required) -> domain, required
      | None -> fail ("property is absent from the typed extension API: " ^ name))
  | Extension _, Standard_property P.KeyValue -> S.ViewString, false
  | _ -> fail "property target mismatch"

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
      (match entries with
      | ["literal", value] -> Literal value
      | _ ->
          only [ "bind" ] entries;
          let path = vector (required "bind" entries) in
          if path = [] then fail "binding path must include a scope";
          Binding path)
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
  | Binding (scope :: path) -> lookup (required (name scope) environment.values) path

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

let typed_value domain (Edn.Any value as data) =
  let invalid () = fail "value does not match the OCaml argument type" in
  let decode_scalar () = match scalar data with Some value -> value | None -> invalid () in
  match domain, value with
  | S.ViewString, Edn.String _ | S.ViewBool, Edn.Bool _
  | S.ViewInt, Edn.Int _ | S.ViewFloat, Edn.Float _ -> decode_scalar ()
  | (S.ViewEnum allowed | S.ViewIcon allowed), Edn.Keyword tag ->
      let name = Edn.keyword_to_string tag in
      if not (List.mem name allowed) then invalid ();
      P.StringValue name
  | S.ViewIcon _, Edn.Vector [|tag; Edn.Any (Edn.String icon)|] when name tag = "app" ->
      P.StringValue ("app:" ^ icon)
  | S.ViewToken, Edn.Vector [|tag; (Edn.Any (Edn.String _) as value)|] when name tag = "string" ->
      (match scalar value with Some value -> value | None -> invalid ())
  | S.ViewToken, Edn.Vector [|tag; (Edn.Any (Edn.Int _) as value)|] when name tag = "int" ->
      (match scalar value with Some value -> value | None -> invalid ())
  | S.ViewAttributes, Edn.Vector entries ->
      let entries = Array.to_list (Array.map (fun (Edn.Any entry) -> match entry with
        | Edn.Vector [|Edn.Any (Edn.String key); Edn.Any (Edn.String value)|] -> key, value
        | _ -> invalid ()) entries) in
      P.StringValue (P.data_attrs_encode entries)
  | S.ViewFloatTuple count, Edn.Vector entries when Array.length entries = count ->
      let values = Array.map (fun (Edn.Any value) -> match value with
        | Edn.Float value when P.is_finite value -> Printf.sprintf "%.17g" value
        | _ -> invalid ()) entries in
      P.StringValue (String.concat " " (Array.to_list values))
  | _ -> invalid ()

let wire target property (Edn.Any data as value) =
  let domain, required = property_type target property in
  let decoded = match data with
    | Edn.Nil when not required -> None
    | _ -> Some (typed_value domain value) in
  match (property, decoded) with
  | Standard_property property, Some value ->
      if not (P.property_value_supported property value) then
        fail ("invalid value for :" ^ S.property_name property);
      Some value
  | Extension_property (_, kind), Some value ->
      if not (X.scalar_value_supported kind value) then fail "invalid extension property type";
      Some value
  | _, None -> None

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
  | P.ScrollEdges _ -> "scroll-edges"
  | P.VirtualWindow _ -> "virtual-window"
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

let target contract hosts tag =
  if String.starts_with ~prefix:"ext/" tag then
    let identifier = String.sub tag 4 (String.length tag - 4) in
    Extension (Contract.extension contract hosts identifier)
  else
    match Hashtbl.find_opt kind_table tag with
    | Some P.Root -> fail "root is owned by Lui_app"
    | Some kind -> ignore (view_contract kind); Standard kind
    | None -> fail ("unknown component :" ^ tag)

let property target name =
  match target with
  | Extension info ->
      if name = "key" then Standard_property P.KeyValue else
      (match M.find_opt name info.Contract.properties with
      | Some property -> Extension_property (name, property.X.extension_property_kind)
      | None -> fail ("unknown extension property :" ^ name))
  | Standard kind -> (
      match Hashtbl.find_opt property_table name with
      | Some property when P.property_supported kind property && Hashtbl.mem typed_properties (kind, property) ->
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
    when not (P.can_contain_children parent && P.child_kind_supported parent child) ->
      fail
        ("invalid child " ^ S.node_kind_name child ^ " in "
       ^ S.node_kind_name parent)
  | Some (Standard parent), Extension _ when not (X.standard_container_supported parent) ->
      fail ("extension child is unsupported in " ^ S.node_kind_name parent)
  | Some (Extension info), Standard _
    when not (info.Contract.tweak || info.Contract.schema.X.extension_standard_children) ->
      fail ("standard child is unsupported in " ^ info.Contract.schema.X.extension_identifier)
  | Some (Extension info), Extension child
    when not (info.Contract.tweak || X.identifier_allowed info.Contract.schema.X.extension_child_identifiers child.Contract.schema.X.extension_identifier) ->
      fail ("extension child is unsupported in " ^ info.Contract.schema.X.extension_identifier)
  | _ -> ()

exception Located_error of string

let shape environment = function
  | Literal value -> Contract.infer value
  | Binding path -> Contract.path (Contract.Record environment) path

let check_expression environment expected = function
  | Literal value -> Contract.check_value "literal" expected value
  | value -> Contract.require_shape "binding" expected (shape environment value)

let view_shape_supported domain actual =
  let module C = Contract in
  let token tag payload = C.Tuple [|C.Enum [keyword tag]; payload|] in
  match domain with
  | S.ViewString -> C.accepts C.String actual
  | S.ViewBool -> C.accepts C.Bool actual
  | S.ViewInt -> C.accepts C.Int actual
  | S.ViewFloat -> C.accepts C.Float actual
  | S.ViewAttributes -> C.accepts (C.Vector (C.Tuple [|C.String; C.String|])) actual
  | S.ViewFloatTuple count -> C.accepts (C.Tuple (Array.make count C.Float)) actual
  | S.ViewEnum allowed -> C.accepts (C.Enum (List.map keyword allowed)) actual
  | S.ViewIcon allowed ->
      C.accepts (C.Enum (List.map keyword allowed)) actual
      || C.accepts (token "app" C.String) actual
  | S.ViewToken -> C.accepts (token "string" C.String) actual || C.accepts (token "int" C.Int) actual

let check_property environment target property value =
  let domain, required = property_type target property in
  let validate data =
    let value = wire target property data in
    match target, property, value with
    | Standard kind, Standard_property property, Some value ->
        if not (P.property_value_supported_for_kind kind property value) then
          fail ("invalid property for " ^ S.node_kind_name kind)
    | _ -> ()
  in
  match value with
  | Literal value -> validate value
  | Binding _ ->
      let actual = shape environment value in
      let rec supported = function
        | Contract.Nullable inner when not required -> supported inner
        | Contract.Enum values ->
            List.for_all (fun value -> validate value; true) values
        | actual -> view_shape_supported domain actual
      in
      if not (supported actual) then
        fail ("property binding has incompatible OCaml argument type: " ^ Contract.describe actual)

let rec fixed_root = function
  | Element _ -> true
  | Component (_, child) | Slot (Some child) -> fixed_root child
  | Platform branches -> List.for_all (fun (_, child) -> fixed_root child) branches
  | Choice (_, yes, no) -> fixed_root yes && fixed_root no
  | Slot None -> true
  | When _ | Each _ -> false

let rec check_view_type expected = function
  | Element (target, _, _, _) ->
      let actual = match target with
        | Standard (P.ListSectionHeader | P.ListSectionFooter) -> "t"
        | Standard kind -> (view_contract kind).S.view_result
        | Extension _ -> "t" in
      if actual <> expected then fail ("expected " ^ expected ^ " child, got " ^ actual)
  | Component (_, child) | Slot (Some child) | When (_, child) | Each (_, _, _, child) ->
      check_view_type expected child
  | Choice (_, yes, no) -> check_view_type expected yes; check_view_type expected no
  | Platform branches -> List.iter (fun (_, child) -> check_view_type expected child) branches
  | Slot None -> ()

let rec view_result = function
  | Element (Standard (P.ListSectionHeader | P.ListSectionFooter), _, _, _)
  | Element (Extension _, _, _, _) -> Some "t"
  | Element (Standard kind, _, _, _) -> Some (view_contract kind).S.view_result
  | Component (_, child) | Slot (Some child) | When (_, child) | Each (_, _, _, child) -> view_result child
  | Choice (_, yes, no) -> unify_view_results (view_result yes) (view_result no)
  | Platform branches -> List.fold_left (fun result (_, child) -> unify_view_results result (view_result child)) None branches
  | Slot None -> None
and unify_view_results left right =
  match left, right with
  | None, result | result, None -> result
  | Some left, Some right when left = right -> Some left
  | _ -> fail "view branches have different OCaml result types"

let compile_graph ~contract graph =
  let count = ref 0 in
  let model_environment = M.singleton "model" contract.Contract.model in
  let rec node owner stack parent depth environment hosts slots location data =
    let build () =
      incr count;
      if !count > 100_000 then fail "compiled view exceeds 100000 nodes";
      if depth > 128 then fail "view nesting exceeds 128";
      let descend suffix = node owner stack parent (depth + 1) environment hosts slots (location ^ suffix) in
      match vector data with
      | [tag; test; child] when name tag = "when" ->
          let test = expression test in
          check_expression environment Contract.Bool test;
          When (test, descend "/when" child)
      | [tag; test; yes; no] when name tag = "if" ->
          let test = expression test in
          check_expression environment Contract.Bool test;
          Choice (test, descend "/if/then" yes, descend "/if/else" no)
      | [tag; data] when name tag = "platform" ->
          let branches = fields data in
          if branches = [] then fail "empty platform selection";
          only ["generic"; "web"; "ios"; "macos"; "android"; "linux"; "windows"; "default"] branches;
          let selected host =
            let platform = X.operating_system_name host.Contract.profile.P.profile_os in
            if List.mem_assoc platform branches then platform else "default"
          in
          List.iter (fun host ->
            if not (List.mem_assoc (selected host) branches) then fail "platform branches do not cover every target host") hosts;
          Platform (List.map (fun (name, data) ->
            let hosts = List.filter (fun host -> selected host = name) hosts in
            name, node owner stack parent (depth + 1) environment hosts slots (location ^ "/platform/" ^ name) data) branches)
      | [tag; slot] when name tag = "slot" ->
          let slot = name slot in
          (match M.find_opt slot slots with
          | Some build -> build parent (depth + 1)
          | None -> fail ("undeclared slot :" ^ slot))
      | [tag; options; child] when name tag = "for" ->
          let options = fields options in
          only ["items"; "as"; "key"] options;
          let alias = name (required "as" options) in
          if alias = "model" || alias = "props" then fail "reserved loop alias";
          let source = expression (required "items" options) in
          let item = match shape environment source with
            | Contract.Vector item -> item
            | Contract.Tuple fields when Array.length fields > 0 ->
                let item = fields.(0) in
                Array.iter (Contract.require_shape "list item" item) fields;
                item
            | _ -> fail "list source must have a vector contract"
          in
          let key = vector (required "key" options) in
          if key = [] then fail "list key path cannot be empty";
          let key_shape = Contract.path item key in
          (match key_shape with
          | Contract.String | Contract.Keyword | Contract.Int -> ()
          | Contract.Enum values -> List.iter (fun value -> match Contract.infer value with
              | Contract.String | Contract.Keyword | Contract.Int -> ()
              | _ -> fail "list keys must be non-null strings, keywords or integers") values
          | _ -> fail "list keys must be non-null strings, keywords or integers");
          let environment = M.add alias item environment in
          Each (source, alias, key, node owner stack parent (depth + 1) environment hosts slots (location ^ "/for") child)
      | tag :: component :: props :: supplied_slots when name tag = "use" ->
          if List.length supplied_slots > 1 then fail "component use accepts one slots map";
          let component_name = name component in
          let definition_owner, component_name, definition = Sources.component graph owner component_name in
          let identity = definition_owner.Sources.id, component_name in
          if List.mem identity stack then fail ("recursive component :" ^ component_name);
          let props = List.map (fun (key, value) -> key, expression value) (fields props) in
          let declarations = match definition.Sources.props with Contract.Record fields -> fields | _ -> fail "invalid component prop schema" in
          if M.cardinal declarations <> List.length props then fail ("wrong props for :" ^ component_name);
          List.iter (fun (key, value) -> match M.find_opt key declarations with
            | Some expected -> check_expression environment expected value
            | None -> fail ("unknown component prop :" ^ key)) props;
          let supplied_slots = match supplied_slots with [] -> [] | [data] -> fields data | _ -> fail "invalid slots map" in
          if List.length supplied_slots <> List.length definition.Sources.slots then fail ("wrong slots for :" ^ component_name);
          let slot_builders = Contract.index (List.map (fun (slot, data) ->
            if not (List.mem slot definition.Sources.slots) then fail ("unknown slot :" ^ slot);
            slot, (fun parent depth -> Slot (Some (node owner stack parent depth environment hosts slots (location ^ "/slot/" ^ slot) data)))) supplied_slots) in
          Component (props, node definition_owner (identity :: stack) parent (depth + 1)
            (M.add "props" definition.Sources.props model_environment) hosts slot_builders
            (definition_owner.Sources.id ^ "#" ^ component_name) definition.Sources.view)
      | tag :: rest ->
          let target = target contract hosts (name tag) in
          child_supported parent target;
          let props, children = match rest with
            | (Edn.Any (Edn.Map _) as props) :: children -> fields props, children
            | children -> [], children
          in
          let events = match List.assoc_opt "on" props with
            | None -> []
            | Some data -> List.map (fun (event_name, data) ->
                let event_key = match target with
                  | Standard _ ->
                      if not (List.exists (fun (name, _, _) -> name = event_name) event_specs) then fail ("unknown event :" ^ event_name);
                      (match target with
                      | Standard kind when not (List.mem event_name (view_contract kind).S.view_events) ->
                          fail ("event is absent from the typed constructor: " ^ event_name)
                      | _ -> ());
                      event_name
                  | Extension info ->
                      if not (M.mem event_name info.Contract.events && List.mem event_name info.Contract.view.S.view_events) then fail ("unknown typed extension event :" ^ event_name);
                      "ext/" ^ info.Contract.schema.X.extension_identifier ^ "/" ^ event_name
                in
                let action_name, arguments = match data with
                  | Edn.Any (Edn.Keyword _) -> name data, []
                  | _ -> (match vector data with
                      | action :: args -> name action, List.map expression args
                      | [] -> fail "empty action")
                in
                let declaration = match M.find_opt action_name contract.Contract.actions with
                  | Some action -> action | None -> fail ("unregistered OCaml action :" ^ action_name)
                in
                if not (List.mem event_key declaration.Contract.events) then fail ("action :" ^ action_name ^ " does not accept " ^ event_key);
                if List.length arguments <> List.length declaration.Contract.arguments then fail ("wrong action arity for :" ^ action_name);
                List.iter2 (check_expression environment) declaration.Contract.arguments arguments;
                {event_name; action_name; arguments}) (fields data)
          in
          let properties = List.filter_map (fun (key, data) ->
            if key = "on" || key = "slots" then None else
              let property = property target key in
              let value = expression data in
              check_property environment target property value;
              Some (property, value)) props
          in
          (match target with
          | Standard kind ->
              List.iter (fun (property, _, required) ->
                if required && not (List.exists (function
                  | Standard_property key, _ -> key = property | _ -> false) properties) then
                  fail ("missing required OCaml argument: " ^ S.property_name property))
                (view_contract kind).S.view_properties;
              let known = List.filter_map (fun (property, value) -> match value with
                | Literal value -> Some (property, wire target property value) | _ -> None) properties in
              if List.length known = List.length properties then validate_properties kind events known
              else begin
                let flags = flags kind events in
                let declared property = List.find_opt (function
                  | Standard_property key, _ -> key = property
                  | _ -> false) properties in
                let presence property = match declared property with
                  | Some (key, Literal value) ->
                      let present = Option.is_some (wire target key value) in
                      present, present
                  | Some (_, (Binding _ as expression)) ->
                      not (Contract.nullable (shape environment expression)), true
                  | None ->
                      let present = P.Property_map.mem property flags in
                      present, present
                in
                let definite property = fst (presence property)
                and possible property = snd (presence property) in
                if not (P.node_property_presence_supported kind ~definite ~possible) then
                  fail ("impossible property set on " ^ S.node_kind_name kind);
                let values = List.fold_left (fun values (property, value) -> match property, value with
                  | Standard_property property, Some value -> P.Property_map.add property value values
                  | _ -> values) flags known in
                if P.tree_row_kind kind
                   && (definite P.TreeLevel || definite P.ChangeEnabled)
                   && (match P.Property_map.find_opt P.RoleValue values with
                      | Some (P.StringValue "treeitem") -> false
                      | Some _ -> true
                      | None -> not (possible P.RoleValue)) then
                  fail "tree metadata requires the treeitem role";
                List.iter (fun action ->
                  let _, probe, _ = List.find (fun (name, _, _) -> name = action.event_name) event_specs in
                  let tree_role_possible = match declared P.RoleValue with
                    | Some (_, (Binding _ as value)) ->
                        (match shape environment value with
                        | Contract.Enum candidates ->
                            List.exists (fun data -> match wire target (Standard_property P.RoleValue) data with
                              | Some (P.StringValue "treeitem") -> true | _ -> false) candidates
                        | _ -> true)
                    | _ -> false
                  in
                  let tree_event = tree_role_possible && P.event_supported_for_properties kind
                    (P.Property_map.add P.RoleValue (P.StringValue "treeitem") values) probe in
                  if not (P.event_supported kind probe || P.event_supported_for_properties kind values probe || tree_event) then
                    fail ("unsupported event :" ^ action.event_name ^ " on " ^ S.node_kind_name kind)) events;
                if not (P.surface_size_supported values && P.viewport_size_supported values) then
                  fail "incompatible static size bounds"
              end
          | Extension info ->
              List.iter (fun (name, _, required) ->
                if required && not (List.exists (function
                  | Extension_property (key, _), _ -> key = name | _ -> false) properties) then
                  fail ("missing required typed extension argument: " ^ name)) info.Contract.view.S.view_properties;
              M.iter (fun name schema ->
                if schema.X.extension_property_required && schema.X.extension_property_default = None then
                  match List.find_opt (function Extension_property (key, _), _ -> key = name | _ -> false) properties with
                  | None -> fail ("missing required extension property :" ^ name)
                  | Some (_, Literal (Edn.Any Edn.Nil)) -> fail ("required extension property is nil :" ^ name)
                  | Some (_, value) when Contract.nullable (shape environment value) -> fail ("required extension property is nullable :" ^ name)
                  | _ -> ()) info.Contract.properties);
          let children = List.mapi (fun index data ->
            node owner stack (Some target) (depth + 1) environment hosts slots (location ^ "/" ^ string_of_int index) data) children in
          (match target with
          | Standard kind ->
              (match (view_contract kind).S.view_children with
              | S.ViewList "nothing" -> if children <> [] then fail "leaf constructor cannot have children"
              | S.ViewList expected -> List.iter (check_view_type expected) children
              | S.ViewArguments expected ->
                  if List.length children <> List.length expected || not (List.for_all fixed_root children) then
                    fail "wrong number of unconditional constructor children";
                  List.iter2 check_view_type expected children)
          | Extension info ->
              (match info.Contract.view.S.view_children with
              | S.ViewList "nothing" -> if children <> [] then fail "leaf extension constructor cannot have children"
              | S.ViewList expected -> List.iter (check_view_type expected) children
              | S.ViewArguments expected ->
                  if List.length children <> List.length expected || not (List.for_all fixed_root children) then
                    fail "wrong number of unconditional extension constructor children";
                  List.iter2 check_view_type expected children));
          let supplied_slots = match List.assoc_opt "slots" props with None -> [] | Some data -> fields data in
          let named_slots = match target with
            | Extension _ -> if supplied_slots <> [] then fail "extension has no named OCaml element slots"; []
            | Standard kind -> List.map (fun (slot, data) ->
                let _, expected, multiple = match List.find_opt (fun (name, _, _) -> name = slot) (view_contract kind).S.view_slots with
                  | Some declaration -> declaration | None -> fail ("unknown typed element slot: " ^ slot) in
                let wrapper = match kind, slot with
                  | P.ListSection, "header" -> Some P.ListSectionHeader
                  | P.ListSection, "footer" -> Some P.ListSectionFooter
                  | P.ListItem, "swipe-actions" -> Some P.SwipeActions
                  | _ -> None in
                let slot_parent = match wrapper with Some kind -> Standard kind | None -> target in
                let values = if multiple then vector data else [data] in
                let values = List.map (node owner stack (Some slot_parent) (depth + 1) environment hosts slots (location ^ "/slots/" ^ slot)) values in
                List.iter (check_view_type expected) values;
                if not multiple && not (List.for_all fixed_root values) then fail "named element argument must have one unconditional root";
                let values = match wrapper with
                  | Some kind -> [Element (Standard kind, [], [], values)] | None -> values in
                slot, values) supplied_slots in
          let headers, tails = List.partition (fun (name, _) -> name = "header") named_slots in
          let children = List.fold_right (fun (_, values) rest -> List.rev_append (List.rev values) rest) tails []
            |> fun tail -> List.rev_append (List.rev children) tail
            |> fun rest -> List.fold_right (fun (_, values) rest -> List.rev_append (List.rev values) rest) headers rest in
          (match target with
          | Extension info when info.Contract.tweak ->
              if not (match children with [child] -> fixed_root child | _ -> false) then
                fail "a platform tweak requires exactly one unconditional child; wrap dynamic content in a container"
          | _ -> ());
          Element (target, properties, events, children)
      | [] -> fail "empty view"
    in
    try
      let result = build () in
      (match result with Choice _ | Platform _ -> ignore (view_result result) | _ -> ());
      result
    with
    | Invalid_view message | Contract.Invalid_contract message | Sources.Invalid_source message ->
        raise (Located_error (location ^ ": " ^ message))
  in
  let check_document_view owner view =
    try check_view_type "t" view with Invalid_view message ->
      raise (Located_error (owner.Sources.id ^ "/view: " ^ message))
  in
  try
    Hashtbl.iter (fun _ owner ->
      M.iter (fun name definition ->
        let slots = Contract.index (List.map (fun name -> name, (fun _ _ -> Slot None)) definition.Sources.slots) in
        ignore (node owner [owner.Sources.id, name] None 0 (M.add "props" definition.Sources.props model_environment)
          [] slots (owner.Sources.id ^ "#" ^ name) definition.Sources.view)) owner.Sources.components;
      if owner.Sources.id <> graph.Sources.entry.Sources.id then
        match owner.Sources.view with
        | Some view ->
            let view = node owner [] None 0 model_environment [] M.empty
              (owner.Sources.id ^ "/view") view in
            check_document_view owner view
        | None -> ()) graph.Sources.documents;
    let owner = graph.Sources.entry in
    let view = match owner.Sources.view with Some view -> view | None -> fail (owner.Sources.id ^ ": entry module has no :view") in
    let root = node owner [] None 0 model_environment contract.Contract.hosts M.empty (owner.Sources.id ^ "/view") view in
    check_document_view owner root;
    Ok {root; contract}
  with Invalid_view message | Located_error message | Sources.Invalid_source message | Contract.Invalid_contract message -> Error message

let parse = Sources.parse

let compile_document ~contract document =
  if not (M.is_empty document.Sources.imports) then Error (document.Sources.id ^ ": use compile_files to resolve imports")
  else compile_graph ~contract (Sources.single document)

let compile ~contract source =
  match parse ~id:"<view>" source with
  | Error error -> Error error
  | Ok document -> compile_document ~contract document

let compile_files ?cache ~contract ~load ~entry () =
  match Sources.load_graph ?cache ~load ~entry () with
  | Error error -> Error error
  | Ok graph -> compile_graph ~contract graph

let component_environment environment props =
  let values = ( "props",
    Edn.any
      (Edn.map
         (List.map
            (fun (key, value) -> (keyword key, evaluate environment value))
            props)) )
  :: List.remove_assoc "props" environment.values in
  {values; caller = Some environment}

let caller environment = match environment.caller with
  | Some caller -> caller | None -> fail "slot has no calling scope"

let platform_name profile = X.operating_system_name profile.P.profile_os

let platform_branch profile branches =
  match List.assoc_opt (platform_name profile) branches with
  | Some branch -> branch
  | None -> (match List.assoc_opt "default" branches with
      | Some branch -> branch | None -> fail "no view for the current platform")

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
      (id, {environment with values = (alias, item) :: List.remove_assoc alias environment.values}))
    (vector (evaluate environment source))

let rec validate profile environment = function
  | Element (target, properties, actions, children) ->
      let properties =
        List.map
          (fun (property, value) ->
            (property, wire target property (evaluate environment value)))
          properties
      in
      (match target with
      | Standard kind -> validate_properties kind actions properties
      | Extension info ->
          let values = List.fold_left (fun values (property, value) ->
            match property, value with
            | Extension_property (name, _), Some value -> M.add name value values
            | _ -> values) M.empty properties in
          if not (X.properties_supported info.Contract.schema values) then
            fail ("missing or invalid properties on " ^ info.Contract.schema.X.extension_identifier));
      List.iter (validate profile environment) children
  | When (condition, child) ->
      if boolean (evaluate environment condition) then
        validate profile environment child
  | Each (source, alias, key, child) ->
      List.iter
        (fun (_, environment) -> validate profile environment child)
        (items environment source alias key)
  | Component (props, child) ->
      validate profile (component_environment environment props) child
  | Choice (condition, yes, no) ->
      validate profile environment (if boolean (evaluate environment condition) then yes else no)
  | Platform branches -> validate profile environment (platform_branch profile branches)
  | Slot (Some child) -> validate profile (caller environment) child
  | Slot None -> fail "unresolved component slot"

(* Interpreter-owned conversions share the mount scope; caller sources are borrowed. *)
let derive context f source =
  Signal.own_signal context.U.ui_scope (Signal.map f source)

let rec mount ~dispatch source node context parent =
  match node with
  | Element (target, properties, actions, children) ->
      let id =
        match target with
        | Standard kind -> U.create context kind
        | Extension info ->
            if info.Contract.tweak then U.platform_tweak context info.Contract.schema.X.extension_identifier
            else U.extension context info.Contract.schema.X.extension_identifier
      in
      List.iter
        (fun (property, expression) ->
          let apply value =
            match (property, wire target property value) with
            | Standard_property property, Some value ->
                U.value_property context id property value
            | Standard_property property, None ->
                Lui_runtime.remove_prop context.U.ui_application id property
            | Extension_property (property, _), Some value ->
                U.extension_property context id property value
            | Extension_property (property, _), None ->
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
  | Choice (condition, yes, no) ->
      Lui_elements.dynamic
        (fun context parent ->
          let test = derive context (fun environment -> boolean (evaluate environment condition)) source in
          Lui_dynamic.switch context parent test Bool.equal (fun context enabled ->
            mount ~dispatch source (if enabled then yes else no) context None))
        context parent
  | Platform branches ->
      mount ~dispatch source (platform_branch context.U.ui_profile branches) context parent
  | Slot (Some child) ->
      mount ~dispatch (derive context caller source) child context parent
  | Slot None -> fail "unresolved component slot"

let render document ~model ~project ~dispatch context parent =
  if not (List.exists (fun host -> host.Contract.profile = context.U.ui_profile) document.contract.Contract.hosts) then
    fail "view was not compiled for the current backend profile";
  let source =
    derive context
      (fun model ->
        let data = project model in
        Contract.check_value "model" document.contract.Contract.model data;
        let environment = {values = [ ("model", data) ]; caller = None} in
        validate context.U.ui_profile environment document.root;
        environment)
      model
  in
  mount ~dispatch source document.root context parent
