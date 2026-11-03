(* Portable application used by native host integration tests. *)
open Lui_elements

type row = { id : int; text : string; detail : string }
type model = { rows : row list; target : string; token : int }
type action = Load | Clear | Reorder | Shrink | Bottom | Variable | Edit of int * string

let rows count = List.init count (fun id ->
  { id; text = "draft-" ^ string_of_int id; detail = "Row-" ^ string_of_int id })

let update model = function
  | Load -> { model with rows = rows 100_000; target = "" }
  | Clear -> { model with rows = []; target = "" }
  | Shrink -> { model with rows = List.filter (fun row -> row.id < 10) model.rows }
  | Bottom ->
    let last = List.fold_left (fun _ row -> Some row.id) None model.rows in
    { model with target = (match last with
        | Some id -> "row-" ^ string_of_int id | None -> "missing-row");
      token = model.token + 1 }
  | Reorder ->
    let ordered = Array.of_list model.rows in
    let first = ref None and last = ref None in
    Array.iteri (fun index row ->
      if row.id = 2 then first := Some index;
      if row.id = 99_999 then last := Some index) ordered;
    (match !first, !last with
     | Some left, Some right ->
       let temporary = ordered.(left) in
       ordered.(left) <- ordered.(right);
       ordered.(right) <- temporary
     | _ -> ());
    { model with rows = Array.to_list ordered }
  | Variable -> { model with rows = List.map (fun row ->
      { row with detail = if row.id mod 2 = 0 then "Row-" ^ string_of_int row.id
        else Printf.sprintf "Row-%d\nSecond line\nThird line" row.id }) model.rows }
  | Edit (id, text) -> { model with rows = List.map (fun row ->
      if row.id = id then { row with text } else row) model.rows }

let view _context source send =
  let control identifier text action =
    button ~accessibility_identifier:identifier ~text
      ~on_press:(fun _ -> ignore (send action)) [] in
  column [
    row [
      control "sparse-load" "Load 100000" Load;
      control "sparse-clear" "Clear" Clear;
      control "sparse-reorder" "Reorder" Reorder;
      control "sparse-shrink" "Shrink" Shrink;
      control "sparse-target-bottom" "Bottom" Bottom;
      control "sparse-variable" "Variable" Variable;
    ];
    text ~accessibility_identifier:"sparse-count"
      ~value:(reactive (fun model -> string_of_int (List.length model.rows)) source) [];
    virtual_list ~accessibility_identifier:"sparse-list" ~height:320
      ~overscan:2 ~item_extent:32.
      ~scroll_target:(reactive (fun model -> model.target) source)
      ~scroll_token:(reactive (fun model -> model.token) source)
      [virtual_rows ~source:(reactive (fun model -> model.rows) source)
         ~key:(fun row -> row.id) ~cmp:Int.compare
         ~scroll_key:(fun row -> "row-" ^ string_of_int row.id)
         ~mount:(fun item_source ->
           let id = (Signal.sample item_source).id in
           column [
             text_field ~placeholder:("Editor-" ^ string_of_int id)
               ~text:(reactive (fun row -> row.text) item_source)
               ~on_input:(function
                 | Lui_protocol.TextChanged (_, text) -> ignore (send (Edit (id, text)))
                 | _ -> ()) [];
             text ~value:(reactive (fun row -> row.detail) item_source) [];
           ]) ()]
  ]

let bridge = Lui_native_bridge.create "BoundedVirtualFixture"

let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create
    ~virtual_rows:(Lui_native_bridge.virtual_rows_supported host_code)
    backend { rows = []; target = ""; token = 0 } update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Callback.register "lui_kotlin_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge;
  Lui_native_bridge.register ~register_named:Callback.register "lui_kotlin" bridge
