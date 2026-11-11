(* A packaged native Image must decode before its canonical Load changes this model. *)
open Lui_elements

let source name fallback = Option.value (Sys.getenv_opt name) ~default:fallback
let first = source "LUI_NSH_IMAGE_URL_A" "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="
let second = source "LUI_NSH_IMAGE_URL_B" first
let missing = source "LUI_NSH_IMAGE_URL_MISSING" "file:///nonexistent/lui-image-missing.png"

type model = { url : string; loads : int; draft : string }
type action = Loaded | Change of string | Edit of string

let initial = { url = first; loads = 0; draft = "" }
let update model = function
  | Loaded -> { model with loads = model.loads + 1 }
  | Change url -> { model with url }
  | Edit draft -> { model with draft }

let view _context model_source send =
  column ~padding:16 ~gap:8
    [ text ~value:"Image URL qualification" []
    ; image ~accessibility_identifier:"image-probe" ~width:120 ~height:60
        ~url:(reactive (fun model -> model.url) model_source)
        ~alt:"Canonical URL image" ~on_load:(fun _ -> ignore (send Loaded)) []
    ; text_field ~accessibility_identifier:"image-editor" ~label:"Retained image editor"
        ~text:(reactive (fun model -> model.draft) model_source)
        ~on_input:(on_input send (fun value -> Edit value)) []
    ; button ~accessibility_identifier:"image-second" ~text:"Second source"
        ~on_press:(press send (Change second)) []
    ; button ~accessibility_identifier:"image-missing" ~text:"Missing source"
        ~on_press:(press send (Change missing)) []
    ; button ~accessibility_identifier:"image-first" ~text:"First source"
        ~on_press:(press send (Change first)) []
    ; text ~accessibility_identifier:"image-loads"
        ~value:(reactive (fun model -> Printf.sprintf "Image loads %d" model.loads) model_source) []
    ]

let bridge = Lui_native_bridge.create "Image URL qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
