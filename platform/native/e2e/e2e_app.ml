(* Tiny list app for the headless e2e driver: a summary text, a text
   field, an "add" button, and a keyed list of item rows each carrying
   delete and promote buttons. Dispatching its events exercises
   create/insert/remove/move patch ops through real user actions. *)

open Lui_elements

type model = { items : string list; draft : string }

type action =
  | Draft of string
  | Add
  | Remove of string
  | Promote of string

let initial = { items = [ "alpha"; "beta" ]; draft = "" }

let update model action =
  match action with
  | Draft draft -> { model with draft }
  | Add ->
    if model.draft = "" then model
    else { items = model.items @ [ model.draft ]; draft = "" }
  | Remove it ->
    { model with items = List.filter (fun s -> s <> it) model.items }
  | Promote it ->
    { model with items = it :: List.filter (fun s -> s <> it) model.items }

let item_row send item_s =
  let item = sample item_s in
  row ~gap:4
    [ text ~value:(reactive (fun v -> "item:" ^ v) item_s) []
    ; button ~text:(reactive (fun v -> "x-" ^ v) item_s)
        ~on_press:(press send (Remove item)) []
    ; button ~text:(reactive (fun v -> "^-" ^ v) item_s)
        ~on_press:(press send (Promote item)) []
    ]

let view _ctx model_s send : t =
  column ~gap:4 ~padding:8
    [ text
        ~value:(reactive (fun m ->
            Printf.sprintf "items=%d draft=%s"
              (List.length m.items) m.draft) model_s)
        []
    ; text_field
        ~text:(reactive (fun m -> m.draft) model_s)
        ~placeholder:"new item" ~label:"New item"
        ~on_input:(on_input send (fun s -> Draft s))
        ~on_submit:(press send Add)
        []
    ; button ~text:"add" ~background:"#3366ff"
        ~on_press:(press send Add) []
    ; keyed
        ~source:(map (fun m -> m.items) model_s)
        ~key:(fun s -> s) ~cmp:String.compare
        ~mount:(item_row send)
    ]
