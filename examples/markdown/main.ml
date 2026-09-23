(* Headless demo: mounts the markdown editor against a printing backend,
   then simulates an edit so the extension wire ops and status-bar updates
   are visible. Run with `dune exec examples/markdown`. *)

let batches = ref []

let backend =
  {
    Lui_protocol.backend_profile =
      Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost;
    apply_batch =
      (fun batch ->
         batches := batch :: !batches;
         Printf.printf "patch batch generation=%d ops=%d\n%!"
           batch.Lui_protocol.generation
           (List.length batch.Lui_protocol.ops);
         true);
  }

let () =
  let registry = Extension_schemas.registry () in
  (match Lui_extension.schema registry "markdown-editor" with
   | Some schema ->
     Printf.printf "fingerprint: %s\n%!" (Lui_extension.fingerprint schema)
   | None -> print_endline "markdown-editor schema missing");
  let app =
    Lui_app.create_with_extensions backend
      (Extension_schemas.registry ())
      Model.initial Model.update View.view
  in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  ignore
    (Lui_app.send app
       (Model.TextChanged ("# Heading\n\n- a\n- b\n", 12)));
  ignore (Lui_app.send app (Model.CursorMoved 3));
  ignore (Lui_app.flush app);
  let model = Lui_app.model app in
  Printf.printf "status: %s\n%!" (Model.status_line model);
  ignore (Lui_app.dispose app)
