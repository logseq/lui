type file = { path : string; name : string; content_type : string }

type t = {
  request : Lui_elements.file_picker_token;
  files : file list;
  failures : int;
}

type json =
  | Scalar of Lui_json.t
  | Object of (string * json) list
  | Array of json list
  | Null

let decode source =
  let length = String.length source in
  let rec space index =
    if index < length && Lui_json.is_space source.[index] then space (index + 1)
    else index
  in
  let expect index char =
    let index = space index in
    if index >= length || source.[index] <> char then
      Lui_json.fail "Invalid JSON";
    index + 1
  in
  let rec value depth index =
    if depth > 32 then Lui_json.fail "File-picker result is too deeply nested";
    let index = space index in
    if index >= length then Lui_json.fail "Truncated JSON";
    match source.[index] with
    | '{' ->
        let field index =
          let index = expect index '"' in
          let name, next = Lui_json.parse_string source index in
          let item, next = value (depth + 1) (expect next ':') in
          ((name, item), next)
        in
        let fields, next = sequence field '}' (index + 1) in
        (Object fields, next)
    | '[' ->
        let items, next = sequence (value (depth + 1)) ']' (index + 1) in
        (Array items, next)
    | 'n' when index + 4 <= length && String.sub source index 4 = "null" ->
        (Null, index + 4)
    | _ ->
        let scalar, next = Lui_json.parse_value source index in
        (Scalar scalar, next)
  and sequence : 'a. (int -> 'a * int) -> char -> int -> 'a list * int =
   fun item close index ->
    let index = space index in
    if index < length && source.[index] = close then ([], index + 1)
    else
      let rec loop rev index =
        let element, next = item index in
        let next = space next in
        if next >= length then Lui_json.fail "Truncated JSON";
        match source.[next] with
        | ',' -> loop (element :: rev) (space (next + 1))
        | c when c = close -> (List.rev (element :: rev), next + 1)
        | _ -> Lui_json.fail "Invalid JSON separator"
      in
      loop [] index
  in
  let string fields name =
    match List.assoc_opt name fields with
    | Some (Scalar (Lui_json.String text)) -> Some text
    | _ -> None
  in
  let file = function
    | Object fields -> (
        match string fields "path" with
        | Some path when String.trim path <> "" ->
            Some
              {
                path;
                name =
                  Option.value (string fields "name")
                    ~default:(Filename.basename path);
                content_type =
                  Option.value
                    (string fields "content-type")
                    ~default:"application/octet-stream";
              }
        | _ -> None)
    | _ -> None
  in
  try
    let result, next = value 0 0 in
    if space next <> length then Lui_json.fail "Trailing JSON";
    match result with
    | Object fields ->
        let request =
          match List.assoc_opt "request" fields with
          | Some (Scalar (Lui_json.String token)) -> `String token
          | Some (Scalar (Lui_json.Int token)) -> `Int token
          | _ -> Lui_json.fail "Missing file-picker request"
        in
        let entries =
          match List.assoc_opt "files" fields with
          | Some (Array entries) -> entries
          | _ -> Lui_json.fail "Missing file-picker files"
        in
        let initial_failures =
          match List.assoc_opt "failures" fields with
          | Some (Scalar (Lui_json.Int count)) when count >= 0 -> count
          | _ -> 0
        in
        let rev, failures =
          List.fold_left
            (fun (rev, failures) entry ->
              match file entry with
              | Some file -> (file :: rev, failures)
              | None -> (rev, failures + 1))
            ([], initial_failures) entries
        in
        Ok { request; files = List.rev rev; failures }
    | _ -> Error "Invalid file-picker result"
  with Lui_json.Parse_error message -> Error message
