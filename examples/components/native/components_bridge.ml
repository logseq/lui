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
  | None -> invalid_arg "Components bridge is not started"

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

let initialize_inner platform_code host_code =
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

let initialize platform_code host_code =
  try
    initialize_inner platform_code host_code
  with exn ->
    Printf.eprintf "lui gallery init failed: %s\n%s%!"
      (Printexc.to_string exn) (Printexc.get_backtrace ());
    raise exn

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

let dispose () =
  latest_patch := "";
  ignore (Lui_app.dispose (app ()));
  !latest_patch

let root_node () = Lui_app.root_node (app ())

let register prefix =
  let open Callback in
  register (prefix ^ "_init") initialize;
  register (prefix ^ "_appear") appear;
  register (prefix ^ "_press") press;
  register (prefix ^ "_long_press") long_press;
  register (prefix ^ "_text_changed") text_changed;
  register (prefix ^ "_submit") submit;
  register (prefix ^ "_dismiss") dismiss;
  register (prefix ^ "_double_press") double_press;
  register (prefix ^ "_toggle_changed") toggle_changed;
  register (prefix ^ "_radio_changed") radio_changed;
  register (prefix ^ "_slider_changed") slider_changed;
  register (prefix ^ "_dispose") dispose;
  register (prefix ^ "_root_node") root_node

(* platform/native/lui_ocaml_bridge.c looks up "lui_ocaml_*" and
   platform/flutter/native/lui_ocaml_bridge.c looks up "lui_flutter_*". *)
let () =
  Printexc.record_backtrace true;
  register "lui_ocaml";
  register "lui_flutter"
