module Edn = Melange_edn
module P = Lui_protocol
module X = Lui_extension
module S = Lui_wire_schema
module M = P.String_map

type shape =
  | String
  | Keyword
  | Bool
  | Int
  | Float
  | Record of shape M.t
  | Vector of shape
  | Tuple of shape array
  | Nullable of shape
  | Enum of Edn.any list

type action = { name : string; arguments : shape list; events : string list }
type host = { profile : P.platform_profile; fingerprints : string M.t }
type extension_info = {
  schema : X.extension_component_schema;
  tweak : bool;
  fingerprint : string;
  properties : X.extension_property_schema M.t;
  events : X.extension_event_schema M.t;
  view : string S.view_contract;
}
type t = {
  model : shape;
  actions : action M.t;
  extensions : X.extension_registry;
  extension_index : extension_info M.t;
  hosts : host list;
}

exception Invalid_contract of string

let fail message = raise (Invalid_contract message)

let index entries =
  List.fold_left
    (fun result (name, value) ->
      if M.mem name result then fail ("duplicate declaration: " ^ name);
      M.add name value result)
    M.empty entries

let record fields = Record (index fields)

let rec describe = function
  | String -> "string"
  | Keyword -> "keyword"
  | Bool -> "bool"
  | Int -> "int"
  | Float -> "float"
  | Record _ -> "record"
  | Vector item -> "vector of " ^ describe item
  | Tuple _ -> "fixed tuple"
  | Nullable value -> "nullable " ^ describe value
  | Enum _ -> "enum"

let keyword (Edn.Any value) =
  match value with
  | Edn.Keyword value -> Edn.keyword_to_string value
  | _ -> fail "expected a keyword"

let rec infer (Edn.Any value) =
  match value with
  | Edn.String _ -> String
  | Edn.Keyword _ -> Keyword
  | Edn.Bool _ -> Bool
  | Edn.Int value
    when value >= Int64.of_int min_int && value <= Int64.of_int max_int -> Int
  | Edn.Float value when P.is_finite value -> Float
  | Edn.Nil -> Enum [Edn.any Edn.nil]
  | Edn.Map fields ->
      record (Array.to_list (Array.map (fun (key, value) -> keyword key, infer value) fields))
  | Edn.Vector values -> Tuple (Array.map infer values)
  | _ -> fail "unsupported data type in the view contract"

let rec check_value path expected (Edn.Any value as data) =
  let mismatch () = fail (path ^ ": expected " ^ describe expected) in
  match expected, value with
  | String, Edn.String _ | Keyword, Edn.Keyword _ | Bool, Edn.Bool _ -> ()
  | Int, Edn.Int number
    when number >= Int64.of_int min_int && number <= Int64.of_int max_int -> ()
  | Float, Edn.Float number when P.is_finite number -> ()
  | Nullable _, Edn.Nil -> ()
  | Nullable inner, _ -> check_value path inner data
  | Enum allowed, _ -> if not (List.mem data allowed) then mismatch ()
  | Record fields, Edn.Map entries ->
      let values = index (Array.to_list (Array.map (fun (key, value) -> keyword key, value) entries)) in
      M.iter (fun name expected ->
        match M.find_opt name values with
        | Some value -> check_value (path ^ "/:" ^ name) expected value
        | None -> fail (path ^ ": missing field :" ^ name)) fields;
      M.iter (fun name _ -> if not (M.mem name fields) then fail (path ^ ": unknown field :" ^ name)) values
  | Vector item, Edn.Vector values ->
      Array.iteri (fun index value -> check_value (path ^ "/" ^ string_of_int index) item value) values
  | Tuple fields, Edn.Vector values when Array.length fields = Array.length values ->
      Array.iteri (fun index expected -> check_value (path ^ "/" ^ string_of_int index) expected values.(index)) fields
  | _ -> mismatch ()

let rec accepts expected actual =
  match expected, actual with
  | _, Enum values ->
      List.for_all (fun value -> try check_value "literal" expected value; true with Invalid_contract _ -> false) values
  | Nullable expected, Nullable actual -> accepts expected actual
  | Nullable expected, actual -> accepts expected actual
  | String, String | Keyword, Keyword | Bool, Bool | Int, Int | Float, Float -> true
  | Record expected, Record actual ->
      M.cardinal expected = M.cardinal actual && M.for_all (fun key expected ->
        match M.find_opt key actual with Some actual -> accepts expected actual | None -> false) expected
  | Vector expected, Vector actual -> accepts expected actual
  | Vector expected, Tuple actual -> Array.for_all (accepts expected) actual
  | Tuple expected, Tuple actual ->
      Array.length expected = Array.length actual && Array.for_all2 accepts expected actual
  | _ -> false

let require_shape context expected actual =
  if not (accepts expected actual) then
    fail (context ^ ": expected " ^ describe expected ^ ", got " ^ describe actual)

let rec path shape = function
  | [] -> shape
  | key :: rest ->
      let next = match shape, key with
        | Record fields, Edn.Any (Edn.Keyword name) ->
            let name = Edn.keyword_to_string name in
            (match M.find_opt name fields with
            | Some shape -> shape
            | None -> fail ("unknown binding field :" ^ name))
        | Tuple fields, Edn.Any (Edn.Int index)
          when index >= 0L && index < Int64.of_int (Array.length fields) -> fields.(Int64.to_int index)
        | Vector _, _ -> fail "indexing a variable-length vector is not statically safe; use :for or a tuple contract"
        | _ -> fail ("binding path does not match " ^ describe shape)
      in
      path next rest

let nullable = function Nullable _ -> true | Enum values -> List.mem (Edn.any Edn.nil) values | _ -> false

let rec of_edn (Edn.Any value as data) =
  match value with
  | Edn.Keyword _ -> (match keyword data with
      | "string" -> String | "keyword" -> Keyword | "bool" -> Bool
      | "int" -> Int | "float" -> Float
      | name -> fail ("unknown component prop type :" ^ name))
  | Edn.Map fields ->
      record (Array.to_list (Array.map (fun (key, value) -> keyword key, of_edn value) fields))
  | Edn.Vector values -> (match Array.to_list values with
      | [tag; shape] when keyword tag = "vector" -> Vector (of_edn shape)
      | [tag; shape] when keyword tag = "maybe" -> Nullable (of_edn shape)
      | tag :: fields when keyword tag = "tuple" -> Tuple (Array.of_list (List.map of_edn fields))
      | tag :: values when keyword tag = "enum" && values <> [] ->
          List.iter (fun value -> ignore (infer value)) values; Enum values
      | _ -> fail "invalid component prop type")
  | _ -> fail "invalid component prop type"

let host ?(registered = []) profile source =
  let fingerprints =
    List.map (fun declaration ->
      declaration.Lui_extension_check.host_identifier,
      declaration.Lui_extension_check.host_literal)
      (Lui_extension_check.extract_fingerprints source)
  in
  {profile; fingerprints = index (List.rev_append registered fingerprints)}

let create ?extensions ?(extension_contracts = []) ~model ~actions ~hosts () =
  if hosts = [] then fail "at least one target host is required";
  ignore (index (List.map (fun host -> X.profile_token host.profile, ()) hosts));
  let extensions = match extensions with Some value -> value | None -> X.registry () in
  let extension_contracts = index extension_contracts in
  X.freeze extensions;
  let extension_index = Hashtbl.fold (fun identifier schema result ->
    let tweak = X.is_tweak extensions identifier in
    let fingerprint = if tweak then X.tweak_fingerprint schema else X.fingerprint schema in
    let properties = index (List.map (fun property -> property.X.extension_property_name, property) schema.X.extension_properties) in
    let events = index (List.map (fun event -> event.X.extension_event_name, event) schema.X.extension_events) in
    let view = match S.extension_view_contract identifier with
      | Some contract -> contract
      | None -> (match M.find_opt identifier extension_contracts with
          | Some contract -> contract
          | None -> fail ("missing OCaml typed view contract for extension: " ^ identifier)) in
    if view.S.view_result <> "t" || view.S.view_slots <> [] then fail (identifier ^ ": unsupported extension result or named slots");
    ignore (index (List.map (fun (name, domain, required) ->
      let property = match M.find_opt name properties with
        | Some property -> property | None -> fail (identifier ^ ": typed property is absent from host schema: " ^ name) in
      let compatible = match domain, property.X.extension_property_kind with
        | S.ViewString, X.StringScalar | S.ViewBool, X.BoolScalar
        | S.ViewInt, X.IntScalar | S.ViewFloat, X.FloatScalar
        | S.ViewEnum _, X.StringScalar -> true | _ -> false in
      if not compatible then fail (identifier ^ ": typed property disagrees with host scalar kind: " ^ name);
      if property.X.extension_property_required && property.X.extension_property_default = None && not required then
        fail (identifier ^ ": required host property is optional in typed API: " ^ name);
      name, ()) view.S.view_properties));
    List.iter (fun event -> if not (M.mem event events) then
      fail (identifier ^ ": typed event is absent from host schema: " ^ event)) view.S.view_events;
    M.iter (fun name property ->
      if property.X.extension_property_required && property.X.extension_property_default = None
         && not (List.exists (fun (key, _, _) -> key = name) view.S.view_properties) then
        fail (identifier ^ ": required host property is absent from typed API: " ^ name)) properties;
    M.add identifier {schema; tweak; fingerprint; properties; events; view} result) extensions.X.extension_schemas M.empty
  in
  {model; actions = index (List.map (fun action -> action.name, action) actions); extensions; extension_index; hosts}

let extension contract hosts identifier =
  let info = match M.find_opt identifier contract.extension_index with
    | Some info -> info
    | None -> fail ("unregistered extension: " ^ identifier)
  in
  List.iter (fun host ->
    let profile = X.profile_token host.profile in
    if not (X.profile_supported info.schema host.profile) then
      fail (identifier ^ " is unsupported on " ^ profile);
    match M.find_opt identifier host.fingerprints with
    | Some actual when actual = info.fingerprint -> ()
    | Some _ -> fail (identifier ^ ": host fingerprint mismatch on " ^ profile)
    | None -> fail (identifier ^ ": no host registration on " ^ profile)) hosts;
  info
