(* Todo list view: plain OCaml calls to the Lui_elements DSL —
   constructors take ~props then a positional children list: row ~gap:4 [ .. ].
   every prop has a `~p` static and `~p_signal` reactive twin — inside
   `map`/`sample` ordinary values and if/match all work. `dyn`, `if_` and
   `keyed` cover structural changes (different element kinds, show/hide,
   identity-keyed lists). *)

open Lui_protocol
open Lui_elements

let content_padding = function
  | MacOS -> 24
  | IOS -> 20
  | AndroidOS | WebOS -> 16
  | _ -> 16

let content_gap = function
  | MacOS -> 14
  | IOS | AndroidOS -> 12
  | _ -> 12

let summary_label (model : Model.t) =
  let remaining =
    List.length (List.filter (fun (item : Model.todo) -> not item.done_) model.items)
  in
  Printf.sprintf "%d remaining / %d total" remaining
    (List.length model.items)

let todo_row send item_source : t =
  let item = sample item_source in
  row ~gap:8
    [ text
        ~value:(reactive (fun (i : Model.todo) ->
           (if i.done_ then "[x] " else "[ ] ") ^ i.title) item_source)
        []
    ; button
        ~text:(reactive (fun (i : Model.todo) ->
           if i.done_ then "Undo" else "Done") item_source)
        ~on_press:(press send (Model.ToggleTodo item.id))
        []
    ; button ~text:"Up" ~on_press:(press send (Model.MoveTodoUp item.id)) []
    ; button ~text:"Delete" ~on_press:(press send (Model.DeleteTodo item.id)) []
    ]

let item_list model_source send : t =
  keyed
    ~source:(map Model.items model_source)
    ~key:(fun (i : Model.todo) -> i.id)
    ~compare
    ~mount:(todo_row send)

let view context model_source send : t =
  let platform = Lui_ui.platform context in
  (column ~gap:(content_gap platform) ~padding:(content_padding platform)
     [ text ~value:"Todos" []
     ; row ~gap:8
         [ text_field
             ~text:(reactive Model.draft model_source)
             ~placeholder:"What needs to be done?" ~label:"New todo"
             ~on_input:(on_input send Model.change_draft)
             ~on_submit:(press send Model.AddTodo)
             []
         ; button ~text:"Add"
             ~on_press:(press send Model.AddTodo)
             []
         ]
     ; textarea
         ~text:(reactive Model.notes model_source)
         ~placeholder:"Notes" ~label:"Todo notes"
         ~on_input:(on_input send Model.change_notes)
         []
     ; scroll [ column ~gap:8 [ item_list model_source send ] ]
     ; text ~value:(reactive summary_label model_source) []
     ])
