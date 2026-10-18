open Lui_ai.Model

type t = {
  items : item list;
  draft : string;
  generating : bool;
  queued : string list;
  next_id : int;
}

type action = Input of string | Send | Stop | Tick

let user id text = { (item id User) with text }
let assistant id text = { (item id Assistant) with text }

let tool_call id title status input output : tool_call =
  { call_id = id; title; tool_kind = "demo"; status;
    input = Some input; output; output_truncated = false }

let seed_items = [
  user "s1" "How do I stream chat updates in LUI?";
  item "s2" Tool_call;
  assistant "s4" "Keyed rows keep one message a single mounted item while chunks arrive.";
]

let seed_items =
  let with_tool =
    List.map (fun i -> if i.id = "s2" then
        { i with tool = Some (tool_call "s2" "search docs" `completed
            "{\"q\":\"lui keyed streaming\"}" (Some "lui_elements.keyed keeps row identity")) }
      else i) seed_items in
  with_tool @ [ assistant "s5" "" ]

let initial =
  { items =
      List.filter (fun i -> i.id <> "s5") seed_items
      @ [ { (assistant "s5" "") with streaming = true } ];
    draft = ""; generating = true;
    queued =
      [ "Welcome to the lui-ai demo. ";
        "This message streams chunk by chunk into one keyed row; ";
        "send a message below to stream a scripted reply." ];
    next_id = 0 }

let scripted_reply n =
  [ "Streaming reply " ^ string_of_int n ^ ": keyed rendering keeps ";
    "this logical message as one row while chunks arrive. ";
    "Scrolling up unpins the transcript; the jump button returns to the latest." ]

let update m = function
  | Input draft -> { m with draft }
  | Stop ->
      let items =
        List.map (fun (i : item) -> { i with streaming = false }) m.items in
      { m with items; generating = false; queued = [] }
  | Send ->
      if String.trim m.draft = "" || m.generating then m
      else
        let n = m.next_id in
        let uid = Printf.sprintf "u%d" n and aid = Printf.sprintf "a%d" n in
        let items =
          upsert
            (upsert m.items (user uid m.draft))
            { (assistant aid "") with streaming = true } in
        { items; draft = ""; generating = true;
          queued = scripted_reply n; next_id = n + 1 }
  | Tick ->
      (match m.queued with
       | [] -> m
       | chunk :: rest ->
           let last =
             match List.rev m.items with i :: _ -> Some i | [] -> None in
           (match last with
            | Some i when i.streaming ->
                let items = append_text m.items i.id chunk in
                let items =
                  if rest = [] then
                    List.map (fun (x : item) -> { x with streaming = false }) items
                  else items in
                { m with items; queued = rest; generating = rest <> [] }
            | _ -> { m with queued = rest }))

let items m = m.items
let draft m = m.draft
let generating m = m.generating
