(* Native bridge for the Swift host. *)

let bridge = Lui_native_bridge.create "Markdown"

let initialize platform_code host_code =
  let app =
    Lui_app.create_with_extensions
      (Lui_native_bridge.backend bridge
         (Lui_native_bridge.profile platform_code host_code))
      (Extension_schemas.registry ())
      Model.initial Model.update View.view
  in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
