(* Smoke tests for the lui OCaml runtime: protocol helpers, the element DSL,
   and the Lui_app reducer-app lifecycle against a recording backend. *)

let batches = ref []

let recording_backend () =
  batches := [];
  {
    Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch = (fun batch -> batches := batch :: !batches; true);
  }

let all_ops () = List.concat_map (fun (b : Lui_protocol.patch_batch) -> b.ops)
                   (List.rev !batches)

let flush_app app = ignore (Lui_app.flush app)

let todo_view _context model_source send =
  let items = Signal.sample model_source in
  Lui_elements.column ~gap:8
    (Lui_elements.text ~value:"Todos" []
     :: List.map
          (fun (item : string) ->
             Lui_elements.row
               [ Lui_elements.text ~value:item [];
                 Lui_elements.button ~text:"Done"
                   ~on_press:(Lui_elements.press send (`Done item)) [] ])
          items)

let test_app_lifecycle () =
  let app =
    Lui_app.create (recording_backend ()) [ "write tests" ]
      (fun model action ->
         match action with
         | `Done item -> List.filter (fun x -> x <> item) model
         | `Add item -> model @ [ item ])
      todo_view
  in
  Alcotest.(check bool) "not disposed" false (Lui_app.disposed app);
  Alcotest.(check bool) "start" true (Lui_app.start app);
  Alcotest.(check bool) "send" true (Lui_app.send app (`Add "ship it"));
  flush_app app;
  Alcotest.(check (list string)) "model updated"
    [ "write tests"; "ship it" ] (Lui_app.model app);
  Alcotest.(check bool) "send done" true
    (Lui_app.send app (`Done "write tests"));
  flush_app app;
  Alcotest.(check (list string)) "model after done" [ "ship it" ]
    (Lui_app.model app);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app);
  Alcotest.(check bool) "disposed" true (Lui_app.disposed app);
  Alcotest.(check bool) "send after dispose" false
    (Lui_app.send app (`Add "ignored"))

let test_backend_receives_patches () =
  let app =
    Lui_app.create (recording_backend ()) []
      (fun model _action -> model)
      todo_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  Alcotest.(check bool) "column created" true
    (List.exists
       (function Lui_protocol.CreateNode (_, Lui_protocol.Column) -> true
               | _ -> false)
       ops);
  Alcotest.(check bool) "batches non-empty" true (ops <> []);
  Alcotest.(check bool) "generations positive" true
    (List.for_all (fun (b : Lui_protocol.patch_batch) -> b.generation > 0)
       !batches);
  ignore (Lui_app.dispose app)

let test_protocol_helpers () =
  Alcotest.(check bool) "modal dialog" true
    (Lui_protocol.modal_surface Lui_protocol.Dialog);
  Alcotest.(check bool) "row not modal" false
    (Lui_protocol.modal_surface Lui_protocol.Row);
  Alcotest.(check bool) "row is container" true
    (Lui_protocol.tree_row_kind Lui_protocol.Row);
  Alcotest.(check bool) "event node" true
    (Lui_protocol.event_node (Lui_protocol.Press 7) = 7);
  let profile = Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost in
  Alcotest.(check bool) "profile os" true
    (profile.profile_os = Lui_protocol.MacOS)

let () =
  Alcotest.run "lui"
    [
      ( "app",
        [
          Alcotest.test_case "lifecycle" `Quick test_app_lifecycle;
          Alcotest.test_case "backend patches" `Quick
            test_backend_receives_patches;
        ] );
      ( "protocol",
        [ Alcotest.test_case "helpers" `Quick test_protocol_helpers ] );
    ]
