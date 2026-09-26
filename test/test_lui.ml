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
        Lui_elements.dyn ~equal:(fun _ _ -> false)
          (fun (m : dyn_model) -> Lui_elements.text ~value:m.label [])
          model_source);
    ]

let creates_text ops =
  List.exists
    (function
     | Lui_protocol.CreateNode (_, Lui_protocol.Text) -> true
     | _ -> false)
    ops

(* A remount reconciles the branch: nodes that map onto their predecessors
   keep their ids, so changed content arrives as prop updates rather than
   drop+create churn. *)
let updates_text ops =
  List.exists
    (function
     | Lui_protocol.SetProp (_, Lui_protocol.TextValue, _) -> true
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
  Alcotest.(check bool) "changed publish updates in place" true
    (updates_text (all_ops ()));
  Alcotest.(check bool) "changed publish mounts nothing" false
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
  (* An unchanged publish reconciles to zero ops — no drop+create churn and
     no prop diff. *)
  ignore (Lui_app.send app `Tick);
  flush_app app;
  Alcotest.(check bool) "default republish emits nothing" true
    (all_ops () = []);
  ignore (Lui_app.send app (`Rename "second"));
  flush_app app;
  Alcotest.(check bool) "default republish updates in place" true
    (updates_text (all_ops ()));
  Alcotest.(check bool) "default republish mounts nothing" false
    (creates_text (all_ops ()));
  ignore (Lui_app.dispose app)

type ext_dyn_model = { ex_url : string }

let ext_dyn_registry () =
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry
    (Lui_extension.component "web-view"
       [ Lui_protocol.generic_profile () ]
       false []
       [ Lui_extension.property "url" Lui_extension.StringScalar true None ]
       [ Lui_extension.event "navigated"
           [ Lui_extension.event_field "url" Lui_extension.StringScalar true ] ]);
  Lui_extension.freeze registry;
  registry

let ext_dyn_view _context model_source _send =
  Lui_elements.column
    [
      Lui_elements.dyn ~equal:(fun a b -> a.ex_url = b.ex_url)
        (fun (m : ext_dyn_model) ->
           Lui_elements.column
             [
               Lui_elements.text ~value:"before" [];
               (fun context parent ->
                 let node = Lui_ui.extension context "web-view" in
                 Lui_ui.extension_property context node "url"
                   (Lui_protocol.StringValue m.ex_url);
                 Lui_ui.on_event context node (fun _event -> ());
                 (match parent with
                 | Some parent -> Lui_ui.append context parent node
                 | None -> ());
                 node);
               Lui_elements.text ~value:"after" [];
             ])
        model_source;
    ]

let test_dyn_remount_with_extension () =
  let app =
    Lui_app.create_with_extensions (recording_backend ())
      (ext_dyn_registry ()) { ex_url = "about:blank" }
      (fun _model action -> match action with `Set ex_url -> { ex_url })
      ext_dyn_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app (`Set "https://example.com"));
  flush_app app;
  let ops = all_ops () in
  Alcotest.(check bool) "remount emits prop update" true
    (List.exists
       (function
         | Lui_protocol.SetExtensionProp (_, "url", _) -> true
         | _ -> false)
       ops);
  (* a SECOND publish must also remount — the subscription has to survive
     the first reconcile *)
  batches := [];
  ignore (Lui_app.send app (`Set "https://example.org"));
  flush_app app;
  Alcotest.(check bool) "second remount emits prop update" true
    (List.exists
       (function
         | Lui_protocol.SetExtensionProp (_, "url", _) -> true
         | _ -> false)
       (all_ops ()));
  ignore (Lui_app.dispose app)

(* meng's plugin drawer: outer dyn over a slot list, each card carrying an
   inner dyn over a plugin-owned view tree containing an extension node.
   Both dyns have to keep updating across repeated publishes. *)
type drawer_model = { slots : (string * string) list; views : (string * string) list }

let drawer_view _context model_source _send =
  Lui_elements.column
    [
      Lui_elements.dyn ~equal:(fun a b -> a = b)
    (fun (slots : (string * string) list) ->
       match slots with
       | [] -> Lui_elements.spacer ~width:0 []
       | slots ->
         Lui_elements.column
           (List.map
              (fun (_plugin_id, panel_id) ->
                 Lui_elements.column
                   [
                     Lui_elements.text ~value:panel_id [];
                     Lui_elements.dyn ~equal:(fun a b -> a = b)
                       (fun (url : string option) ->
                          match url with
                          | Some url ->
                            Lui_elements.column
                              [
                                (fun context parent ->
                                  let node =
                                    Lui_ui.extension context "web-view"
                                  in
                                  Lui_ui.extension_property context node "url"
                                    (Lui_protocol.StringValue url);
                                  Lui_ui.on_event context node (fun _ -> ());
                                  (match parent with
                                  | Some parent ->
                                    Lui_ui.append context parent node
                                  | None -> ());
                                  node);
                              ]
                          | None -> Lui_elements.spacer ~width:0 [])
                       (Signal.map
                          (fun (m : drawer_model) ->
                             List.assoc_opt panel_id m.views)
                          model_source);
                   ])
              slots))
        (Signal.map (fun (m : drawer_model) -> m.slots) model_source);
    ]

(* An outer dyn remount renames the card columns an inner dyn mounts
   under; each inner reconcile must not wipe the aliases other branches
   still rely on (or their remounts are skipped forever). *)
let test_alias_preserved_across_reconciles () =
  let initial =
    { slots = [ ("p1", "browser") ]; views = [ ("browser", "u0") ] }
  in
  let app =
    Lui_app.create_with_extensions (recording_backend ())
      (ext_dyn_registry ()) initial
      (fun model action ->
         match action with
         | `View (panel_id, url) ->
           {
             model with
             views =
               (panel_id, url)
               :: List.remove_assoc panel_id model.views;
           }
         | `Slots slots -> { model with slots })
      drawer_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  (* add a second card: outer remount reconciles the first card's column
     onto the existing node, leaving the new inner dyns' parents as
     aliases *)
  ignore
    (Lui_app.send app
       (`Slots [ ("p1", "browser"); ("p2", "main") ]
       |> fun a -> a));
  ignore
    (Lui_app.send app (`View ("main", "m0")));
  flush_app app;
  let has_url_op url =
    List.exists
      (function
        | Lui_protocol.SetExtensionProp (_, "url", Lui_protocol.StringValue v)
          -> v = url
        | _ -> false)
      (all_ops ())
  in
  batches := [];
  ignore (Lui_app.send app (`View ("browser", "b1")));
  flush_app app;
  Alcotest.(check bool) "first inner remount emits" true (has_url_op "b1");
  batches := [];
  ignore (Lui_app.send app (`View ("main", "m1")));
  flush_app app;
  Alcotest.(check bool) "sibling inner remount still emits" true
    (has_url_op "m1");
  batches := [];
  ignore (Lui_app.send app (`View ("browser", "b2")));
  flush_app app;
  Alcotest.(check bool) "first inner dyn still alive after own reconcile"
    true (has_url_op "b2");
  (* discarded candidate ids from finished reconciles must not pile up:
     the table holds only aliases live branches still reference *)
  let alias_count =
    Hashtbl.length
      (Lui_app.runtime app).Lui_runtime.runtime_node_aliases
  in
  Alcotest.(check bool) "alias table stays bounded" true (alias_count < 10);
  ignore (Lui_app.dispose app)

let test_nested_dyn_extension () =
  let initial =
    {
      slots = [ ("p1", "browser") ];
      views = [ ("browser", "about:blank") ];
    }
  in
  let app =
    Lui_app.create_with_extensions (recording_backend ())
      (ext_dyn_registry ()) initial
      (fun model action ->
         match action with
         | `View (panel_id, url) ->
           {
             model with
             views =
               (panel_id, url)
               :: List.remove_assoc panel_id model.views;
           }
         | `Slots slots -> { model with slots })
      drawer_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app (`View ("browser", "https://one.test")));
  flush_app app;
  Alcotest.(check bool) "first inner remount" true
    (List.exists
       (function
         | Lui_protocol.SetExtensionProp (_, "url", _) -> true
         | _ -> false)
       (all_ops ()));
  batches := [];
  ignore (Lui_app.send app (`View ("browser", "https://two.test")));
  flush_app app;
  Alcotest.(check bool) "second inner remount" true
    (List.exists
       (function
         | Lui_protocol.SetExtensionProp (_, "url", _) -> true
         | _ -> false)
       (all_ops ()));
  ignore (Lui_app.dispose app)

type swap_model = { sm_label : string; sm_button : bool }

let swap_view _context model_source _send =
  Lui_elements.column
    [
      Lui_elements.dyn ~equal:(fun _ _ -> false)
        (fun (m : swap_model) ->
           if m.sm_button
           then Lui_elements.button ~text:m.sm_label []
           else Lui_elements.text ~value:m.sm_label [])
        model_source;
    ]

let creates_button ops =
  List.exists
    (function
     | Lui_protocol.CreateNode (_, Lui_protocol.Button) -> true
     | _ -> false)
    ops

let drops_node ops =
  List.exists (function Lui_protocol.DropNode _ -> true | _ -> false) ops

let keyed_radio_group_view _context model_source _send =
  Lui_elements.radio_group ~label:"Language"
    [
      Lui_elements.keyed_radio ~source:model_source
        ~key:(fun (choice : string) -> choice)
        ~cmp:String.compare
        ~mount:(fun choice_source ->
          Lui_elements.radio ~text_signal:choice_source []);
    ]

let creates ops kind =
  List.exists
    (function Lui_protocol.CreateNode (_, k) -> k = kind | _ -> false)
    ops

let attached_under ops parent =
  List.exists
    (function
     | Lui_protocol.InsertChild (p, _child, _index) -> p = parent
     | _ -> false)
    ops

let test_keyed_radio_mounts_under_group () =
  let app =
    Lui_app.create (recording_backend ()) [ "en"; "fr" ]
      (fun model action ->
         match action with `Add choice -> model @ [ choice ])
      keyed_radio_group_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let group_node =
    List.find_map
      (function
       | Lui_protocol.CreateNode (node, Lui_protocol.RadioGroup) ->
         Some node
       | _ -> None)
      ops
  in
  Alcotest.(check bool) "radio-group created" true (group_node <> None);
  Alcotest.(check bool) "radios created" true
    (creates ops Lui_protocol.Radio);
  (match group_node with
   | Some node ->
     Alcotest.(check bool) "radios attach under group" true
       (attached_under ops node)
   | None -> ());
  batches := [];
  ignore (Lui_app.send app (`Add "de"));
  flush_app app;
  Alcotest.(check bool) "insert adds a radio" true
    (creates (all_ops ()) Lui_protocol.Radio);
  ignore (Lui_app.dispose app)

let test_dyn_remount_swaps_incompatible_kind () =
  let app =
    Lui_app.create (recording_backend ())
      { sm_label = "first"; sm_button = false }
      (fun model action ->
         match action with `Swap -> { model with sm_button = true })
      swap_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app `Swap);
  flush_app app;
  (* An incompatible root cannot be mapped: reconcile falls back to a real
     drop+create for the branch. *)
  Alcotest.(check bool) "swap mounts the new kind" true
    (creates_button (all_ops ()));
  Alcotest.(check bool) "swap drops the old kind" true
    (drops_node (all_ops ()));
  ignore (Lui_app.dispose app)

let capture_node cell element : Lui_elements.t =
 fun context parent ->
  let node = element context parent in
  cell := node;
  node

let test_glass_button_actions () =
  let single_presses = ref 0 in
  let information_presses = ref 0 in
  let settings_presses = ref 0 in
  let single_node = ref 0 in
  let group_node = ref 0 in
  let action label icon presses : Lui_element_combine.action =
    { label; icon; text = None; on_press = (fun _ -> incr presses) }
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node single_node
               (Lui_element_combine.glass_buttons
                  ~actions:[ action "New note" `plus single_presses ]);
             capture_node group_node
               (Lui_element_combine.glass_buttons
                  ~actions:
                    [ action "Information" `info information_presses;
                      action "Settings" `settings settings_presses ]);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let group_children =
    all_ops ()
    |> List.filter_map (function
         | Lui_protocol.InsertChild (parent, child, index)
           when parent = !group_node -> Some (index, child)
         | _ -> None)
    |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
    |> List.map snd
  in
  Alcotest.(check int) "group has two actions" 2 (List.length group_children);
  List.iter
    (fun node ->
       ignore (Lui_app.dispatch_event app (Lui_protocol.Press node)))
    (!single_node :: group_children);
  flush_app app;
  Alcotest.(check (list int)) "each action has its own callback"
    [ 1; 1; 1 ]
    [ !single_presses; !information_presses; !settings_presses ];
  ignore (Lui_app.dispose app)

let test_glass_buttons_require_an_action () =
  let rejected =
    try
      let _element = Lui_element_combine.glass_buttons ~actions:[] in
      false
    with Invalid_argument _ -> true
  in
  Alcotest.(check bool) "empty group rejected" true rejected

let test_glass_button_text_is_optional () =
  let icon_only_node = ref 0 in
  let text_node = ref 0 in
  let group_node = ref 0 in
  let action : Lui_element_combine.action =
    { label = "New note"; icon = `plus; text = None; on_press = (fun _ -> ()) }
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node icon_only_node
               (Lui_element_combine.glass_buttons ~actions:[ action ]);
             capture_node text_node
               (Lui_element_combine.glass_buttons
                  ~actions:[ { action with text = Some "New note" } ]);
             capture_node group_node
               (Lui_element_combine.glass_buttons
                  ~actions:
                    [ { action with label = "Information"; icon = `info
                      ; text = Some "Info" }
                    ; { action with label = "Settings"; icon = `settings }
                    ]);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let has_property node property value =
    List.exists
      (function
       | Lui_protocol.SetProp (id, key, Lui_protocol.StringValue text) ->
         id = node && key = property && text = value
       | _ -> false)
      (all_ops ())
  in
  Alcotest.(check bool) "icon-only button keeps accessible label" true
    (has_property !icon_only_node Lui_protocol.AccessibilityLabel "New note");
  Alcotest.(check bool) "icon-only button has no visible text" false
    (has_property !icon_only_node Lui_protocol.TextValue "New note");
  Alcotest.(check bool) "text button shows its text" true
    (has_property !text_node Lui_protocol.TextValue "New note");
  let group_children =
    all_ops ()
    |> List.filter_map (function
         | Lui_protocol.InsertChild (parent, child, index)
           when parent = !group_node -> Some (index, child)
         | _ -> None)
    |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
    |> List.map snd
  in
  Alcotest.(check int) "group has two actions" 2 (List.length group_children);
  Alcotest.(check bool) "first group action shows text" true
    (has_property (List.hd group_children) Lui_protocol.TextValue "Info");
  Alcotest.(check bool) "second group action is icon-only" false
    (has_property (List.nth group_children 1) Lui_protocol.TextValue "Settings");
  ignore (Lui_app.dispose app)

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

(* Extension fingerprint sync: the gallery declares its extension schemas
   once in Extension_schemas (OCaml); host apps mirror the canonical
   fingerprint strings as literals. Lui_extension_check compares the two so
   drift fails here instead of surfacing as a runtime "extension fingerprint
   mismatch" blank screen. *)

let source_root () =
  match Sys.getenv_opt "DUNE_SOURCEROOT" with
  | Some root -> root
  | None ->
    let rec ascend depth dir =
      if depth > 12 then
        failwith "could not locate repository root (dune-project)"
      else if
        Sys.file_exists (Filename.concat dir "dune-project")
        && not
             (String.equal (Filename.basename dir) "_build"
             || String.equal (Filename.basename (Filename.dirname dir))
                  "_build")
      then dir
      else ascend (depth + 1) (Filename.dirname dir)
    in
    ascend 0 (Sys.getcwd ())

let read_file path =
  let channel = open_in_bin path in
  let contents =
    really_input_string channel (in_channel_length channel)
  in
  close_in channel;
  contents

let gallery_source () =
  read_file
    (Filename.concat (source_root ())
       "examples/components/ios-swiftui/Sources/LUIComponentsApp/GalleryExtensions.swift")

let contains source pattern =
  let n = String.length pattern in
  let last = String.length source - n in
  let rec loop i = i <= last && (String.sub source i n = pattern || loop (i + 1)) in
  loop 0

let replace_first source pattern replacement =
  let n = String.length pattern in
  let last = String.length source - n in
  let rec loop i =
    if i > last then None
    else if String.sub source i n = pattern then
      Some
        (String.sub source 0 i ^ replacement
        ^ String.sub source (i + n) (String.length source - i - n))
    else loop (i + 1)
  in
  loop 0

let gallery_schema identifier =
  let registry = Extension_schemas.registry () in
  match Lui_extension.schema registry identifier with
  | Some schema -> schema
  | None -> Alcotest.fail ("unregistered schema " ^ identifier)

let test_fingerprint_format () =
  Alcotest.(check string) "apple-map fingerprint"
    "lui-extension-v1|9:apple-map|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map"));
  Alcotest.(check string) "marker fingerprint"
    "lui-extension-v1|16:apple-map-marker|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:|properties:5:title:string:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map-marker"));
  Alcotest.(check string) "tweak fingerprint"
    "lui-tweak-v1|14:gallery-accent|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,macos/flutter,macos/swiftui,web/web,windows/flutter|properties:"
    (Lui_extension.tweak_fingerprint (gallery_schema "gallery-accent"))

let test_host_literals_in_sync () =
  let registry = Extension_schemas.registry () in
  match
    Lui_extension_check.check_registry registry (gallery_source ())
  with
  | [] -> ()
  | mismatches ->
    Alcotest.failf "extension fingerprint drift:\n%s"
      (Lui_extension_check.describe_mismatches mismatches)

let test_drift_is_caught () =
  let registry = Extension_schemas.registry () in
  let source = gallery_source () in
  (* Drop the marker child from apple-map's host literal only. *)
  let drifted =
    match
      replace_first source "|children:16:apple-map-marker|" "|children:|"
    with
    | Some value -> value
    | None -> Alcotest.fail "gallery source did not contain the expected literal"
  in
  (match Lui_extension_check.check_registry registry drifted with
   | [ Lui_extension_check.Drifted { declaration; expected } ] ->
     Alcotest.(check string) "drifted identifier" "apple-map"
       declaration.host_identifier;
     Alcotest.(check bool) "expected keeps the child" true
       (contains expected "16:apple-map-marker")
   | _ -> Alcotest.fail "expected exactly one drifted fingerprint");
  (* A host literal for an extension the OCaml side never declared. *)
  let undeclared =
    source
    ^ "\n    fingerprint: \"lui-extension-v1|8:fake-map|profiles:ios/swiftui|standard-children:0|children:|properties:|events:\"\n"
  in
  (match Lui_extension_check.check_registry registry undeclared with
   | [ Lui_extension_check.Undeclared_identifier declaration ] ->
     Alcotest.(check string) "undeclared identifier" "fake-map"
       declaration.host_identifier
   | _ -> Alcotest.fail "expected exactly one undeclared identifier");
  (* Dart host registrations use single-quoted literals: same extraction. *)
  let dart_source =
    "LUIFlutterExtension(\n\
    \  identifier: 'apple-map',\n\
    \  fingerprint: 'lui-extension-v1|9:apple-map|profiles:ios/swiftui,macos/swiftui|standard-children:1|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:',\n\
    \  builder: (_) => const SizedBox.shrink(),\n\
    )"
  in
  match Lui_extension_check.check_registry registry dart_source with
  | [ Lui_extension_check.Drifted { declaration; expected } ] ->
    Alcotest.(check string) "dart identifier" "apple-map"
      declaration.host_identifier;
    Alcotest.(check bool) "expected has standard-children:0" true
      (contains expected "standard-children:0")
  | _ -> Alcotest.fail "expected exactly one drifted Dart fingerprint"


let test_menu_trigger_rules () =
  let open Lui_protocol in
  Alcotest.(check bool) "trigger hosts dropdown-menu" true
    (child_kind_supported MenuTrigger DropdownMenu);
  Alcotest.(check bool) "trigger rejects menu-item child" false
    (child_kind_supported MenuTrigger MenuItem);
  Alcotest.(check bool) "dropdown-menu accepts trigger" true
    (child_kind_supported DropdownMenu MenuTrigger);
  Alcotest.(check bool) "menu-item keeps context-menu" true
    (child_kind_supported MenuItem ContextMenu);
  Alcotest.(check bool) "menu-item drops dropdown-menu" false
    (child_kind_supported MenuItem DropdownMenu);
  Alcotest.(check bool) "context-menu rejects trigger" false
    (child_kind_supported ContextMenu MenuTrigger);
  Alcotest.(check bool) "toolbar accepts trigger" true
    (child_kind_supported Toolbar MenuTrigger);
  Alcotest.(check bool) "trigger allows text" true
    (property_supported MenuTrigger TextValue);
  Alcotest.(check bool) "trigger allows icon" true
    (property_supported MenuTrigger InlineIconName);
  Alcotest.(check bool) "trigger allows label" true
    (property_supported MenuTrigger AccessibilityLabel);
  Alcotest.(check bool) "trigger drops width" false
    (property_supported MenuTrigger WidthValue);
  Alcotest.(check bool) "trigger drops size" false
    (property_supported MenuTrigger SizeValue);
  Alcotest.(check bool) "trigger drops press" false
    (property_supported MenuTrigger PressEnabled);
  let props entries = List.to_seq entries |> Property_map.of_seq in
  Alcotest.(check bool) "icon+label ok" true
    (node_properties_supported MenuTrigger
       (props [ (InlineIconName, StringValue "ellipsis");
                (AccessibilityLabel, StringValue "Account menu") ]));
  Alcotest.(check bool) "icon without label rejected" false
    (node_properties_supported MenuTrigger
       (props [ (InlineIconName, StringValue "ellipsis") ]));
  Alcotest.(check bool) "empty trigger rejected" false
    (node_properties_supported MenuTrigger (props []));
  Alcotest.(check bool) "text-only ok" true
    (node_properties_supported MenuTrigger
       (props [ (TextValue, StringValue "More") ]))

let test_property_matrix_sync () =
  (* property_supported's restrictive arms and additive extras must mirror
     schema/components.json (kindProperties / kindExtraProperties) as emitted
     into Lui_wire_schema — the shared single source for OCaml and Swift. *)
  List.iter
    (fun kind ->
       List.iter
         (fun property ->
            match Lui_wire_schema.kind_property_matrix kind with
            | Some allowed ->
              let expected =
                property = Lui_protocol.AccessibilityIdentifier
                || List.mem property allowed
              in
              Alcotest.(check bool)
                (Printf.sprintf "matrix %s x %s"
                   (Lui_wire_schema.node_kind_name kind)
                   (Lui_wire_schema.property_name property))
                expected (Lui_protocol.property_supported kind property)
            | None ->
              if List.mem property (Lui_wire_schema.kind_extra_properties kind)
              then
                Alcotest.(check bool)
                  (Printf.sprintf "extra %s x %s"
                     (Lui_wire_schema.node_kind_name kind)
                     (Lui_wire_schema.property_name property))
                  true (Lui_protocol.property_supported kind property))
         Lui_wire_schema.all_properties)
    Lui_wire_schema.all_node_kinds

let test_theme_tokens_json () =
  Alcotest.(check string) "fixed + adaptive values"
    {|{"background":{"light":"#fff","dark":"#000"},"primary":"#7c3aed"}|}
    (Lui_ui.theme_tokens_json
       [ ( "background",
           Lui_ui.Adaptive { light = "#fff"; dark = "#000" } );
         ("primary", Lui_ui.Fixed "#7c3aed") ])

(* ---------- Lui_json_view: the language-neutral view-model layer ---------- *)

let str_contains ~needle s =
  let n = String.length s and m = String.length needle in
  let rec go i =
    i + m <= n
    && (String.sub s i m = needle || go (i + 1))
  in
  m = 0 || go 0

let json_view_json =
  {|{"kind":"column","children":[
      {"kind":"card","children":[{"kind":"text","value":"hi"}]},
      {"kind":"switch","id":"sw","checked":true},
      {"kind":"slider","id":"sl","value":0.5},
      {"kind":"icon","name":"plus"},
      {"kind":"toggle-button","id":"b1","text":"Go"},
      {"kind":"table","children":[{"kind":"table-row","children":[
         {"kind":"table-cell","text":"c"}]}]},
      {"kind":"radio-group","children":[{"kind":"radio","label":"r"}]},
      {"kind":"stepper","children":[{"kind":"step","text":"s"}]},
      {"kind":"bottom-tabs","children":[{"kind":"bottom-tab","title":"t"}]},
      {"kind":"input-group","children":[
        {"kind":"textarea","id":"tf"},
        {"kind":"input-group-actions","children":[{"kind":"button","text":"a"}]}]},
      {"kind":"split","children":[{"kind":"text","value":"l"},{"kind":"text","value":"r"}]},
      {"kind":"totally-bogus"}
    ]}|}

let test_json_view_render () =
  let events = ref [] in
  let view _context _model_source _send =
    match Lui_json_view_parse.parse json_view_json with
    | Ok v ->
      Lui_json_view.render
        ~on_event:(fun ~id ~kind ~fields ->
           events := (id, kind, fields) :: !events)
        v
    | Error e -> Lui_elements.text ~value:("parse error: " ^ e) []
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model) view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let created k =
    List.exists
      (function Lui_protocol.CreateNode (_, k') -> k' = k | _ -> false)
      ops
  in
  List.iter
    (fun k ->
       Alcotest.(check bool)
         (Printf.sprintf "created %s"
            (Lui_wire_schema.node_kind_name k))
         true (created k))
    [ Lui_protocol.Card; SwitchControl; Slider; Icon; ToggleButton;
      Table; TableRow; TableCell; RadioGroup; Radio; Stepper; Step;
      BottomTabs; BottomTab; InputGroup; InputGroupActions; Button;
      Split; Textarea; Text ];
  (* unknown kinds render a visible placeholder, never a blank/raise *)
  Alcotest.(check bool) "placeholder text" true
    (List.exists
       (function
          | Lui_protocol.SetProp (_, Lui_protocol.TextValue,
                                  Lui_protocol.StringValue s) ->
            str_contains ~needle:"unsupported component" s
          | _ -> false)
       ops);
  (* press on the node carrying "id" routes through the event sink *)
  let b1 =
    List.find_map
      (function
         | Lui_protocol.CreateNode (id, Lui_protocol.ToggleButton) ->
           Some id
         | _ -> None)
      ops
  in
  (match b1 with
   | Some id ->
     ignore
       (Lui_app.dispatch_event app
          (Lui_protocol.ToggleChanged (id, true)));
     flush_app app;
     Alcotest.(check (list (pair string string))) "event routed"
       [ ("b1", "toggle") ]
       (List.map (fun (id, k, _) -> (id, k)) !events);
     Alcotest.(check bool) "checked field decoded" true
       (match !events with
        | [ (_, _, [ ("checked", Lui_json_view.Bool true) ]) ] -> true
        | _ -> false)
   | None -> Alcotest.fail "toggle-button node not created");
  ignore (Lui_app.dispose app)

let test_json_view_parse () =
  (* malformed input is rejected wholesale — never a partial mount *)
  Alcotest.(check bool) "trailing junk rejected" true
    (match Lui_json_view_parse.parse {|{"kind":"text"} junk|} with
     | Error _ -> true
     | Ok _ -> false);
  Alcotest.(check bool) "unterminated rejected" true
    (match Lui_json_view_parse.parse {|{"kind":"tex|} with
     | Error _ -> true
     | Ok _ -> false);
  Alcotest.(check bool) "partial object rejected" true
    (match Lui_json_view_parse.parse {|{"kind":"text",|} with
     | Error _ -> true
     | Ok _ -> false);
  (* escaped surrogate pairs decode to the real emoji *)
  Alcotest.(check bool) "surrogate pair decodes" true
    (match Lui_json_view_parse.parse {|{"kind":"text","value":"\uD83D\uDE00"}|} with
     | Ok (Lui_json_view.Obj fields) ->
       (match List.assoc_opt "value" fields with
        | Some (Lui_json_view.Str s) -> s = "\xF0\x9F\x98\x80"
        | _ -> false)
     | _ -> false);
  (* pathological nesting is capped *)
  let deep =
    let b = Buffer.create 4096 in
    for _ = 1 to 600 do Buffer.add_string b "{\"kind\":\"row\",\"children\":[" done;
    Buffer.add_string b "null";
    for _ = 1 to 600 do Buffer.add_string b "]}" done;
    Buffer.contents b
  in
  Alcotest.(check bool) "deep nesting rejected" true
    (match Lui_json_view_parse.parse deep with
     | Error _ -> true
     | Ok _ -> false);
  (* app: icon names pass through without double-prefixing *)
  Alcotest.(check bool) "app: icon kept" true
    (match Lui_json_view_parse.parse {|{"kind":"icon","name":"app:mine"}|} with
     | Ok _ -> true
     | Error _ -> false)

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
        [
          Alcotest.test_case "helpers" `Quick test_protocol_helpers;
          Alcotest.test_case "menu-trigger rules" `Quick
            test_menu_trigger_rules;
          Alcotest.test_case "property matrix sync" `Quick
            test_property_matrix_sync;
        ] );
      ( "dyn",
        [
          Alcotest.test_case "equal skips remount" `Quick
            test_dyn_equal_skips_remount;
          Alcotest.test_case "default remounts" `Quick
            test_dyn_default_remounts;
          Alcotest.test_case "remount swaps incompatible kind" `Quick
            test_dyn_remount_swaps_incompatible_kind;
          Alcotest.test_case "remount with extension node" `Quick
            test_dyn_remount_with_extension;
          Alcotest.test_case "nested dyn with extension node" `Quick
            test_nested_dyn_extension;
          Alcotest.test_case "aliases preserved across reconciles" `Quick
            test_alias_preserved_across_reconciles;
          Alcotest.test_case "keyed_radio mounts under group" `Quick
            test_keyed_radio_mounts_under_group;
        ] );
      ( "dispatch",
        [
          Alcotest.test_case "value echoes dropped" `Quick
            test_dispatch_drops_value_echoes;
          Alcotest.test_case "unset default echoes dropped" `Quick
            test_dispatch_drops_unset_default_echoes;
        ] );
      ( "theming",
        [
          Alcotest.test_case "theme_tokens_json" `Quick
            test_theme_tokens_json;
        ] );
      ( "glass buttons",
        [
          Alcotest.test_case "action callbacks" `Quick test_glass_button_actions;
          Alcotest.test_case "requires an action" `Quick
            test_glass_buttons_require_an_action;
          Alcotest.test_case "optional visible text" `Quick
            test_glass_button_text_is_optional;
        ] );
      ( "json_view",
        [
          Alcotest.test_case "render + events" `Quick test_json_view_render;
          Alcotest.test_case "parse edge cases" `Quick test_json_view_parse;
        ] );
      ( "extension fingerprints",
        [
          Alcotest.test_case "canonical format" `Quick
            test_fingerprint_format;
          Alcotest.test_case "host literals in sync" `Quick
            test_host_literals_in_sync;
          Alcotest.test_case "drift is caught" `Quick test_drift_is_caught;
        ] );
    ]
