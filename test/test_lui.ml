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

type dyn_model = { label : string; ticks : int }

let dyn_view ?equal _context model_source _send =
  Lui_elements.column
    [
      (match equal with
      | Some equal ->
        Lui_elements.dyn ~equal
          (fun (m : dyn_model) -> Lui_elements.text ~value:m.label [])
          model_source
      | None ->
        Lui_elements.dyn
          (fun (m : dyn_model) -> Lui_elements.text ~value:m.label [])
          model_source);
    ]

let creates_text ops =
  List.exists
    (function
     | Lui_protocol.CreateNode (_, Lui_protocol.Text) -> true
     | _ -> false)
    ops

let dyn_reducer model action =
  match action with
  | `Tick -> { model with ticks = model.ticks + 1 }
  | `Rename label -> { model with label }

let test_dyn_equal_skips_remount () =
  let app =
    Lui_app.create (recording_backend ()) { label = "first"; ticks = 0 }
      dyn_reducer
      (dyn_view ~equal:(fun a b -> a.label = b.label))
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app `Tick);
  flush_app app;
  Alcotest.(check bool) "equal republish mounts nothing" true
    (all_ops () = []);
  Alcotest.(check bool) "model still published" true
    ((Lui_app.model app).ticks = 1);
  ignore (Lui_app.send app (`Rename "second"));
  flush_app app;
  Alcotest.(check bool) "changed publish remounts" true
    (creates_text (all_ops ()));
  ignore (Lui_app.dispose app)

let test_dyn_default_remounts () =
  let app =
    Lui_app.create (recording_backend ()) { label = "first"; ticks = 0 }
      dyn_reducer dyn_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app `Tick);
  flush_app app;
  Alcotest.(check bool) "default republish remounts" true
    (creates_text (all_ops ()));
  ignore (Lui_app.dispose app)

let capture_node cell element : Lui_elements.t =
 fun context parent ->
  let node = element context parent in
  cell := node;
  node

let test_dispatch_drops_value_echoes () =
  let inputs = ref 0 in
  let toggles = ref 0 in
  let presses = ref 0 in
  let field_node = ref 0 in
  let checkbox_node = ref 0 in
  let button_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [
             capture_node field_node
               (Lui_elements.text_field ~text:"hello"
                  ~on_input:(fun _event -> incr inputs) []);
             capture_node checkbox_node
               (Lui_elements.checkbox ~checked:false
                  ~on_toggle:(fun _event -> incr toggles) []);
             capture_node button_node
               (Lui_elements.button
                  ~on_press:(fun _event -> incr presses) []);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.TextChanged (!field_node, "hello")));
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.ToggleChanged (!checkbox_node, false)));
  flush_app app;
  Alcotest.(check int) "text echo suppressed" 0 !inputs;
  Alcotest.(check int) "toggle echo suppressed" 0 !toggles;
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.TextChanged (!field_node, "hello!")));
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.ToggleChanged (!checkbox_node, true)));
  ignore
    (Lui_app.dispatch_event app (Lui_protocol.Press !button_node));
  flush_app app;
  Alcotest.(check int) "changed text delivered" 1 !inputs;
  Alcotest.(check int) "changed toggle delivered" 1 !toggles;
  Alcotest.(check int) "press still delivered" 1 !presses;
  ignore (Lui_app.dispose app)

let test_dispatch_drops_unset_default_echoes () =
  let inputs = ref 0 in
  let field_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [
             capture_node field_node
               (Lui_elements.text_field
                  ~on_input:(fun _event -> incr inputs) []);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  ignore
    (Lui_app.dispatch_event app (Lui_protocol.TextChanged (!field_node, "")));
  flush_app app;
  Alcotest.(check int) "empty echo on unset text suppressed" 0 !inputs;
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.TextChanged (!field_node, "x")));
  flush_app app;
  Alcotest.(check int) "typed text delivered" 1 !inputs;
  ignore (Lui_app.dispose app)

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
      ( "dyn",
        [
          Alcotest.test_case "equal skips remount" `Quick
            test_dyn_equal_skips_remount;
          Alcotest.test_case "default remounts" `Quick
            test_dyn_default_remounts;
        ] );
      ( "dispatch",
        [
          Alcotest.test_case "value echoes dropped" `Quick
            test_dispatch_drops_value_echoes;
          Alcotest.test_case "unset default echoes dropped" `Quick
            test_dispatch_drops_unset_default_echoes;
        ] );
    ]
