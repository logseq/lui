(* Exact integer JSON for the shared viewport contract. No float conversion. *)
type t = String of string | Int of int | Array of t list | Object of (string * t) list

let fail () = invalid_arg "invalid shared virtual JSON"

let decode text =
  let length = String.length text in
  let rec value depth index =
    if depth > 64 || index >= length then fail ();
    match text.[index] with
    | '"' ->
      let result, next = Lui_json.parse_string text (index + 1) in
      String result, next
    | '[' -> sequence (depth + 1) (index + 1) ']' (fun xs -> Array xs)
    | '{' -> fields (depth + 1) (index + 1) []
    | '0' .. '9' ->
      let finish = ref index in
      while !finish < length && text.[!finish] >= '0' && text.[!finish] <= '9' do
        incr finish
      done;
      let literal = String.sub text index (!finish - index) in
      (match int_of_string_opt literal with
       | Some number when string_of_int number = literal -> Int number, !finish
       | _ -> fail ())
    | _ -> fail ()
  and sequence depth index closing make =
    if index < length && text.[index] = closing then make [], index + 1
    else
      let rec loop index result =
        let item, next = value depth index in
        if next >= length then fail ();
        if text.[next] = closing then make (List.rev (item :: result)), next + 1
        else if text.[next] = ',' then loop (next + 1) (item :: result)
        else fail ()
      in loop index []
  and fields depth index result =
    if index < length && text.[index] = '}' && result = [] then Object [], index + 1
    else begin
      if index >= length || text.[index] <> '"' then fail ();
      let name, next = Lui_json.parse_string text (index + 1) in
      if List.mem_assoc name result || next >= length || text.[next] <> ':' then fail ();
      let item, next = value depth (next + 1) in
      if next >= length then fail ();
      let result = (name, item) :: result in
      if text.[next] = '}' then Object (List.rev result), next + 1
      else if text.[next] = ',' then fields depth (next + 1) result
      else fail ()
    end
  in
  try
    let result, next = value 0 0 in
    if next <> length then fail ();
    result
  with Lui_json.Parse_error _ -> fail ()

let encode value =
  let buffer = Buffer.create 128 in
  let rec add = function
    | String text -> Lui_wire.add_quoted buffer text
    | Int number -> Buffer.add_string buffer (string_of_int number)
    | Array items ->
      Buffer.add_char buffer '[';
      List.iteri (fun index item -> if index > 0 then Buffer.add_char buffer ','; add item) items;
      Buffer.add_char buffer ']'
    | Object fields ->
      Buffer.add_char buffer '{';
      List.iteri (fun index (name, item) ->
        if index > 0 then Buffer.add_char buffer ',';
        Lui_wire.add_quoted buffer name; Buffer.add_char buffer ':'; add item) fields;
      Buffer.add_char buffer '}'
  in add value; Buffer.contents buffer

let string = function String value -> value | _ -> fail ()
let positive = function Int value when value > 0 -> value | _ -> fail ()
let array = function Array values -> values | _ -> fail ()
let object_ names = function
  | Object fields when List.sort String.compare (List.map fst fields)
      = List.sort String.compare names -> fields
  | _ -> fail ()
let strings values = List.map string (array values)
let nonempty text = if text = "" then fail () else text
let vector text =
  let values = strings (decode text) in
  let seen = Hashtbl.create (List.length values) in
  List.iter (fun value ->
    ignore (nonempty value);
    if Hashtbl.mem seen value then fail ();
    Hashtbl.add seen value ()) values;
  values
let encode_strings values = encode (Array (List.map (fun value -> String value) values))
