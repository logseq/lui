(* Minimal JSON decoder for host bridge payloads.

   Host→OCaml extension events carry a flat JSON object whose values are
   scalars (strings, booleans, numbers). That is all the bridge needs: the
   runtime validates the decoded map against the declared extension event
   schema, so richer structures are rejected there anyway. *)

open Lui_protocol

type t =
  | String of string
  | Bool of bool
  | Int of int
  | Float of float

exception Parse_error of string

let fail message = raise (Parse_error message)

let is_space = function
  | ' ' | '\t' | '\n' | '\r' -> true
  | _ -> false

(* Decode \uXXXX escapes (including surrogate pairs) to UTF-8 bytes. *)
let utf8_of_codepoint buffer code =
  if code < 0x80 then Buffer.add_char buffer (Char.chr code)
  else if code < 0x800 then begin
    Buffer.add_char buffer (Char.chr (0xC0 lor (code lsr 6)));
    Buffer.add_char buffer (Char.chr (0x80 lor (code land 0x3F)))
  end
  else if code < 0x10000 then begin
    Buffer.add_char buffer (Char.chr (0xE0 lor (code lsr 12)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
    Buffer.add_char buffer (Char.chr (0x80 lor (code land 0x3F)))
  end
  else begin
    Buffer.add_char buffer (Char.chr (0xF0 lor (code lsr 18)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((code lsr 12) land 0x3F)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
    Buffer.add_char buffer (Char.chr (0x80 lor (code land 0x3F)))
  end

let hex_value c =
  match c with
  | '0' .. '9' -> Char.code c - Char.code '0'
  | 'a' .. 'f' -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' -> Char.code c - Char.code 'A' + 10
  | _ -> fail "invalid unicode escape"

let parse_hex4 source index =
  if index + 4 > String.length source then fail "truncated unicode escape";
  let value = ref 0 in
  for i = 0 to 3 do
    value := (!value lsl 4) lor hex_value source.[index + i]
  done;
  !value

let parse_string source index =
  let buffer = Buffer.create 16 in
  let rec loop index =
    if index >= String.length source then fail "unterminated string";
    match source.[index] with
    | '"' -> (Buffer.contents buffer, index + 1)
    | '\\' ->
      if index + 1 >= String.length source then fail "unterminated escape";
      (match source.[index + 1] with
       | '"' -> Buffer.add_char buffer '"'; loop (index + 2)
       | '\\' -> Buffer.add_char buffer '\\'; loop (index + 2)
       | '/' -> Buffer.add_char buffer '/'; loop (index + 2)
       | 'b' -> Buffer.add_char buffer '\b'; loop (index + 2)
       | 'f' -> Buffer.add_char buffer '\012'; loop (index + 2)
       | 'n' -> Buffer.add_char buffer '\n'; loop (index + 2)
       | 'r' -> Buffer.add_char buffer '\r'; loop (index + 2)
       | 't' -> Buffer.add_char buffer '\t'; loop (index + 2)
       | 'u' ->
         let code = parse_hex4 source (index + 2) in
         if code >= 0xD800 && code <= 0xDBFF then begin
           (* High surrogate: a low surrogate escape must follow. *)
           if index + 7 >= String.length source
              || source.[index + 6] <> '\\' || source.[index + 7] <> 'u'
           then fail "unpaired surrogate escape";
           let low = parse_hex4 source (index + 8) in
           if low < 0xDC00 || low > 0xDFFF then
             fail "invalid surrogate pair";
           let combined =
             0x10000 + ((code - 0xD800) lsl 10) + (low - 0xDC00)
           in
           utf8_of_codepoint buffer combined;
           loop (index + 12)
         end
         else begin
           utf8_of_codepoint buffer code;
           loop (index + 6)
         end
       | _ -> fail "invalid escape")
    | c -> Buffer.add_char buffer c; loop (index + 1)
  in
  loop index

let parse_number source index =
  let start = index in
  let rec scan index =
    if index < String.length source then
      match source.[index] with
      | '0' .. '9' | '-' | '+' | '.' | 'e' | 'E' -> scan (index + 1)
      | _ -> index
    else index
  in
  let finish = scan index in
  let text = String.sub source start (finish - start) in
  (match float_of_string_opt text with
   | Some number -> (number, finish)
   | None -> fail "invalid number")

let skip_space source index =
  let rec loop index =
    if index < String.length source && is_space source.[index] then
      loop (index + 1)
    else index
  in
  loop index

let expect source index chars =
  let rec loop offset =
    if offset >= String.length chars then index + offset
    else if index + offset >= String.length source
         || source.[index + offset] <> chars.[offset]
    then fail ("expected " ^ chars)
    else loop (offset + 1)
  in
  loop 0

let parse_value source index =
  let index = skip_space source index in
  if index >= String.length source then fail "truncated value";
  match source.[index] with
  | '"' ->
    let text, next = parse_string source (index + 1) in
    (String text, next)
  | 't' -> (Bool true, expect source index "true")
  | 'f' -> (Bool false, expect source index "false")
  | 'n' -> (Float 0.0, expect source index "null")
  | '-' | '0' .. '9' ->
    let number, next = parse_number source index in
    let truncated = Float.trunc number in
    if number = truncated && Float.abs number < 4611686018427387904.0 then
      (Int (int_of_float truncated), next)
    else (Float number, next)
  | _ -> fail "unsupported value kind"

(* Parse a single-level object of scalar values. Objects and arrays are
   intentionally unsupported: extension event payloads are flat by design. *)
let parse_object source =
  let index = skip_space source 0 in
  if index >= String.length source || source.[index] <> '{' then
    fail "expected object";
  let rec loop index fields =
    let index = skip_space source index in
    if index >= String.length source then fail "unterminated object";
    match source.[index] with
    | '}' -> (fields, index + 1)
    | '"' ->
      let name, next = parse_string source (index + 1) in
      let next = skip_space source next in
      if next >= String.length source || source.[next] <> ':' then
        fail "expected colon";
      let value, next = parse_value source (next + 1) in
      let next = skip_space source next in
      if next < String.length source && source.[next] = ',' then
        loop (next + 1) ((name, value) :: fields)
      else if next < String.length source && source.[next] = '}' then
        ((name, value) :: fields, next + 1)
      else fail "expected comma or closing brace"
    | _ -> fail "expected object field"
  in
  let fields, next = loop (index + 1) [] in
  let next = skip_space source next in
  if next < String.length source then fail "trailing content";
  fields

let wire_value = function
  | String text -> StringValue text
  | Bool value -> BoolValue value
  | Int value -> IntValue value
  | Float value -> FloatValue value

let parse_values source =
  let trimmed = String.trim source in
  if trimmed = "" || trimmed = "{}" then String_map.empty
  else
    List.fold_left
      (fun values (name, value) ->
         String_map.add name (wire_value value) values)
      String_map.empty (parse_object trimmed)
