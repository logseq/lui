(* Native bridge for the Swift host: registers the OCaml-side entry points
   that platform/native/lui_ocaml_bridge.c calls back into. Each entry point
   returns the JSON patch batch produced since the previous call. *)

open Lui_protocol

let latest_patch = ref ""

let current_app : (Model.t, Model.action) Lui_app.reducer_app option ref =
  ref None

let app () =
  match !current_app with
  | Some value -> value
  | None -> invalid_arg "Markdown bridge is not started"

let operating_system = function
  | 1 -> MacOS
  | 2 -> IOS
  | 3 -> AndroidOS
  | 4 -> LinuxOS
  | 5 -> WindowsOS
  | _ -> GenericOS

let host_kind = function
  | 1 -> WebHost
  | 2 -> SwiftUIHost
  | 3 -> FlutterHost
  | 4 -> QMLHost
  | _ -> GenericHost

let backend host_profile =
  {
    backend_profile = host_profile;
    apply_batch =
      (fun batch ->
         latest_patch := Lui_wire.encode_batch batch;
         true);
  }

let initialize platform_code host_code =
  latest_patch := "";
  let value =
    Lui_app.create_with_extensions
      (backend
         (profile (operating_system platform_code) (host_kind host_code)))
      (Extension_schemas.registry ())
      Model.initial Model.update View.view
  in
  current_app := Some value;
  ignore (Lui_app.start value);
  ignore (Lui_app.flush value);
  !latest_patch

let dispatch event =
  latest_patch := "";
  let value = app () in
  ignore (Lui_app.dispatch_event value event);
  ignore (Lui_app.flush value);
  !latest_patch

let appear node = dispatch (Appear node)

let press node = dispatch (Press node)

let long_press node = dispatch (LongPress node)

let text_changed node text = dispatch (TextChanged (node, text))

let submit node = dispatch (Submit node)

let dismiss node = dispatch (Dismiss node)

let double_press node = dispatch (DoublePress node)

let toggle_changed node checked = dispatch (ToggleChanged (node, checked))

let radio_changed node = dispatch (Change node)

let slider_changed node value = dispatch (ValueChanged (node, value))

(* Extension events travel as a flat JSON object of scalar values; decode it
   and let the runtime validate the payload against the declared schema. *)
let extension_event node identifier name json_values =
  let values =
    match Lui_json.parse_values json_values with
    | values -> values
    | exception Lui_json.Parse_error message ->
      invalid_arg ("invalid extension event payload: " ^ message)
  in
  dispatch (ExtensionEvent (node, identifier, name, values))

let dispose () =
  latest_patch := "";
  ignore (Lui_app.dispose (app ()));
  !latest_patch

let root_node () = Lui_app.root_node (app ())

let () =
  Callback.register "lui_ocaml_init" initialize;
  Callback.register "lui_ocaml_appear" appear;
  Callback.register "lui_ocaml_press" press;
  Callback.register "lui_ocaml_long_press" long_press;
  Callback.register "lui_ocaml_text_changed" text_changed;
  Callback.register "lui_ocaml_submit" submit;
  Callback.register "lui_ocaml_dismiss" dismiss;
  Callback.register "lui_ocaml_double_press" double_press;
  Callback.register "lui_ocaml_toggle_changed" toggle_changed;
  Callback.register "lui_ocaml_radio_changed" radio_changed;
  Callback.register "lui_ocaml_slider_changed" slider_changed;
  Callback.register "lui_ocaml_extension_event" extension_event;
  Callback.register "lui_ocaml_dispose" dispose;
  Callback.register "lui_ocaml_root_node" root_node
