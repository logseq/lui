open Lui_protocol

let protocol = "lui-agent"
let version = 1

let operations =
  [ "hello"; "tree"; "dump"; "find"; "prop"; "press"; "long-press";
    "double-press"; "submit"; "dismiss"; "appear"; "change"; "type";
    "toggle"; "value"; "key"; "ext" ]

type target = {
  host : string;
  runtime : Lui_runtime.application;
  dispatch : event -> unit;
  flush : unit -> unit;
}

let app_target ?(host = "app") app =
  {
    host;
    runtime = Lui_app.runtime app;
    dispatch = (fun event -> ignore (Lui_app.dispatch_event app event));
    flush = (fun () -> ignore (Lui_app.flush app));
  }

exception Rejected of string

let reject message = raise (Rejected message)

(* ---------- retained tree, keyed by wire names ---------- *)

let kind_name runtime node =
  match Hashtbl.find_opt runtime.Lui_runtime.mounted_nodes node with
  | Some kind -> Some (Lui_wire_schema.node_kind_name kind)
  | None ->
    Option.map
      (fun identifier -> "extension:" ^ identifier)
      (Hashtbl.find_opt runtime.Lui_runtime.runtime_extension_nodes node)

let properties runtime node =
  let standard =
    match Hashtbl.find_opt runtime.Lui_runtime.runtime_properties node with
    | Some props ->
      Property_map.fold
        (fun property value acc ->
           (Lui_wire_schema.property_name property, value) :: acc)
        props []
    | None -> []
  in
  let extension =
    match
      Hashtbl.find_opt runtime.Lui_runtime.runtime_extension_properties node
    with
    | Some props -> String_map.bindings props
    | None -> []
  in
  List.sort (fun (a, _) (b, _) -> String.compare a b) (standard @ extension)

let children runtime node =
  match Hashtbl.find_opt runtime.Lui_runtime.runtime_children node with
  | Some children -> Lui_sequence.to_list children
  | None -> []

let parent runtime node =
  Hashtbl.find_opt runtime.Lui_runtime.runtime_parents node

let all_nodes runtime =
  let nodes = Hashtbl.create 64 in
  Hashtbl.iter (fun node _ -> Hashtbl.replace nodes node ())
    runtime.Lui_runtime.mounted_nodes;
  Hashtbl.iter (fun node _ -> Hashtbl.replace nodes node ())
    runtime.Lui_runtime.runtime_extension_nodes;
  List.sort Int.compare (Hashtbl.fold (fun node () acc -> node :: acc) nodes [])

let live runtime node = kind_name runtime node <> None

let roots runtime =
  List.filter
    (fun node ->
       match parent runtime node with
       | Some owner -> not (live runtime owner)
       | None -> true)
    (all_nodes runtime)

(* ---------- selectors ---------- *)

type selector =
  | Id of int
  | Kind of string
  | Ext of string
  | Text of string
  | Prop of string * string
  | Prop_prefix of string * string
  | All of selector list

let unquote value =
  let length = String.length value in
  if length >= 2 && value.[0] = '"' && value.[length - 1] = '"' then
    String.sub value 1 (length - 2)
  else value

let selector_one text =
  match String.index_opt text ':' with
  | None -> (
    match int_of_string_opt text with
    | Some node -> Some (Id node)
    | None -> Some (Text text))
  | Some colon -> (
    let head = String.sub text 0 colon in
    let rest = String.sub text (colon + 1) (String.length text - colon - 1) in
    match head with
    | "id" -> Option.map (fun node -> Id node) (int_of_string_opt rest)
    | "kind" -> Some (Kind rest)
    | "ext" -> Some (Ext rest)
    | "text" -> Some (Text (unquote rest))
    | "prop" -> (
      match String.index_opt rest '=' with
      | Some equals ->
        let name = String.sub rest 0 equals in
        let value =
          unquote
            (String.sub rest (equals + 1) (String.length rest - equals - 1))
        in
        let length = String.length value in
        if length > 0 && value.[length - 1] = '*' then
          Some (Prop_prefix (name, String.sub value 0 (length - 1)))
        else Some (Prop (name, value))
      | None -> None)
    | _ -> None)

let selector_of_string text =
  match String.split_on_char '&' text with
  | [ one ] -> selector_one one
  | parts ->
    let selectors = List.filter_map selector_one parts in
    if List.length selectors = List.length parts then Some (All selectors)
    else None

let contains ~needle text =
  let needle = String.lowercase_ascii needle
  and text = String.lowercase_ascii text in
  let needle_length = String.length needle
  and text_length = String.length text in
  let rec at index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || at (index + 1))
  in
  at 0

let value_text = function
  | StringValue text -> text
  | value -> Lui_wire.encode_value value

let rec matches runtime node = function
  | Id id -> node = id
  | Kind name -> kind_name runtime node = Some name
  | Ext identifier -> kind_name runtime node = Some ("extension:" ^ identifier)
  | Text needle ->
    List.exists
      (function _, StringValue text -> contains ~needle text | _ -> false)
      (properties runtime node)
  | Prop (name, expected) -> (
    match List.assoc_opt name (properties runtime node) with
    | Some value -> value_text value = expected
    | None -> false)
  | Prop_prefix (name, prefix) -> (
    match List.assoc_opt name (properties runtime node) with
    | Some (StringValue text) ->
      String.length prefix <= String.length text
      && String.sub text 0 (String.length prefix) = prefix
    | _ -> false)
  | All selectors -> List.for_all (matches runtime node) selectors

let find runtime selector =
  List.filter (fun node -> matches runtime node selector) (all_nodes runtime)

(* ---------- request fields ---------- *)

let field fields name = List.assoc_opt name fields

let string_field fields name =
  match field fields name with
  | Some (Lui_json.String text) -> text
  | Some _ -> reject (name ^ " must be a string")
  | None -> reject ("missing " ^ name)

let selector_field fields =
  let text = string_field fields "selector" in
  match selector_of_string text with
  | Some selector -> (text, selector)
  | None -> reject ("bad selector: " ^ text)

let resolve runtime fields =
  let text, selector = selector_field fields in
  match find runtime selector with
  | node :: _ -> node
  | [] -> reject ("no node matches " ^ text)

(* ---------- replies ---------- *)

let add_key buffer name =
  Lui_wire.add_quoted buffer name;
  Buffer.add_char buffer ':'

let add_list buffer add items =
  Buffer.add_char buffer '[';
  List.iteri
    (fun index item ->
       if index > 0 then Buffer.add_char buffer ',';
       add item)
    items;
  Buffer.add_char buffer ']'

let add_int buffer number = Buffer.add_string buffer (string_of_int number)

let reply op extra =
  let buffer = Buffer.create 256 in
  Buffer.add_string buffer "{\"ok\":true,\"op\":";
  Lui_wire.add_quoted buffer op;
  extra buffer;
  Buffer.add_char buffer '}';
  Buffer.contents buffer

let failure op message =
  let buffer = Buffer.create 128 in
  Buffer.add_string buffer "{\"ok\":false";
  (match op with
  | Some op ->
    Buffer.add_string buffer ",\"op\":";
    Lui_wire.add_quoted buffer op
  | None -> ());
  Buffer.add_string buffer ",\"error\":";
  Lui_wire.add_quoted buffer message;
  Buffer.add_char buffer '}';
  Buffer.contents buffer

let add_props buffer props =
  Buffer.add_char buffer '{';
  List.iteri
    (fun index (name, value) ->
       if index > 0 then Buffer.add_char buffer ',';
       add_key buffer name;
       Lui_wire.add_value buffer value)
    props;
  Buffer.add_char buffer '}'

let rec add_node runtime buffer node =
  Buffer.add_string buffer "{\"id\":";
  add_int buffer node;
  Buffer.add_string buffer ",\"kind\":";
  Lui_wire.add_quoted buffer (Option.value (kind_name runtime node) ~default:"");
  Buffer.add_string buffer ",\"props\":";
  add_props buffer (properties runtime node);
  Buffer.add_string buffer ",\"children\":";
  add_list buffer (add_node runtime buffer)
    (List.filter (live runtime) (children runtime node));
  Buffer.add_char buffer '}'

(* Same line format as Drive's [Model.dump], so failures read alike. *)
let describe runtime node =
  let texts =
    List.filter_map
      (function
        | (("text" | "label" | "value" | "placeholder") as name),
          StringValue text ->
          Some (name ^ "=" ^ Printf.sprintf "%S" text)
        | _ -> None)
      (properties runtime node)
  in
  let count = List.length (List.filter (live runtime) (children runtime node)) in
  Printf.sprintf "#%d %s%s%s" node
    (Option.value (kind_name runtime node) ~default:"")
    (if texts = [] then "" else " " ^ String.concat " " texts)
    (if count = 0 then "" else Printf.sprintf " (%d children)" count)

let dump runtime start =
  let buffer = Buffer.create 1024 in
  let rec walk depth node =
    Buffer.add_string buffer (String.make (2 * depth) ' ');
    Buffer.add_string buffer (describe runtime node);
    Buffer.add_char buffer '\n';
    List.iter (walk (depth + 1)) (List.filter (live runtime) (children runtime node))
  in
  List.iter (walk 0) start;
  Buffer.contents buffer

(* ---------- actions ---------- *)

let supports runtime node event =
  match Hashtbl.find_opt runtime.Lui_runtime.mounted_nodes node with
  | Some kind ->
    let props =
      Option.value
        (Hashtbl.find_opt runtime.Lui_runtime.runtime_properties node)
        ~default:Property_map.empty
    in
    event_supported_for_properties kind props event
  | None -> false

(* A gesture lands on the nearest ancestor that handles it, as a host
   hit test would: [press text:Save] presses the button around the label. *)
let rec handler_for runtime make node =
  if supports runtime node (make node) then Some node
  else
    match parent runtime node with
    | Some owner when live runtime owner -> handler_for runtime make owner
    | _ -> None

let gesture target op make fields =
  let node = resolve target.runtime fields in
  match handler_for target.runtime make node with
  | Some handler -> (handler, make handler)
  | None ->
    reject
      (Printf.sprintf "#%d %s and its ancestors do not handle %s" node
         (Option.value (kind_name target.runtime node) ~default:"") op)

let direct target op event fields =
  let node = resolve target.runtime fields in
  let event = event node in
  if supports target.runtime node event then (node, event)
  else
    reject
      (Printf.sprintf "#%d %s does not handle %s" node
         (Option.value (kind_name target.runtime node) ~default:"") op)

let bool_field fields name =
  match field fields name with
  | Some (Lui_json.Bool value) -> value
  | Some (Lui_json.String ("true" | "1")) | Some (Lui_json.Int 1) -> true
  | Some (Lui_json.String ("false" | "0")) | Some (Lui_json.Int 0) -> false
  | Some _ -> reject (name ^ " must be a boolean")
  | None -> reject ("missing " ^ name)

let number_field fields name =
  match field fields name with
  | Some (Lui_json.Float value) -> value
  | Some (Lui_json.Int value) -> float_of_int value
  | Some (Lui_json.String text) -> (
    match float_of_string_opt text with
    | Some value -> value
    | None -> reject (name ^ " must be a number"))
  | Some _ -> reject (name ^ " must be a number")
  | None -> reject ("missing " ^ name)

let extension_event target node identifier name values =
  let schema =
    try Lui_runtime.require_extension_schema target.runtime node
    with Invalid_argument _ -> reject (Printf.sprintf "#%d is not an extension" node)
  in
  if schema.Lui_extension.extension_identifier <> identifier then
    reject
      (Printf.sprintf "#%d is %s, not %s" node
         schema.Lui_extension.extension_identifier identifier);
  if not (Lui_extension.event_payload_supported schema name values) then
    reject (Printf.sprintf "%s does not accept event %s with these fields" identifier name);
  (node, ExtensionEvent (node, identifier, name, values))

let key_event target fields =
  let combo = string_field fields "combo" in
  let node =
    match find target.runtime (Ext "key-surface") with
    | node :: _ -> node
    | [] -> reject "no key-surface extension is mounted"
  in
  let modifiers, key =
    match List.rev (String.split_on_char '+' combo) with
    | key :: modifiers -> (String.concat "," (List.rev modifiers), key)
    | [] -> ("", combo)
  in
  let values =
    String_map.empty
    |> String_map.add "key" (StringValue key)
    |> String_map.add "mods" (StringValue modifiers)
  in
  extension_event target node "key-surface" "key" values

let action target op fields =
  match op with
  | "press" -> gesture target op (fun node -> Press node) fields
  | "long-press" -> gesture target op (fun node -> LongPress node) fields
  | "double-press" -> gesture target op (fun node -> DoublePress node) fields
  | "submit" -> direct target op (fun node -> Submit node) fields
  | "dismiss" -> direct target op (fun node -> Dismiss node) fields
  | "appear" -> direct target op (fun node -> Appear node) fields
  | "change" -> direct target op (fun node -> Change node) fields
  | "type" ->
    let text = string_field fields "text" in
    direct target op (fun node -> TextChanged (node, text)) fields
  | "toggle" ->
    let checked = bool_field fields "value" in
    direct target op (fun node -> ToggleChanged (node, checked)) fields
  | "value" ->
    let number = number_field fields "value" in
    direct target op (fun node -> ValueChanged (node, number)) fields
  | "key" -> key_event target fields
  | "ext" ->
    let node = resolve target.runtime fields in
    let identifier = string_field fields "identifier" in
    let name = string_field fields "name" in
    let values =
      match field fields "fields" with
      | Some (Lui_json.String json) -> (
        try Lui_json.parse_values json
        with Lui_json.Parse_error message -> reject ("bad fields: " ^ message))
      | Some _ -> reject "fields must be a JSON object string"
      | None -> String_map.empty
    in
    extension_event target node identifier name values
  | op -> reject ("unknown op: " ^ op)

(* ---------- dispatch ---------- *)

let hello target buffer =
  Buffer.add_string buffer ",\"protocol\":";
  Lui_wire.add_quoted buffer protocol;
  Buffer.add_string buffer ",\"version\":";
  add_int buffer version;
  Buffer.add_string buffer ",\"host\":";
  Lui_wire.add_quoted buffer target.host;
  Buffer.add_string buffer ",\"generation\":";
  add_int buffer !(target.runtime.Lui_runtime.runtime_generation);
  Buffer.add_string buffer ",\"ops\":";
  add_list buffer (Lui_wire.add_quoted buffer) operations

let start_nodes runtime fields =
  match field fields "selector" with
  | None -> roots runtime
  | Some _ -> [ resolve runtime fields ]

let answer target op fields =
  let runtime = target.runtime in
  match op with
  | "hello" -> reply op (hello target)
  | "tree" ->
    let start = start_nodes runtime fields in
    reply op (fun buffer ->
      Buffer.add_string buffer ",\"generation\":";
      add_int buffer !(runtime.Lui_runtime.runtime_generation);
      Buffer.add_string buffer ",\"nodes\":";
      add_list buffer (add_node runtime buffer) start)
  | "dump" ->
    let text = dump runtime (start_nodes runtime fields) in
    reply op (fun buffer ->
      Buffer.add_string buffer ",\"text\":";
      Lui_wire.add_quoted buffer text)
  | "find" ->
    let _, selector = selector_field fields in
    let nodes = find runtime selector in
    reply op (fun buffer ->
      Buffer.add_string buffer ",\"nodes\":";
      add_list buffer (add_int buffer) nodes)
  | "prop" -> (
    let node = resolve runtime fields in
    let name = string_field fields "name" in
    match List.assoc_opt name (properties runtime node) with
    | Some value ->
      reply op (fun buffer ->
        Buffer.add_string buffer ",\"node\":";
        add_int buffer node;
        Buffer.add_string buffer ",\"value\":";
        Lui_wire.add_value buffer value)
    | None -> reject (Printf.sprintf "no prop %s on #%d" name node))
  | op ->
    let node, event = action target op fields in
    target.dispatch event;
    target.flush ();
    reply op (fun buffer ->
      Buffer.add_string buffer ",\"node\":";
      add_int buffer node)

let handle target request =
  match Lui_json.parse_object request with
  | exception Lui_json.Parse_error message -> failure None ("bad request: " ^ message)
  | fields -> (
    match List.assoc_opt "op" fields with
    | Some (Lui_json.String op) -> (
      target.flush ();
      try answer target op fields with Rejected message -> failure (Some op) message)
    | _ -> failure None "request has no op")
