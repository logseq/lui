(* The builder replaces this marker before compiling each native library. *)
open Lui_elements

let version = "__LUI_UPGRADE_VERSION__"

type model = { count : int; draft : string }
type action = Increment | Edit of string

let initial = { count = 0; draft = "" }

let update model = function
  | Increment -> { model with count = model.count + 1 }
  | Edit draft -> { model with draft }

let view _context model_source send =
  column ~padding:24 ~gap:12
    [ text ~value:("OCaml upgrade " ^ version) []
    ; text_field ~label:"Upgrade editor" ~text:(reactive (fun model -> model.draft) model_source)
        ~on_input:(on_input send (fun value -> Edit value)) []
    ; button ~text:"Increment" ~on_press:(press send Increment) []
    ; text ~accessibility_identifier:"upgrade-count"
        ~value:(reactive (fun model -> Printf.sprintf "Count %d" model.count) model_source) []
    ]

let bridge = Lui_native_bridge.create ("Upgrade fixture " ^ version)

let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
