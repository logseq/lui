type id = string

type kind =
  | User
  | Assistant
  | Thinking
  | Tool_call
  | Notice
  | Host of string

type delivery = [ `sent | `pending | `uncertain ]
type attachment_status = [ `uploading | `ready | `failed ]

type attachment = {
  attachment_id : id;
  name : string;
  media_type : string;
  size : int option;
  status : attachment_status;
  path : string option;
  url : string option;
}

type tool_status =
  [ `pending | `in_progress | `completed | `failed | `unknown ]

type tool_call = {
  call_id : id;
  title : string;
  tool_kind : string;
  status : tool_status;
  input : string option;
  output : string option;
  output_truncated : bool;
}

type item = {
  id : id;
  kind : kind;
  text : string;
  streaming : bool;
  delivery : delivery;
  attachments : attachment list;
  tool : tool_call option;
  payload : string option;
  truncated : bool;
}

let item id kind = {
  id;
  kind;
  text = "";
  streaming = false;
  delivery = `sent;
  attachments = [];
  tool = None;
  payload = None;
  truncated = false;
}

let find items id = List.find_opt (fun (i : item) -> i.id = id) items

let upsert items it =
  let rec go acc = function
    | [] -> List.rev_append acc [ it ]
    | (x : item) :: tl ->
        if x.id = it.id then List.rev_append acc (it :: tl)
        else go (x :: acc) tl
  in
  go [] items

let append_text items id delta =
  List.map
    (fun (i : item) ->
      if i.id = id then { i with text = i.text ^ delta } else i)
    items

let set_delivery items id delivery =
  List.map
    (fun (i : item) -> if i.id = id then { i with delivery } else i)
    items

type tool_update = {
  update_id : id;
  update_title : string option;
  update_kind : string option;
  update_status : tool_status option;
  update_input : string option;
  update_output : string option;
  update_output_truncated : bool option;
}

let merge_opt old upd = match upd with Some _ -> upd | None -> old

let merge_tool (call : tool_call) (u : tool_update) : tool_call = {
  call_id = call.call_id;
  title = Option.value u.update_title ~default:call.title;
  tool_kind = Option.value u.update_kind ~default:call.tool_kind;
  status = Option.value u.update_status ~default:call.status;
  input = merge_opt call.input u.update_input;
  output = merge_opt call.output u.update_output;
  output_truncated =
    Option.value u.update_output_truncated ~default:call.output_truncated;
}

let update_tool items (u : tool_update) =
  List.map
    (fun (i : item) ->
      match i.tool with
      | Some call when call.call_id = u.update_id ->
          { i with tool = Some (merge_tool call u) }
      | _ -> i)
    items

type row =
  | Single of item
  | Tool_group of item list

let group_rows ~group items =
  if not group then List.map (fun i -> Single i) items
  else
    let close acc run =
      match run with [] -> acc | _ -> Tool_group (List.rev run) :: acc
    in
    let rec go acc run = function
      | [] -> List.rev (close acc run)
      | (i : item) :: tl ->
          if i.kind = Tool_call then go acc (i :: run) tl
          else go (Single i :: close acc run) [] tl
    in
    go [] [] items

(* Group identity keys: the first member id survives run growth. *)
let row_key = function
  | Single i -> i.id
  | Tool_group (i :: _) -> "tools:" ^ i.id
  | Tool_group [] -> "tools:empty"

let tool_active (call : tool_call) =
  call.status = `pending || call.status = `in_progress

let group_active items =
  List.exists
    (fun (i : item) -> match i.tool with Some c -> tool_active c | None -> false)
    items

let tool_status_label = function
  | `pending -> "Pending"
  | `in_progress -> "Running"
  | `completed -> "Done"
  | `failed -> "Failed"
  | `unknown -> "Unknown"

let is_image (a : attachment) =
  String.starts_with ~prefix:"image/" (String.lowercase_ascii a.media_type)

let size_label bytes =
  if bytes < 1024 then Printf.sprintf "%d B" bytes
  else if bytes < 1024 * 1024 then Printf.sprintf "%.0f KB" (Float.of_int bytes /. 1024.)
  else Printf.sprintf "%.1f MB" (Float.of_int bytes /. (1024. *. 1024.))
