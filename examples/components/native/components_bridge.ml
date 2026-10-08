(* Native bridge for the Swift and Kotlin hosts. Entry points live in
   Lui_native_bridge; this module only builds the gallery app. *)

let bridge = Lui_native_bridge.create "Components"

let initialize platform_code host_code =
  try
    let app =
      Lui_app.create_with_extensions
        (Lui_native_bridge.backend bridge
           (Lui_native_bridge.profile platform_code host_code))
        (Extension_schemas.registry ())
        Model.initial Model.update View.view
    in
    Lui_native_bridge.boot bridge app
  with exn ->
    Printf.eprintf "lui gallery init failed: %s\n%s%!" (Printexc.to_string exn)
      (Printexc.get_backtrace ());
    raise exn

(* platform/native/lui_ocaml_bridge.c looks up "lui_ocaml_*";
   platform/android/lui's JNI bridge looks up "lui_kotlin_*". *)
let () =
  Printexc.record_backtrace true;
  Callback.register "lui_ocaml_init" initialize;
  Callback.register "lui_kotlin_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge;
  Lui_native_bridge.register ~register_named:Callback.register "lui_kotlin" bridge
