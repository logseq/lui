(* Real Picked/Dismiss C ABI qualification. No request opens a dialog at startup. *)
open Lui_elements

type model = { payload : string; dismissals : int }
type action = Picked of string | Dismissed

let update model = function
  | Picked payload -> { model with payload }
  | Dismissed -> { model with dismissals = model.dismissals + 1 }

let view _context model_source send =
  column ~padding:16 ~gap:8
    [ file_picker ~accessibility_identifier:"picker-probe"
        ~on_picked:(function
          | Lui_protocol.Picked (_, payload) -> ignore (send (Picked payload))
          | _ -> ())
        ~on_dismiss:(fun _ -> ignore (send Dismissed)) []
    ; text ~accessibility_identifier:"picker-payload"
        ~value:(reactive (fun model -> model.payload) model_source) []
    ; text ~accessibility_identifier:"picker-dismissals"
        ~value:(reactive (fun model -> string_of_int model.dismissals) model_source) []
    ]

let bridge = Lui_native_bridge.create "File picker ABI qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend { payload = "none"; dismissals = 0 } update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
