(* JSON wire encoding of patch batches for host renderers. *)

open Lui_protocol

let add_escaped_json buffer value =
  String.iter
    (fun c ->
       match c with
       | '\\' -> Buffer.add_string buffer "\\\\"
       | '"' -> Buffer.add_string buffer "\\\""
       | '\n' -> Buffer.add_string buffer "\\n"
       | '\r' -> Buffer.add_string buffer "\\r"
       | '\t' -> Buffer.add_string buffer "\\t"
       | c when Char.code c < 0x20 ->
         let code = Char.code c in
         Buffer.add_string buffer "\\u00";
         Buffer.add_char buffer "0123456789abcdef".[code lsr 4];
         Buffer.add_char buffer "0123456789abcdef".[code land 15]
       | c -> Buffer.add_char buffer c)
    value

let escape_json value =
  let buffer = Buffer.create (String.length value + 8) in
  add_escaped_json buffer value;
  Buffer.contents buffer

let add_quoted buffer value =
  Buffer.add_char buffer '"';
  add_escaped_json buffer value;
  Buffer.add_char buffer '"'

let quoted value =
  let buffer = Buffer.create (String.length value + 8) in
  add_quoted buffer value;
  Buffer.contents buffer

let encode_value value =
  match value with
  | StringValue text -> quoted text
  | BoolValue enabled -> if enabled then "true" else "false"
  | IntValue number -> string_of_int number
  | FloatValue number ->
    (* %.17g round-trips a float64. NaN and infinities are not JSON
       numbers; callers must reject them before they reach the wire. *)
    if classify_float number <> FP_normal
       && classify_float number <> FP_subnormal
       && classify_float number <> FP_zero
    then invalid_arg "float value is not finite";
    let encoded = Printf.sprintf "%.17g" number in
    if String.contains encoded '.' || String.contains encoded 'e'
       || String.contains encoded 'E'
    then encoded
    else encoded ^ ".0"

let add_int buffer value = Buffer.add_string buffer (string_of_int value)

let add_value buffer = function
  | StringValue value -> add_quoted buffer value
  | value -> Buffer.add_string buffer (encode_value value)

let add_property buffer prefix node property =
  Buffer.add_string buffer prefix;
  add_int buffer node;
  Buffer.add_string buffer ",\"property\":";
  add_quoted buffer property

let add_op buffer = function
  | CreateNode (node, kind) ->
    Buffer.add_string buffer "{\"op\":\"create-node\",\"id\":";
    add_int buffer node;
    Buffer.add_string buffer ",\"kind\":";
    add_quoted buffer (Lui_wire_schema.node_kind_name kind);
    Buffer.add_char buffer '}'
  | CreateExtension (node, identifier, fingerprint) ->
    Buffer.add_string buffer "{\"op\":\"create-extension\",\"id\":";
    add_int buffer node;
    Buffer.add_string buffer ",\"identifier\":";
    add_quoted buffer identifier;
    Buffer.add_string buffer ",\"fingerprint\":";
    add_quoted buffer fingerprint;
    Buffer.add_char buffer '}'
  | DropNode node ->
    Buffer.add_string buffer "{\"op\":\"drop-node\",\"id\":";
    add_int buffer node;
    Buffer.add_char buffer '}'
  | DetachSubtree node ->
    Buffer.add_string buffer "{\"op\":\"detach-subtree\",\"id\":";
    add_int buffer node;
    Buffer.add_char buffer '}'
  | SetProp (node, property, value) ->
    add_property buffer "{\"op\":\"set-prop\",\"id\":" node
      (Lui_wire_schema.property_name property);
    Buffer.add_string buffer ",\"value\":";
    add_value buffer value;
    Buffer.add_char buffer '}'
  | RemoveProp (node, property) ->
    add_property buffer "{\"op\":\"remove-prop\",\"id\":" node
      (Lui_wire_schema.property_name property);
    Buffer.add_char buffer '}'
  | SetExtensionProp (node, property, value) ->
    add_property buffer "{\"op\":\"set-extension-prop\",\"id\":" node property;
    Buffer.add_string buffer ",\"value\":";
    add_value buffer value;
    Buffer.add_char buffer '}'
  | RemoveExtensionProp (node, property) ->
    add_property buffer "{\"op\":\"remove-extension-prop\",\"id\":" node property;
    Buffer.add_char buffer '}'
  | InsertChild (parent, child, index) ->
    Buffer.add_string buffer "{\"op\":\"insert-child\",\"parent\":";
    add_int buffer parent;
    Buffer.add_string buffer ",\"child\":";
    add_int buffer child;
    Buffer.add_string buffer ",\"index\":";
    add_int buffer index;
    Buffer.add_char buffer '}'
  | RemoveChild (parent, child) ->
    Buffer.add_string buffer "{\"op\":\"remove-child\",\"parent\":";
    add_int buffer parent;
    Buffer.add_string buffer ",\"child\":";
    add_int buffer child;
    Buffer.add_char buffer '}'
  | MoveChild (parent, child, index) ->
    Buffer.add_string buffer "{\"op\":\"move-child\",\"parent\":";
    add_int buffer parent;
    Buffer.add_string buffer ",\"child\":";
    add_int buffer child;
    Buffer.add_string buffer ",\"index\":";
    add_int buffer index;
    Buffer.add_char buffer '}'

let encode_op operation =
  let buffer = Buffer.create 128 in
  add_op buffer operation;
  Buffer.contents buffer

let add_ops buffer operations =
  List.iteri (fun index operation ->
    if index <> 0 then Buffer.add_char buffer ',';
    add_op buffer operation) operations

let encode_ops operations =
  let buffer = Buffer.create 256 in
  add_ops buffer operations;
  Buffer.contents buffer

let encode_batch batch =
  (* One growing buffer avoids retaining a JSON string for every operation
     alongside another complete operations string and the final batch. *)
  let buffer = Buffer.create 256 in
  Buffer.add_string buffer "{\"generation\":";
  add_int buffer batch.generation;
  Buffer.add_string buffer ",\"ops\":[";
  add_ops buffer batch.ops;
  Buffer.add_string buffer "]}";
  Buffer.contents buffer

(* ---------- decoding ----------

   The wire format exists so a batch can cross a process/language
   boundary (SwiftUI, Kotlin, Web, the dylib test driver); OCaml-side
   hosts never had to read it back, so no decoder lived in the library.
   [decode_batch] is the inverse of [encode_batch]: it lets a
   same-runtime wire backend — tests, remote-replay tooling — consume
   the exact bytes a foreign host would see, which is what makes
   backend parity checkable on this side of the seam. *)

let dfail message = raise (Lui_json.Parse_error message)

type dcursor = { d_src : string; mutable d_pos : int }

let d_len c = String.length c.d_src

let d_ws c = c.d_pos <- Lui_json.skip_space c.d_src c.d_pos

let d_peek c =
  d_ws c;
  if c.d_pos < d_len c then c.d_src.[c.d_pos] else '\000'

let d_expect_char c ch =
  if d_peek c <> ch then dfail (Printf.sprintf "expected %C" ch);
  c.d_pos <- c.d_pos + 1

let d_string c =
  if d_peek c <> '"' then dfail "expected string";
  let text, next = Lui_json.parse_string c.d_src (c.d_pos + 1) in
  c.d_pos <- next;
  text

let d_lexeme c =
  d_ws c;
  let text, next = Lui_json.parse_number c.d_src c.d_pos in
  if next = c.d_pos then dfail "expected number";
  c.d_pos <- next;
  text

(* Scalar field value: string, bool, or the raw number lexeme (int vs
   float is decided by the syntax the encoder chose — a FloatValue is
   always emitted with '.'/'e', an IntValue never is). *)
type d_value =
  | DString of string
  | DBool of bool
  | DNum of string

let d_value c =
  match d_peek c with
  | '"' -> DString (d_string c)
  | 't' -> c.d_pos <- Lui_json.expect c.d_src c.d_pos "true"; DBool true
  | 'f' -> c.d_pos <- Lui_json.expect c.d_src c.d_pos "false"; DBool false
  | '-' | '0' .. '9' -> DNum (d_lexeme c)
  | _ -> dfail "unsupported value kind"

let d_sep_or_end c close =
  match d_peek c with
  | ',' -> c.d_pos <- c.d_pos + 1; `More
  | ch when ch = close -> c.d_pos <- c.d_pos + 1; `Done
  | _ -> dfail (Printf.sprintf "expected ',' or %C" close)

(* One op object into a (name, scalar) assoc. Op objects never nest —
   the only array/object in the format is the batch's own ops list. *)
let d_fields c =
  d_expect_char c '{';
  let rec loop acc =
    match d_peek c with
    | '}' -> c.d_pos <- c.d_pos + 1; List.rev acc
    | '"' ->
      let name = d_string c in
      d_expect_char c ':';
      let value = d_value c in
      let acc = (name, value) :: acc in
      (match d_sep_or_end c '}' with
      | `More -> loop acc
      | `Done -> List.rev acc)
    | _ -> dfail "expected object field"
  in
  loop []

(* name -> variant tables, built once: [List.find_opt] over
   all_properties costs O(#properties) per op, which is the wrong way to
   spend a big mount batch. *)
let decode_tables =
  lazy
    (let kinds = Hashtbl.create 128 in
     List.iter
       (fun k -> Hashtbl.replace kinds (Lui_wire_schema.node_kind_name k) k)
       Lui_wire_schema.all_node_kinds;
     let properties = Hashtbl.create 512 in
     List.iter
       (fun p ->
         Hashtbl.replace properties (Lui_wire_schema.property_name p) p)
       Lui_wire_schema.all_properties;
     (kinds, properties))

let kind_of_name name =
  match Hashtbl.find_opt (fst (Lazy.force decode_tables)) name with
  | Some kind -> kind
  | None -> dfail ("unknown node kind " ^ name)

let property_of_name name =
  match Hashtbl.find_opt (snd (Lazy.force decode_tables)) name with
  | Some property -> property
  | None -> dfail ("unknown property " ^ name)

let field_opt name fields =
  match List.find_opt (fun (k, _) -> k = name) fields with
  | Some (_, value) -> Some value
  | None -> None

let field name fields =
  match field_opt name fields with
  | Some value -> value
  | None -> dfail ("missing field " ^ name)

let f_str name fields =
  match field name fields with
  | DString s -> s
  | _ -> dfail ("field " ^ name ^ " must be a string")

let f_int name fields =
  match field name fields with
  | DNum text -> (
    match int_of_string_opt text with
    | Some value -> value
    | None -> dfail ("field " ^ name ^ " must be an integer"))
  | _ -> dfail ("field " ^ name ^ " must be a number")

let wire_of_field = function
  | DString s -> StringValue s
  | DBool b -> BoolValue b
  | DNum text ->
    let float_syntax =
      String.exists
        (fun ch -> ch = '.' || ch = 'e' || ch = 'E' || ch = '+')
        text
    in
    if float_syntax then
      match float_of_string_opt text with
      | Some f -> FloatValue f
      | None -> dfail ("invalid float " ^ text)
    else
      match int_of_string_opt text with
      | Some i -> IntValue i
      | None -> dfail ("invalid int " ^ text)

let op_of_fields fields =
  match f_str "op" fields with
  | "create-node" ->
    CreateNode (f_int "id" fields, kind_of_name (f_str "kind" fields))
  | "create-extension" ->
    CreateExtension
      ( f_int "id" fields,
        f_str "identifier" fields,
        f_str "fingerprint" fields )
  | "drop-node" -> DropNode (f_int "id" fields)
  | "detach-subtree" -> DetachSubtree (f_int "id" fields)
  | "set-prop" ->
    SetProp
      ( f_int "id" fields,
        property_of_name (f_str "property" fields),
        wire_of_field (field "value" fields) )
  | "remove-prop" ->
    RemoveProp (f_int "id" fields, property_of_name (f_str "property" fields))
  | "set-extension-prop" ->
    SetExtensionProp
      ( f_int "id" fields,
        f_str "property" fields,
        wire_of_field (field "value" fields) )
  | "remove-extension-prop" ->
    RemoveExtensionProp (f_int "id" fields, f_str "property" fields)
  | "insert-child" ->
    InsertChild
      (f_int "parent" fields, f_int "child" fields, f_int "index" fields)
  | "remove-child" ->
    RemoveChild (f_int "parent" fields, f_int "child" fields)
  | "move-child" ->
    MoveChild
      (f_int "parent" fields, f_int "child" fields, f_int "index" fields)
  | op -> dfail ("unknown patch op " ^ op)

let decode_batch source =
  let c = { d_src = source; d_pos = 0 } in
  let generation = ref 0 in
  let ops = ref [] in
  let read_ops () =
    d_expect_char c '[';
    let rec loop acc =
      match d_peek c with
      | ']' -> c.d_pos <- c.d_pos + 1; List.rev acc
      | '{' ->
        let op = op_of_fields (d_fields c) in
        let acc = op :: acc in
        (match d_sep_or_end c ']' with
        | `More -> loop acc
        | `Done -> List.rev acc)
      | _ -> dfail "expected patch op object"
    in
    loop []
  in
  d_expect_char c '{';
  let rec fields () =
    match d_peek c with
    | '}' -> c.d_pos <- c.d_pos + 1
    | '"' ->
      let name = d_string c in
      d_expect_char c ':';
      (match name, d_peek c with
      | "ops", '[' -> ops := read_ops ()
      | "ops", _ -> dfail "\"ops\" must be an array"
      | "generation", _ -> (
        match d_value c with
        | DNum text -> (
          match int_of_string_opt text with
          | Some g -> generation := g
          | None -> dfail "generation must be an integer")
        | _ -> dfail "generation must be a number")
      (* Forward compatibility: a newer encoder's extra fields are
         skipped, like a foreign host's JSON layer would. *)
      | _, _ -> ignore (d_value c));
      (match d_sep_or_end c '}' with
      | `More -> fields ()
      | `Done -> ())
    | _ -> dfail "expected batch field"
  in
  fields ();
  if d_peek c <> '\000' then dfail "trailing content after batch";
  { generation = !generation; ops = !ops }

(* The transport choice at the backend seam: [In_process] hands the
   batch over as the value it already is (the fast path a same-process
   native backend takes); [Wire] pays the full encode -> decode a
   foreign/remote host pays, keeping that path exercisable for parity. *)
type transport =
  | In_process
  | Wire

let transcode transport batch =
  match transport with
  | In_process -> batch
  | Wire -> decode_batch (encode_batch batch)
