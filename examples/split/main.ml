(* Headless demo: mounts the split demo against a printing backend so the
   extension wire ops are visible. Run with `dune exec examples/split`. *)

let backend =
  {
    Lui_protocol.backend_profile =
      Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost;
    apply_batch =
      (fun batch ->
         Printf.printf "patch batch generation=%d ops=%d\n%!"
           batch.Lui_protocol.generation
           (List.length batch.Lui_protocol.ops);
         true);
  }

let () =
  let app =
    Lui_app.create_with_extensions backend
      (Lui_split.registry ())
      Model.initial Model.update View.view
  in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  ignore (Lui_app.dispose app)
