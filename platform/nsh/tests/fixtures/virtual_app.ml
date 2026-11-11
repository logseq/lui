(* A real OCaml application for qualification of the desktop sparse-row seam. *)
open Lui_elements

module Int_map = Map.Make (Int)

type completion = { outcome : string; count : int }
type model = {
  rows : int list;
  count : int;
  row2_index : int option;
  last_id : int option;
  edits : string Int_map.t;
  activated : int option;
  scroll_target : string;
  scroll_token : int;
  completions : completion Int_map.t;
}

type action =
  | Load of int
  | Clear
  | Reorder
  | Shrink
  | Remove_row2
  | Edit of int * string
  | Activate of int
  | Jump_last
  | Jump_top
  | Jump_missing
  | Complete of int * string

let initial = {
  rows = []; count = 0; row2_index = None; last_id = None;
  edits = Int_map.empty; activated = None; scroll_target = "";
  scroll_token = 0; completions = Int_map.empty;
}

let with_rows model rows =
  let count, row2_index, last_id =
    List.fold_left
      (fun (index, row2, _) id ->
        index + 1, (if id = 2 then Some index else row2), Some id)
      (0, None, None) rows
  in
  { model with rows; count; row2_index; last_id; scroll_target = "" }

let jump model id =
  { model with scroll_target = Printf.sprintf "row-%d" id;
               scroll_token = model.scroll_token + 1 }

let update model = function
  | Load count -> with_rows { model with edits = Int_map.empty; activated = None }
                    (List.init count Fun.id)
  | Clear -> with_rows { model with edits = Int_map.empty; activated = None } []
  | Reorder ->
      (match model.row2_index with
       | Some index when index <> model.count - 1 ->
           let rows = Array.of_list model.rows in
           let last = Array.length rows - 1 in
           let previous = rows.(last) in
           rows.(last) <- rows.(index);
           rows.(index) <- previous;
           with_rows model (Array.to_list rows)
       | Some _ | None -> model)
  | Shrink ->
      if model.count <= 20 then model
      else
        let rows = Array.of_list model.rows in
        with_rows model (Array.to_list (Array.sub rows 0 20))
  | Remove_row2 ->
      (match model.row2_index with
       | None -> model
       | Some _ -> with_rows model (List.filter (fun id -> id <> 2) model.rows))
  | Edit (id, value) -> { model with edits = Int_map.add id value model.edits }
  | Activate id -> { model with activated = Some id }
  | Jump_last -> jump model (Option.value model.last_id ~default:(-1))
  | Jump_top -> jump model 0
  | Jump_missing -> jump model (-1)
  | Complete (token, outcome) ->
      let previous = Int_map.find_opt token model.completions in
      let count = match previous with None -> 1 | Some value -> value.count + 1 in
      { model with completions = Int_map.add token { outcome; count } model.completions }

let edited_value id model =
  Option.value (Int_map.find_opt id model.edits)
    ~default:(Printf.sprintf "Row %d" id)

let status model =
  let completed = Int_map.bindings model.completions
    |> List.map (fun (token, value) ->
      Printf.sprintf "%d:%s:%d" token value.outcome value.count)
    |> String.concat ","
  in
  Printf.sprintf "count=%d row2-index=%d activated=%d edited2=%S token=%d completions=%s"
    model.count (Option.value model.row2_index ~default:(-1))
    (Option.value model.activated ~default:(-1)) (edited_value 2 model)
    model.scroll_token completed

let row_view model_source send item_source =
  let id = sample item_source in
  let content =
    if id = 2 then
      text_field ~height:32 ~width:240 ~label:"Row2"
        ~accessibility_identifier:"row-2-editor"
        ~text:(reactive (edited_value id) model_source)
        ~on_input:(on_input send (fun value -> Edit (id, value))) []
    else
      text ~value:(Printf.sprintf "Row %d" id) []
  in
  row ~height:32 ~gap:8 ~key:(Printf.sprintf "row-%d" id)
    ~accessibility_identifier:(Printf.sprintf "row-%d" id)
    [ content
    ; button ~height:32 ~text:(Printf.sprintf "Activate %d" id)
        ~accessibility_identifier:(Printf.sprintf "activate-%d" id)
        ~on_press:(press send (Activate id)) []
    ]

let view _context model_source send =
  let control identifier label action =
    button ~text:label ~accessibility_identifier:identifier
      ~on_press:(press send action) []
  in
  let completed = function
    | Lui_protocol.ScrollCompleted (_, token, outcome) ->
        ignore (send (Complete (token, outcome)))
    | _ -> ()
  in
  column ~gap:4 ~padding:8
    [ text ~value:"Sparse virtual qualification" []
    ; row ~gap:4
        [ control "load-1k" "Load 1k" (Load 1_000)
        ; control "load-100k" "Load 100k" (Load 100_000)
        ; control "clear" "Clear" Clear
        ; control "reorder" "Reorder" Reorder
        ; control "shrink" "Shrink" Shrink
        ; control "remove-row-2" "Remove row 2" Remove_row2
        ]
    ; row ~gap:4
        [ control "jump-last" "Jump last" Jump_last
        ; control "jump-top" "Jump top" Jump_top
        ; control "jump-missing" "Jump missing" Jump_missing
        ]
    ; text_field ~height:32 ~width:240 ~label:"Outside"
        ~accessibility_identifier:"outside-editor" ~text:"Outside" []
    ; text ~accessibility_identifier:"status" ~value:(reactive status model_source) []
    ; virtual_list ~height:320 ~overscan:2 ~item_extent:32.
        ~accessibility_identifier:"virtual-list"
        ~scroll_target:(reactive (fun model -> model.scroll_target) model_source)
        ~scroll_token:(reactive (fun model -> model.scroll_token) model_source)
        ~scroll_animated:false ~on_scroll_completed:completed
        [ virtual_rows
            ~source:(reactive (fun model -> model.rows)
              (Signal.cutoff (fun a b -> a.rows == b.rows) model_source))
            ~key:Fun.id ~cmp:Int.compare
            ~scroll_key:(fun id -> Printf.sprintf "row-%d" id)
            ~mount:(row_view model_source send) ()
        ]
    ]

let bridge = Lui_native_bridge.create "Sparse virtual qualification"

let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  (* This qualification fixture opts in before production capability 6 is enabled. *)
  let app = Lui_app.create ~virtual_rows:true backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
