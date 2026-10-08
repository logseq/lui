(* JSON wire encoding of patch batches for host renderers. *)

open Lui_protocol

let escape_json value =
  let buffer = Buffer.create (String.length value + 8) in
  String.iter
    (fun c ->
       match c with
       | '\\' -> Buffer.add_string buffer "\\\\"
       | '"' -> Buffer.add_string buffer "\\\""
       | '\n' -> Buffer.add_string buffer "\\n"
       | '\r' -> Buffer.add_string buffer "\\r"
       | '\t' -> Buffer.add_string buffer "\\t"
       | c when Char.code c < 0x20 ->
         (* JSON requires every remaining control character (NUL, form
            feed, ...) to be escaped; emitting it raw makes the whole
            batch undecodable on the host. *)
         Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))
       | c -> Buffer.add_char buffer c)
    value;
  Buffer.contents buffer

let quoted value = "\"" ^ escape_json value ^ "\""

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

let encode_op operation =
  match operation with
  | CreateNode (node, kind) ->
    Printf.sprintf "{\"op\":\"create-node\",\"id\":%d,\"kind\":%s}" node
      (quoted (Lui_wire_schema.node_kind_name kind))
  | CreateExtension (node, identifier, fingerprint) ->
    Printf.sprintf "{\"op\":\"create-extension\",\"id\":%d,\"identifier\":%s,\"fingerprint\":%s}"
      node (quoted identifier) (quoted fingerprint)
  | DropNode node -> Printf.sprintf "{\"op\":\"drop-node\",\"id\":%d}" node
  | DetachSubtree node ->
    Printf.sprintf "{\"op\":\"detach-subtree\",\"id\":%d}" node
  | SetProp (node, property, value) ->
    Printf.sprintf "{\"op\":\"set-prop\",\"id\":%d,\"property\":%s,\"value\":%s}"
      node
      (quoted (Lui_wire_schema.property_name property))
      (encode_value value)
  | RemoveProp (node, property) ->
    Printf.sprintf "{\"op\":\"remove-prop\",\"id\":%d,\"property\":%s}" node
      (quoted (Lui_wire_schema.property_name property))
  | SetExtensionProp (node, property, value) ->
    Printf.sprintf
      "{\"op\":\"set-extension-prop\",\"id\":%d,\"property\":%s,\"value\":%s}"
      node (quoted property) (encode_value value)
  | RemoveExtensionProp (node, property) ->
    Printf.sprintf
      "{\"op\":\"remove-extension-prop\",\"id\":%d,\"property\":%s}" node
      (quoted property)
  | InsertChild (parent, child, index) ->
    Printf.sprintf
      "{\"op\":\"insert-child\",\"parent\":%d,\"child\":%d,\"index\":%d}" parent
      child index
  | RemoveChild (parent, child) ->
    Printf.sprintf "{\"op\":\"remove-child\",\"parent\":%d,\"child\":%d}" parent
      child
  | MoveChild (parent, child, index) ->
    Printf.sprintf
      "{\"op\":\"move-child\",\"parent\":%d,\"child\":%d,\"index\":%d}" parent
      child index

let encode_ops operations =
  String.concat "," (List.map encode_op operations)

let encode_batch batch =
  Printf.sprintf "{\"generation\":%d,\"ops\":[%s]}" batch.generation
    (encode_ops batch.ops)
