(* Real source-factory replacement inside an independently owned Parent Scroll. *)
open Lui_elements

type model = { factory : int }
type action = Rebuild
let rows = List.init 1_000 Fun.id
let update model = function Rebuild -> {factory=model.factory+1}

let view _context model_source send =
  let source_factory factory =
    column ~key:"factory" ~min_width:0
      [virtual_list ~key:"source" ~viewport:`parent ~overscan:5 ~item_extent:44.
         ~accessibility_identifier:"virtual-list"
         [virtual_rows ~source:(reactive (fun _ -> rows) model_source)
            ~key:Fun.id ~cmp:Int.compare
            ~mount:(fun item ->
              let id=sample item in
              row ~key:(string_of_int id) ~height:44 ~min_width:0
                ~accessibility_identifier:(Printf.sprintf "replacement-row-%d" id)
                [text ~accessibility_identifier:(Printf.sprintf "replacement-label-%d" id)
                   ~value:(Printf.sprintf "Factory %d row %d" factory id) []]) ()]]
  in
  column ~gap:4 ~padding:8
    [text ~value:"Sparse virtual qualification" [];
     button ~text:"Replace factory" ~accessibility_identifier:"rebuild-factory"
       ~on_press:(press send Rebuild) [];
     text_field ~accessibility_identifier:"replacement-outside" ~height:32 ~width:240
       ~text:"Retained outside input" [];
     text ~accessibility_identifier:"status"
       ~value:(reactive (fun model -> Printf.sprintf "factory=%d" model.factory) model_source) [];
     scroll ~height:320 ~width:600 ~accessibility_identifier:"replacement-scroll"
       [column ~min_width:0
          [text ~height:64 ~value:"Shared parent header" [];
           reactive source_factory (reactive (fun model -> model.factory) model_source)]]]

let bridge = Lui_native_bridge.create "Sparse virtual qualification"
let initialize platform_code host_code =
  let backend=Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app=Lui_app.create ~virtual_rows:true backend {factory=0} update view in
  Lui_native_bridge.boot bridge app
let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
