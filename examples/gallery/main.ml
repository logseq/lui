(* Headless demo: mounts the gallery app against a printing backend,
   then simulates a few interactions. *)

let backend =
  {
    Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch =
      (fun batch ->
         Printf.printf "patch batch generation=%d ops=%d\n%!"
           batch.Lui_protocol.generation
           (List.length batch.Lui_protocol.ops);
         true);
  }

let () =
  let app = Lui_app.create backend Model.initial Model.update View.view in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  ignore (Lui_app.send app Model.ToggleDisabled);
  ignore (Lui_app.send app (Model.SetFieldValue "hello"));
  ignore (Lui_app.send app Model.AdvanceProgress);
  ignore (Lui_app.send app Model.OpenDialog);
  ignore (Lui_app.send app Model.CloseDialog);
  ignore (Lui_app.send app (Model.SelectBottomTab "search"));
  ignore (Lui_app.flush app);
  let model = Lui_app.model app in
  Printf.printf
    "disabled=%b field=%S progress=%.1f bottom_tab=%S\n%!"
    model.Model.disabled model.Model.field_value model.Model.progress
    model.Model.bottom_tab;
  ignore (Lui_app.dispose app)
