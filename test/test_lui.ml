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

(* A node mounted and dropped inside one pending batch has its ops
   elided; surviving insert/move indices it offset must be renumbered so
   the stream stays incrementally valid for the backend. *)
let test_same_batch_create_drop_renumbers () =
  let list_view _context model_source _send =
    (* The dropped node must sit mid-list and differ in kind from the
       sibling at its position — unkeyed children pair positionally, so
       same-kind siblings reuse the slot and only the tail ever drops. *)
    Lui_elements.column
      [
        Lui_elements.dyn ~equal:(fun a b -> (a : bool) = b)
          (fun (show : bool) ->
             Lui_elements.row
               ([ Lui_elements.text ~value:"a" [] ]
                @ (if show then [ Lui_elements.button ~text:"x" [] ]
                   else [])
                @ [ Lui_elements.text ~value:"b" [];
                    Lui_elements.text ~value:"c" [] ]))
          model_source;
      ]
  in
  let app =
    Lui_app.create (recording_backend ()) true
      (fun _model action -> match action with `Hide -> false)
      list_view
  in
  ignore (Lui_app.start app);
  ignore (Lui_app.send app `Hide);
  flush_app app;
  let children = Hashtbl.create 8 in
  let children_of parent =
    match Hashtbl.find_opt children parent with
    | Some list -> list
    | None -> []
  in
  let rec insert_at list index value =
    match (list, index) with
    | _, 0 -> value :: list
    | x :: rest, n -> x :: insert_at rest (n - 1) value
    | [], _ -> [ value ]
  in
  List.iter
    (fun (operation : Lui_protocol.patch_op) ->
       match operation with
       | InsertChild (parent, child, index) ->
         let current = children_of parent in
         Alcotest.(check bool)
           (Printf.sprintf "insert-child %d at %d of %d" child index
              (List.length current))
           true (index >= 0 && index <= List.length current);
         Hashtbl.replace children parent (insert_at current index child)
       | RemoveChild (parent, child) ->
         Hashtbl.replace children parent
           (List.filter (fun x -> x <> child) (children_of parent))
       | MoveChild (parent, child, index) ->
         let without =
           List.filter (fun x -> x <> child) (children_of parent)
         in
         Alcotest.(check bool)
           (Printf.sprintf "move-child %d to %d of %d" child index
              (List.length without))
           true (index >= 0 && index <= List.length without);
         Hashtbl.replace children parent (insert_at without index child)
       | _ -> ())
    (all_ops ());
  ignore (Lui_app.dispose app)

(* Runs enqueue_drop over a hand-built pending_ops stream (stored
   newest-first inside the runtime) and returns the surviving ops in
   oldest-first order. *)
let elided_ops ops ghost =
  let runtime =
    Lui_runtime.create (Signal.scheduler ()) (recording_backend ())
  in
  runtime.Lui_runtime.pending_ops := List.rev ops;
  Lui_runtime.enqueue_drop runtime ghost;
  List.rev !(runtime.Lui_runtime.pending_ops)

let describe_op (operation : Lui_protocol.patch_op) =
  let open Lui_protocol in
  match operation with
  | CreateNode (id, kind) ->
    Printf.sprintf "create:%d:%s" id (Lui_wire_schema.node_kind_name kind)
  | CreateExtension (id, _, _) -> Printf.sprintf "create-ext:%d" id
  | DropNode id -> Printf.sprintf "drop:%d" id
  | SetProp (id, _, _) -> Printf.sprintf "set-prop:%d" id
  | RemoveProp (id, _) -> Printf.sprintf "remove-prop:%d" id
  | SetExtensionProp (id, _, _) -> Printf.sprintf "set-ext-prop:%d" id
  | RemoveExtensionProp (id, _) -> Printf.sprintf "remove-ext-prop:%d" id
  | InsertChild (parent, child, index) ->
    Printf.sprintf "insert:%d->%d@%d" child parent index
  | RemoveChild (parent, child) ->
    Printf.sprintf "remove:%d->%d" child parent
  | MoveChild (parent, child, index) ->
    Printf.sprintf "move:%d->%d@%d" child parent index

let check_ops label expected actual =
  Alcotest.(check string) label
    (String.concat " " (List.map describe_op expected))
    (String.concat " " (List.map describe_op actual))

(* move-child is remove-then-insert: moving a sibling from before the
   dropped node onto its slot leaves the phantom at index 0, so the
   survivor must be emitted at index 0 — keeping the ghost-space target
   would reorder the surviving siblings. *)
let test_same_batch_drop_adjusts_foreign_move () =
  let open Lui_protocol in
  let ops =
    elided_ops
      [
        CreateNode (1, Column);
        CreateNode (2, Text);
        InsertChild (1, 2, 0);
        CreateNode (3, Button);
        InsertChild (1, 3, 1);
        CreateNode (4, Text);
        InsertChild (1, 4, 2);
        MoveChild (1, 2, 1);
      ]
      3
  in
  check_ops "foreign move renumbered"
    [
      CreateNode (1, Column);
      CreateNode (2, Text);
      InsertChild (1, 2, 0);
      CreateNode (4, Text);
      InsertChild (1, 4, 1);
      MoveChild (1, 2, 0);
    ]
    ops

(* A sibling attached earlier in the same batch is removed before the
   dropped node: the phantom slot tracks it down to 0, and the next
   insert lands at index 0 in ghost-free space instead of index 1. *)
let test_same_batch_drop_tracks_foreign_remove () =
  let open Lui_protocol in
  let ops =
    elided_ops
      [
        CreateNode (1, Column);
        CreateNode (2, Text);
        InsertChild (1, 2, 0);
        CreateNode (3, Button);
        InsertChild (1, 3, 1);
        CreateNode (4, Text);
        InsertChild (1, 4, 2);
        RemoveChild (1, 2);
        CreateNode (5, Text);
        InsertChild (1, 5, 1);
      ]
      3
  in
  check_ops "insert after foreign remove renumbered"
    [
      CreateNode (1, Column);
      CreateNode (2, Text);
      InsertChild (1, 2, 0);
      CreateNode (4, Text);
      InsertChild (1, 4, 1);
      RemoveChild (1, 2);
      CreateNode (5, Text);
      InsertChild (1, 5, 0);
    ]
    ops

(* A remove or move of a child attached before this batch hides its
   origin index from the stream; while the dropped node's slot is live,
   renumbering cannot recover — elision gives up and the node is dropped
   with a real drop-node op, leaving a stream the backend can apply. *)
let test_same_batch_drop_untracked_aborts () =
  let open Lui_protocol in
  let source =
    [
      CreateNode (1, Column);
      CreateNode (3, Button);
      InsertChild (1, 3, 1);
      RemoveChild (1, 9);
      CreateNode (5, Text);
      InsertChild (1, 5, 1);
    ]
  in
  check_ops "untracked remove aborts elision"
    (source @ [ DropNode 3 ])
    (elided_ops source 3)

let test_same_batch_drop_poisoned_parent_aborts () =
  let open Lui_protocol in
  let source =
    [
      CreateNode (1, Column);
      RemoveChild (1, 9);
      CreateNode (3, Button);
      InsertChild (1, 3, 0);
      RemoveChild (1, 8);
    ]
  in
  check_ops "poisoned parent aborts later elision"
    (source @ [ DropNode 3 ])
    (elided_ops source 3)

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

let drops_node ops =
  List.exists (function Lui_protocol.DropNode _ -> true | _ -> false) ops

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

type nested_dyn_model = { outer : bool; inner : string }

let nested_dyn_view _context model_source _send =
  Lui_elements.column
    [
      Lui_elements.dyn ~equal:(fun a b -> a.outer = b.outer)
        (fun (_m : nested_dyn_model) ->
          (* A branch that is itself a bare dyn mounts under a transparent
             anchor instead of raising on parent = None. *)
          Lui_elements.dyn ~equal:(fun a b -> a.inner = b.inner)
            (fun (m : nested_dyn_model) ->
               Lui_elements.text ~value:m.inner [])
            model_source)
        model_source;
    ]

let test_dyn_nested_bare () =
  let app =
    Lui_app.create (recording_backend ()) { outer = true; inner = "in" }
      (fun model action ->
         match action with
         | `Inner inner -> { model with inner }
         | `Outer outer -> { model with outer })
      nested_dyn_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  Alcotest.(check bool) "nested dyn mounts text" true
    (creates_text (all_ops ()));
  batches := [];
  ignore (Lui_app.send app (`Inner "updated"));
  flush_app app;
  Alcotest.(check bool) "inner republish updates" true
    (updates_text (all_ops ()));
  ignore (Lui_app.dispose app)

let test_extension_names_allow_underscore () =
  Alcotest.(check bool) "underscore identifier valid" true
    (Lui_extension.valid_name "my_extension");
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry
    (Lui_extension.component "with_underscore"
       [ Lui_protocol.generic_profile () ]
       false []
       [
         Lui_extension.property "some_prop" Lui_extension.StringScalar true
           None;
       ]
       [
         Lui_extension.event "some_event"
           [ Lui_extension.event_field "some_field" Lui_extension.IntScalar true ];
       ]);
  Lui_extension.freeze registry

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

(* [~equal] defaults to [(=)]: republishing an equal value skips the
   remount, a different value reconciles in place. *)
let test_dyn_default_equal () =
  let app =
    Lui_app.create (recording_backend ()) { label = "first"; ticks = 0 }
      dyn_reducer
      (fun _context model_source _send ->
        Lui_elements.column
          [
            Lui_elements.dyn
              (fun (label : string) -> Lui_elements.text ~value:label [])
              (Signal.map (fun (m : dyn_model) -> m.label) model_source);
          ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  ignore (Lui_app.send app `Tick);
  flush_app app;
  Alcotest.(check bool) "equal republish emits nothing" true
    (all_ops () = []);
  ignore (Lui_app.send app (`Rename "second"));
  flush_app app;
  Alcotest.(check bool) "changed publish updates in place" true
    (updates_text (all_ops ()));
  Alcotest.(check bool) "changed publish mounts nothing" false
    (creates_text (all_ops ()));
  ignore (Lui_app.dispose app)

(* [if_ ~test] mounts the child while the signal publishes [true]
   and drops it on [false]. *)
let test_if_test_toggles () =
  let app =
    Lui_app.create (recording_backend ()) { outer = true; inner = "in" }
      (fun model action ->
        match action with
        | `Hide -> { model with outer = false }
        | `Show -> { model with outer = true })
      (fun _context model_source _send ->
        Lui_elements.column
          [
            Lui_elements.if_
              ~test:
                (Signal.map (fun (m : nested_dyn_model) -> m.outer)
                   model_source)
              (Lui_elements.text ~value:"child" []);
          ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  Alcotest.(check bool) "if_ mounts child" true (creates_text (all_ops ()));
  batches := [];
  ignore (Lui_app.send app `Hide);
  flush_app app;
  Alcotest.(check bool) "if_ drops child" true (drops_node (all_ops ()));
  batches := [];
  ignore (Lui_app.send app `Show);
  flush_app app;
  Alcotest.(check bool) "if_ remounts child" true
    (creates_text (all_ops ()));
  ignore (Lui_app.dispose app)

(* A derived signal shared across remounts keeps working: consumers do
   not own the sources they are handed, so hiding and re-showing the
   branch re-subscribes to a still-live signal. *)
let test_dyn_shared_source_survives_remount () =
  let app =
    Lui_app.create (recording_backend ()) { outer = true; inner = "in" }
      (fun model action ->
        match action with
        | `Hide -> { model with outer = false }
        | `Show -> { model with outer = true }
        | `Inner inner -> { model with inner })
      (fun _context model_source _send ->
        let derived =
          Signal.map (fun (m : nested_dyn_model) -> m.inner) model_source
        in
        Lui_elements.column
          [
            Lui_elements.if_
              ~test:
                (Signal.map (fun (m : nested_dyn_model) -> m.outer)
                   model_source)
              (Lui_elements.dyn
                 ~equal:(fun a b -> a = b)
                 (fun inner -> Lui_elements.text ~value:inner [])
                 derived);
          ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  ignore (Lui_app.send app `Hide);
  flush_app app;
  ignore (Lui_app.send app (`Inner "changed"));
  batches := [];
  ignore (Lui_app.send app `Show);
  flush_app app;
  Alcotest.(check bool) "remount recreates the text node" true
    (creates_text (all_ops ()));
  Alcotest.(check bool) "remount emits latest inner" true
    (List.exists
       (function
        | Lui_protocol.SetProp
            (_, Lui_protocol.TextValue, Lui_protocol.StringValue "changed") ->
            true
        | _ -> false)
       (all_ops ()));
  ignore (Lui_app.dispose app)

let creates_text_count ops =
  List.length
    (List.filter
       (function
        | Lui_protocol.CreateNode (_, Lui_protocol.Text) -> true
        | _ -> false)
       ops)

(* [keyed ~source] mounts one child per item and diffs republished
   membership by key. *)
let test_keyed_source () =
  let app =
    Lui_app.create (recording_backend ()) [ "a"; "b" ]
      (fun model action -> match action with `Add item -> model @ [ item ])
      (fun _context model_source _send ->
        Lui_elements.column
          [
            Lui_elements.keyed ~source:model_source
              ~key:(fun (s : string) -> s) ~cmp:String.compare
              ~mount:(fun item_source ->
                Lui_elements.text ~value_signal:item_source []);
          ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  Alcotest.(check int) "keyed mounts items" 2
    (creates_text_count (all_ops ()));
  batches := [];
  ignore (Lui_app.send app (`Add "c"));
  flush_app app;
  Alcotest.(check int) "keyed mounts the new item only" 1
    (creates_text_count (all_ops ()));
  Alcotest.(check bool) "keyed drops nothing on add" false
    (drops_node (all_ops ()));
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
    Lui_element_combine.Press
      { label; icon; text = None; on_press = (fun _ -> incr presses) }
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node single_node
               (Lui_element_combine.buttons
                  ~actions:[ action "New note" `plus single_presses ]);
             capture_node group_node
               (Lui_element_combine.buttons
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
      let _element = Lui_element_combine.buttons ~actions:[] in
      false
    with Invalid_argument _ -> true
  in
  Alcotest.(check bool) "empty group rejected" true rejected

let test_glass_button_text_is_optional () =
  let icon_only_node = ref 0 in
  let text_node = ref 0 in
  let group_node = ref 0 in
  let action : Lui_element_combine.action =
    Lui_element_combine.Press
      { label = "New note"; icon = `plus; text = None; on_press = (fun _ -> ()) }
  in
  let with_press ~label ~icon ~text : Lui_element_combine.action =
    Lui_element_combine.Press
      { label; icon; text; on_press = (fun _ -> ()) }
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node icon_only_node
               (Lui_element_combine.buttons ~actions:[ action ]);
             capture_node text_node
               (Lui_element_combine.buttons
                  ~actions:
                    [ with_press ~label:"New note" ~icon:`plus
                        ~text:(Some "New note") ]);
             capture_node group_node
               (Lui_element_combine.buttons
                  ~actions:
                    [ with_press ~label:"Information" ~icon:`info
                        ~text:(Some "Info")
                    ; with_press ~label:"Settings" ~icon:`settings ~text:None
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

let test_glass_button_menu_action () =
  let picked = ref 0 in
  let single_node = ref 0 in
  let group_node = ref 0 in
  let menu_entries () =
    [ Lui_elements.menu_item ~text:"Duplicate"
        ~on_press:(fun _ -> incr picked) [] ]
  in
  let menu_action : Lui_element_combine.action =
    Lui_element_combine.Menu
      { label = "More actions"; icon = `ellipsis; text = None
      ; menu = menu_entries (); on_dismiss = None }
  in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node single_node
               (Lui_element_combine.buttons ~actions:[ menu_action ]);
             capture_node group_node
               (Lui_element_combine.buttons
                  ~actions:
                    [ Lui_element_combine.Press
                        { label = "New note"; icon = `plus; text = None
                        ; on_press = (fun _ -> ()) }
                    ; menu_action
                    ]);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let children_of parent =
    ops
    |> List.filter_map (function
         | Lui_protocol.InsertChild (p, child, index)
           when p = parent -> Some (index, child)
         | _ -> None)
    |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
    |> List.map snd
  in
  let kind_of node =
    List.find_map
      (function
       | Lui_protocol.CreateNode (id, kind) when id = node -> Some kind
       | _ -> None)
      ops
  in
  let has_property node property value =
    List.exists
      (function
       | Lui_protocol.SetProp (id, key, Lui_protocol.StringValue text) ->
         id = node && key = property && text = value
       | _ -> false)
      ops
  in
  (* A lone menu action still shares the glass capsule shape: a one-member
     button group wraps the sizing cell (box is not a legal toolbar child). *)
  Alcotest.(check bool) "single menu action capsule is a button group" true
    (kind_of !single_node = Some Lui_protocol.ButtonGroup);
  Alcotest.(check bool) "single menu action capsule is glass" true
    (has_property !single_node Lui_protocol.BackgroundValue "glass");
  let cells = children_of !single_node in
  Alcotest.(check int) "single capsule wraps one cell" 1
    (List.length cells);
  let single_cell = children_of (List.hd cells) in
  Alcotest.(check int) "single cell wraps one trigger" 1
    (List.length single_cell);
  let trigger = List.hd single_cell in
  Alcotest.(check bool) "menu action mounts a menu-trigger" true
    (kind_of trigger = Some Lui_protocol.MenuTrigger);
  let menu_children = children_of trigger in
  Alcotest.(check int) "trigger hosts one dropdown-menu" 1
    (List.length menu_children);
  Alcotest.(check bool) "trigger child is a dropdown-menu" true
    (kind_of (List.hd menu_children) = Some Lui_protocol.DropdownMenu);
  let items = children_of (List.hd menu_children) in
  Alcotest.(check int) "menu has its items" 1 (List.length items);
  Alcotest.(check bool) "menu item is a menu-item node" true
    (kind_of (List.hd items) = Some Lui_protocol.MenuItem);
  (* Mixed press + menu actions share one group capsule *)
  let group_children = children_of !group_node in
  Alcotest.(check int) "group has two cells" 2 (List.length group_children);
  Alcotest.(check bool) "first cell is the press button" true
    (kind_of (List.hd group_children) = Some Lui_protocol.Button);
  Alcotest.(check bool) "second cell wraps the trigger" true
    (kind_of (List.nth group_children 1) = Some Lui_protocol.Box);
  (* Menu items dispatch their own presses *)
  List.iter
    (fun node ->
       ignore (Lui_app.dispatch_event app (Lui_protocol.Press node)))
    items;
  flush_app app;
  Alcotest.(check int) "menu item press fires its handler" 1 !picked;
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

let test_pointer_events () =
  let open Lui_protocol in
  let detail =
    { x = 12.5; y = 34.5; modifiers = 11; button = 1; target_class = "a b" }
  in
  (* node extraction *)
  Alcotest.(check int) "press-detail node" 7
    (event_node (PressDetail (7, detail)));
  Alcotest.(check int) "pointer-down node" 7
    (event_node (PointerDown (7, detail)));
  Alcotest.(check int) "pointer-up node" 7
    (event_node (PointerUp (7, detail)));
  Alcotest.(check int) "pointer-enter node" 7
    (event_node (PointerEnter 7));
  Alcotest.(check int) "pointer-leave node" 7
    (event_node (PointerLeave 7));
  Alcotest.(check int) "context-menu node" 7
    (event_node (ContextMenuPress (7, detail)));
  (* kind-level support: press-capable kinds take the detail events *)
  List.iter
    (fun kind ->
       Alcotest.(check bool)
         (Printf.sprintf "%s admits press detail"
            (Lui_wire_schema.node_kind_name kind))
         true (event_supported kind (PressDetail (0, detail))))
    [ Button; Column; Radio; Select; Combobox; MenuItem; ListItem; Text;
      TableCell; TimelineItem; FileImage; BottomTab; SwipeAction ];
  Alcotest.(check bool) "input press-detail denied" false
    (event_supported Input (PressDetail (0, detail)));
  Alcotest.(check bool) "text pointer down/up" true
    (event_supported Text (PointerDown (0, detail))
     && event_supported Text (PointerUp (0, detail)));
  (* pointer enter/leave render on every kind but Root *)
  List.iter
    (fun kind ->
       Alcotest.(check bool)
         (Printf.sprintf "%s admits pointer enter/leave"
            (Lui_wire_schema.node_kind_name kind))
         true
         (event_supported kind (PointerEnter 0)
          && event_supported kind (PointerLeave 0)))
    [ Button; Column; Text; Input; Icon; TableCell ];
  Alcotest.(check bool) "root pointer enter denied" false
    (event_supported Root (PointerEnter 0));
  (* context-menu press on the kinds that can host a ContextMenu child *)
  List.iter
    (fun kind ->
       Alcotest.(check bool)
         (Printf.sprintf "%s admits context menu press"
            (Lui_wire_schema.node_kind_name kind))
         true (event_supported kind (ContextMenuPress (0, detail))))
    [ Button; ToggleButton; Toggle; Radio; Slider; NumberStepper; TextField;
      SecureField; Input; SearchField; Textarea; Checkbox; SwitchControl;
      Select; Combobox; MenuItem; ListItem; Accordion; Text; TableCell ];
  Alcotest.(check bool) "column context menu denied" false
    (event_supported Column (ContextMenuPress (0, detail)));
  (* standard nodes admit the family by kind — pointer-enabled only tells
     hosts to attach listeners (same role as press-enabled on Press) *)
  let props entries = List.to_seq entries |> Property_map.of_seq in
  let pointer_on = props [ (PointerEnabled, BoolValue true) ] in
  List.iter
    (fun event ->
       Alcotest.(check bool) "button admits by kind" true
         (event_supported_for_properties Button Property_map.empty event);
       Alcotest.(check bool) "button admits with prop" true
         (event_supported_for_properties Button pointer_on event))
    [ PressDetail (0, detail); PointerDown (0, detail);
      PointerUp (0, detail); PointerEnter 0; PointerLeave 0;
      ContextMenuPress (0, detail) ];
  Alcotest.(check bool) "input press-detail still denied" false
    (event_supported_for_properties Input pointer_on
       (PressDetail (0, detail)));
  Alcotest.(check bool) "input enter admitted" true
    (event_supported_for_properties Input pointer_on (PointerEnter 0));
  (* treeitem rows instead gate the family on pointer-enabled, mirroring
     how Press gates on press-enabled *)
  let treeitem entries =
    props ((RoleValue, StringValue "treeitem") :: entries)
  in
  Alcotest.(check bool) "treeitem detail gated" false
    (event_supported_for_properties Column (treeitem [])
       (PressDetail (0, detail)));
  Alcotest.(check bool) "treeitem enter gated" false
    (event_supported_for_properties Column (treeitem []) (PointerEnter 0));
  Alcotest.(check bool) "treeitem menu gated" false
    (event_supported_for_properties Column (treeitem [])
       (ContextMenuPress (0, detail)));
  Alcotest.(check bool) "treeitem detail with prop" true
    (event_supported_for_properties Column
       (treeitem [ (PointerEnabled, BoolValue true) ])
       (PressDetail (0, detail)));
  Alcotest.(check bool) "treeitem enter with prop" true
    (event_supported_for_properties Column
       (treeitem [ (PointerEnabled, BoolValue true) ])
       (PointerEnter 0));
  (* pointer-enabled is a common bool property (not on root) *)
  Alcotest.(check bool) "pointer-enabled on column" true
    (property_supported Column PointerEnabled);
  Alcotest.(check bool) "pointer-enabled on accordion" true
    (property_supported Accordion PointerEnabled);
  Alcotest.(check bool) "pointer-enabled not on root" false
    (property_supported Root PointerEnabled);
  Alcotest.(check bool) "pointer-enabled bool value" true
    (property_value_supported PointerEnabled (BoolValue true));
  Alcotest.(check bool) "pointer-enabled rejects int" false
    (property_value_supported PointerEnabled (IntValue 1))

let test_pointer_dispatch () =
  let details = ref 0 in
  let enters = ref 0 in
  let leaves = ref 0 in
  let menus = ref 0 in
  let button_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [
             capture_node button_node
               (Lui_elements.button
                  ~on_press_detail:(fun _event -> incr details)
                  ~on_pointer_enter:(fun _event -> incr enters)
                  ~on_pointer_leave:(fun _event -> incr leaves)
                  ~on_context_menu:(fun _event -> incr menus) []);
           ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let detail =
    { Lui_protocol.x = 1.0; y = 2.0; modifiers = 0; button = 0;
      target_class = "" }
  in
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.PressDetail (!button_node, detail)));
  ignore
    (Lui_app.dispatch_event app (Lui_protocol.PointerEnter !button_node));
  ignore
    (Lui_app.dispatch_event app (Lui_protocol.PointerLeave !button_node));
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.ContextMenuPress (!button_node, detail)));
  flush_app app;
  Alcotest.(check (list int)) "pointer handlers fired" [ 1; 1; 1; 1 ]
    [ !details; !enters; !leaves; !menus ];
  (* kind-unsupported events are still rejected at dispatch *)
  Alcotest.check_raises "unsupported event rejected"
    (Invalid_argument "event is unsupported by node kind")
    (fun () ->
       ignore
         (Lui_app.dispatch_event app
            (Lui_protocol.ValueChanged (!button_node, 0.5))));
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
    "lui-extension-v1|9:apple-map|profiles:ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,windows/gpui|standard-children:0|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map"));
  Alcotest.(check string) "marker fingerprint"
    "lui-extension-v1|16:apple-map-marker|profiles:ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,windows/gpui|standard-children:0|children:|properties:5:title:string:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map-marker"));
  Alcotest.(check string) "tweak fingerprint"
    "lui-tweak-v1|14:gallery-accent|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|properties:"
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
  (* Single-quoted literals are extracted the same way. *)
  let quoted_source =
    "fingerprint: 'lui-extension-v1|9:apple-map|profiles:ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,windows/gpui|standard-children:1|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:'"
  in
  match Lui_extension_check.check_registry registry quoted_source with
  | [ Lui_extension_check.Drifted { declaration; expected } ] ->
    Alcotest.(check string) "quoted identifier" "apple-map"
      declaration.host_identifier;
    Alcotest.(check bool) "expected has standard-children:0" true
      (contains expected "standard-children:0")
  | _ -> Alcotest.fail "expected exactly one drifted single-quoted fingerprint"


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
  Alcotest.(check bool) "menu-item keeps dropdown-menu" true
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

let test_list_suite_rules () =
  let open Lui_protocol in
  (* explicit sections *)
  Alcotest.(check bool) "list hosts section" true
    (child_kind_supported ListContainer ListSection);
  Alcotest.(check bool) "section rejects list parent" false
    (child_kind_supported ListSection ListSection);
  Alcotest.(check bool) "section outside list rejected" false
    (child_kind_supported Row ListSection);
  Alcotest.(check bool) "section hosts row" true
    (child_kind_supported ListSection ListItem);
  Alcotest.(check bool) "section rejects text row" false
    (child_kind_supported ListSection Text);
  Alcotest.(check bool) "section hosts header" true
    (child_kind_supported ListSection ListSectionHeader);
  Alcotest.(check bool) "section hosts footer" true
    (child_kind_supported ListSection ListSectionFooter);
  Alcotest.(check bool) "header needs section parent" false
    (child_kind_supported ListContainer ListSectionHeader);
  (* swipe actions *)
  Alcotest.(check bool) "row hosts swipe-actions" true
    (child_kind_supported ListItem SwipeActions);
  Alcotest.(check bool) "swipe-actions needs list-item" false
    (child_kind_supported ListSection SwipeActions);
  Alcotest.(check bool) "swipe-actions hosts action" true
    (child_kind_supported SwipeActions SwipeAction);
  Alcotest.(check bool) "action needs swipe-actions" false
    (child_kind_supported ListItem SwipeAction);
  Alcotest.(check bool) "swipe-actions rejects row" false
    (child_kind_supported SwipeActions ListItem);
  (* props *)
  Alcotest.(check bool) "section key" true
    (property_supported ListSection KeyValue);
  Alcotest.(check bool) "section separator" true
    (property_supported ListSection SeparatorValue);
  Alcotest.(check bool) "section drops text" false
    (property_supported ListSection TextValue);
  Alcotest.(check bool) "row key" true
    (property_supported ListItem KeyValue);
  Alcotest.(check bool) "row separator" true
    (property_supported ListItem SeparatorValue);
  Alcotest.(check bool) "key rejected elsewhere" false
    (property_supported Button KeyValue);
  Alcotest.(check bool) "list style" true
    (property_supported ListContainer StyleValue);
  Alcotest.(check bool) "list scroll token" true
    (property_supported ListContainer ScrollToken);
  Alcotest.(check bool) "list tracks visible range" true
    (property_supported ListContainer TrackVisibleRange);
  Alcotest.(check bool) "scroll props list-only" false
    (property_supported ListItem ScrollToken);
  Alcotest.(check bool) "action edge" true
    (property_supported SwipeAction EdgeValue);
  Alcotest.(check bool) "action icon" true
    (property_supported SwipeAction InlineIconName);
  Alcotest.(check bool) "action drops width" false
    (property_supported SwipeAction WidthValue);
  Alcotest.(check bool) "swipe-actions container bare" false
    (property_supported SwipeActions TextValue);
  (* prop value vocab *)
  Alcotest.(check bool) "style vocab" true
    (property_value_supported StyleValue (StringValue "inset-grouped"));
  Alcotest.(check bool) "style rejects junk" false
    (property_value_supported StyleValue (StringValue "cards"));
  Alcotest.(check bool) "anchor vocab" true
    (property_value_supported ScrollAnchor (StringValue "center"));
  Alcotest.(check bool) "separator vocab" true
    (property_value_supported SeparatorValue (StringValue "hidden"));
  Alcotest.(check bool) "edge vocab" true
    (property_value_supported EdgeValue (StringValue "leading"));
  Alcotest.(check bool) "token is int" true
    (property_value_supported ScrollToken (IntValue 3));
  Alcotest.(check bool) "token rejects string" false
    (property_value_supported ScrollToken (StringValue "3"));
  (* events *)
  Alcotest.(check bool) "list scroll-completed" true
    (event_supported ListContainer (ScrollCompleted (0, 0, "")));
  Alcotest.(check bool) "list visible-range" true
    (event_supported ListContainer (VisibleRange (0, 0, 0)));
  Alcotest.(check bool) "scroll events list-only" false
    (event_supported ListItem (ScrollCompleted (0, 0, "")));
  Alcotest.(check bool) "action press" true
    (event_supported SwipeAction (Press 0));
  Alcotest.(check bool) "row toggle" true
    (event_supported ListItem (ToggleChanged (0, true)));
  (* disclosure rows *)
  let props entries = List.to_seq entries |> Property_map.of_seq in
  Alcotest.(check bool) "disclosure row ok" true
    (node_properties_supported ListItem
       (props [ (Expanded, BoolValue true); (ToggleEnabled, BoolValue true) ]));
  Alcotest.(check bool) "expanded needs toggle-enabled" false
    (node_properties_supported ListItem
       (props [ (Expanded, BoolValue true) ]));
  Alcotest.(check bool) "tree level still needs treeitem" false
    (node_properties_supported ListItem
       (props [ (TreeLevel, IntValue 1); (Expanded, BoolValue true);
                (ToggleEnabled, BoolValue true) ]));
  (* swipe-action needs a label or icon *)
  Alcotest.(check bool) "action text ok" true
    (node_properties_supported SwipeAction
       (props [ (TextValue, StringValue "Archive") ]));
  Alcotest.(check bool) "action icon ok" true
    (node_properties_supported SwipeAction
       (props [ (InlineIconName, StringValue "trash") ]));
  Alcotest.(check bool) "bare action rejected" false
    (node_properties_supported SwipeAction (props []))

let test_file_picker () =
  let open Lui_protocol in
  Alcotest.(check bool) "file-picker hosts children" true
    (can_contain_children FilePicker);
  Alcotest.(check bool) "picked is a file-picker event" true
    (event_supported_for_properties FilePicker Property_map.empty
       (Picked (0, "{}")));
  Alcotest.(check bool) "dismiss is a file-picker event" true
    (event_supported_for_properties FilePicker Property_map.empty
       (Dismiss 0));
  Alcotest.(check bool) "picked is not a button event" false
    (event_supported_for_properties Button Property_map.empty
       (Picked (0, "{}")));
  Alcotest.(check bool) "request prop allowed" true
    (property_supported FilePicker PickerRequest);
  Alcotest.(check bool) "types prop allowed" true
    (property_supported FilePicker PickerTypes);
  Alcotest.(check bool) "multiple prop allowed" true
    (property_supported FilePicker PickerMultiple);
  Alcotest.(check bool) "source prop allowed" true
    (property_supported FilePicker PickerSource);
  Alcotest.(check bool) "completion prop allowed" true
    (property_supported FilePicker PickerCompletion);
  Alcotest.(check bool) "text prop rejected" false
    (property_supported FilePicker TextValue);
  Alcotest.(check bool) "request accepts a string" true
    (property_value_supported PickerRequest (StringValue "op-1"));
  Alcotest.(check bool) "request accepts an int" true
    (property_value_supported PickerRequest (IntValue 7));
  Alcotest.(check bool) "multiple accepts bool" true
    (property_value_supported PickerMultiple (BoolValue true));
  Alcotest.(check bool) "source accepts camera" true
    (property_value_supported PickerSource (StringValue "camera"));
  Alcotest.(check bool) "source rejects junk" false
    (property_value_supported PickerSource (StringValue "screen"));
  let picked_payloads = ref [] in
  let dismissed = ref 0 in
  let picker_node = ref 0 in
  let int_picker_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node picker_node
               (Lui_elements.file_picker ~source:`photos
                  ~request:(`String "op-1") ~types:"public.image" ~multiple:true
                  ~completion:(`String "")
                  ~on_picked:(fun event ->
                    match event with
                    | Picked (_, payload) ->
                      picked_payloads := payload :: !picked_payloads
                    | _ -> ())
                  ~on_dismiss:(fun _ -> incr dismissed)
                  []);
             capture_node int_picker_node
               (Lui_elements.file_picker ~request:(`Int 7) []) ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let kind_of node =
    List.find_map
      (function
       | CreateNode (id, kind) when id = node -> Some kind
       | _ -> None)
      ops
  in
  let prop_value node property =
    List.find_map
      (function
       | SetProp (id, key, value) when id = node && key = property ->
         Some value
       | _ -> None)
      ops
  in
  Alcotest.(check bool) "node is a file-picker" true
    (kind_of !picker_node = Some FilePicker);
  Alcotest.(check bool) "request wired" true
    (prop_value !picker_node PickerRequest = Some (StringValue "op-1"));
  Alcotest.(check bool) "int request wired" true
    (prop_value !int_picker_node PickerRequest = Some (IntValue 7));
  Alcotest.(check bool) "types wired" true
    (prop_value !picker_node PickerTypes = Some (StringValue "public.image"));
  Alcotest.(check bool) "multiple wired" true
    (prop_value !picker_node PickerMultiple = Some (BoolValue true));
  Alcotest.(check bool) "source wired" true
    (prop_value !picker_node PickerSource = Some (StringValue "photos"));
  ignore
    (Lui_app.dispatch_event app
       (Picked (!picker_node, {|{"request":"op-1","files":[]}|})));
  ignore (Lui_app.dispatch_event app (Dismiss !picker_node));
  flush_app app;
  Alcotest.(check (list string)) "picked delivered"
    [ {|{"request":"op-1","files":[]}|} ] !picked_payloads;
  Alcotest.(check int) "dismiss delivered" 1 !dismissed;
  ignore (Lui_app.dispose app)

let test_media_file_rules () =
  let open Lui_protocol in
  Alcotest.(check bool) "link is container" true
    (can_contain_children Link);
  Alcotest.(check bool) "file-image is leaf" false
    (can_contain_children FileImage);
  Alcotest.(check bool) "file-preview is leaf" false
    (can_contain_children FilePreview);
  Alcotest.(check bool) "link allows url" true
    (property_supported Link UrlValue);
  Alcotest.(check bool) "link allows text" true
    (property_supported Link TextValue);
  Alcotest.(check bool) "link allows icon" true
    (property_supported Link InlineIconName);
  Alcotest.(check bool) "link drops path" false
    (property_supported Link PathValue);
  Alcotest.(check bool) "file-image allows path" true
    (property_supported FileImage PathValue);
  Alcotest.(check bool) "file-image allows image-fit" true
    (property_supported FileImage ImageFitValue);
  Alcotest.(check bool) "image-fit rejects stretching" false
    (property_value_supported ImageFitValue (StringValue "stretch"));
  Alcotest.(check bool) "file-image allows max-pixel-size" true
    (property_supported FileImage MaxPixelSize);
  Alcotest.(check bool) "file-image allows press" true
    (property_supported FileImage PressEnabled);
  Alcotest.(check bool) "file-image drops url" false
    (property_supported FileImage UrlValue);
  Alcotest.(check bool) "file-preview allows path" true
    (property_supported FilePreview PathValue);
  Alcotest.(check bool) "file-preview drops width" false
    (property_supported FilePreview WidthValue);
  Alcotest.(check bool) "file-preview keeps accessibility-identifier" true
    (property_supported FilePreview AccessibilityIdentifier);
  Alcotest.(check bool) "max-pixel-size positive" true
    (property_value_supported MaxPixelSize (IntValue 1024));
  Alcotest.(check bool) "max-pixel-size rejects zero" false
    (property_value_supported MaxPixelSize (IntValue 0));
  Alcotest.(check bool) "path accepts string" true
    (property_value_supported PathValue (StringValue "/x.png"));
  Alcotest.(check bool) "url accepts string" true
    (property_value_supported UrlValue (StringValue "https://e.com"));
  Alcotest.(check bool) "file-image press event" true
    (event_supported FileImage (Press 0));
  Alcotest.(check bool) "file-preview dismiss event" true
    (event_supported FilePreview (Dismiss 0));
  Alcotest.(check bool) "link drops dismiss" false
    (event_supported Link (Dismiss 0));
  let props entries = List.to_seq entries |> Property_map.of_seq in
  Alcotest.(check bool) "file-image needs path" false
    (node_properties_supported FileImage (props []));
  Alcotest.(check bool) "file-image ok" true
    (node_properties_supported FileImage
       (props [ (PathValue, StringValue "/x.png") ]));
  Alcotest.(check bool) "file-preview needs path" false
    (node_properties_supported FilePreview (props []));
  Alcotest.(check bool) "link needs url" false
    (node_properties_supported Link (props []));
  Alcotest.(check bool) "link ok" true
    (node_properties_supported Link
       (props [ (UrlValue, StringValue "https://e.com") ]))

let media_view _context _model _send =
  Lui_elements.column
    [
      Lui_elements.link ~url:"https://example.com" ~text:"Example" [];
      Lui_elements.file_image ~path:"/tmp/pic.png" ~max_pixel_size:512 ~fit:`fill [];
      Lui_elements.file_preview ~path:"/tmp/doc.pdf" [];
    ]

let test_media_file_mount () =
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      media_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let open Lui_protocol in
  let creates kind =
    List.exists (function CreateNode (_, k) -> k = kind | _ -> false) ops
  in
  Alcotest.(check bool) "link mounted" true (creates Link);
  Alcotest.(check bool) "file-image mounted" true (creates FileImage);
  Alcotest.(check bool) "file-preview mounted" true (creates FilePreview);
  Alcotest.(check bool) "url prop set" true
    (List.exists
       (function
        | SetProp (_, UrlValue, StringValue "https://example.com") -> true
        | _ -> false)
       ops);
  Alcotest.(check bool) "path prop set" true
    (List.exists
       (function
        | SetProp (_, PathValue, StringValue "/tmp/pic.png") -> true
        | _ -> false)
       ops);
  Alcotest.(check bool) "proportional fill prop set" true
    (List.exists (function SetProp (_, ImageFitValue, StringValue "fill") -> true | _ -> false) ops);
  Alcotest.(check bool) "max-pixel-size prop set" true
    (List.exists
       (function
        | SetProp (_, MaxPixelSize, IntValue 512) -> true
        | _ -> false)
       ops);
  ignore (Lui_app.dispose app)

let test_edge_overlay_fit_rules () =
  let open Lui_protocol in
  Alcotest.(check bool) "edge-inset contains children" true
    (can_contain_children EdgeInset);
  Alcotest.(check bool) "overlay contains children" true
    (can_contain_children Overlay);
  Alcotest.(check bool) "view-that-fits contains children" true
    (can_contain_children ViewThatFits);
  Alcotest.(check bool) "overlay accepts a list child" true
    (child_kind_supported Overlay ListContainer);
  Alcotest.(check bool) "overlay accepts a row child" true
    (child_kind_supported Overlay Row);
  Alcotest.(check bool) "overlay rejects root child" false
    (child_kind_supported Overlay Root);
  Alcotest.(check bool) "edge-inset holds edge" true
    (property_supported EdgeInset EdgeValue);
  Alcotest.(check bool) "edge-inset holds visible" true
    (property_supported EdgeInset Visible);
  Alcotest.(check bool) "edge-inset holds gap" true
    (property_supported EdgeInset Gap);
  Alcotest.(check bool) "edge-inset styles background" true
    (property_supported EdgeInset BackgroundValue);
  Alcotest.(check bool) "row drops edge" false
    (property_supported Row EdgeValue);
  Alcotest.(check bool) "row drops visible" false
    (property_supported Row Visible);
  Alcotest.(check bool) "view-that-fits holds orientation" true
    (property_supported ViewThatFits OrientationValue);
  Alcotest.(check bool) "view-that-fits drops edge" false
    (property_supported ViewThatFits EdgeValue);
  Alcotest.(check bool) "alignment lands on overlay" true
    (property_supported Overlay AlignmentValue);
  Alcotest.(check bool) "alignment lands on overlay children" true
    (property_supported Text AlignmentValue);
  (* Restrictive kinds still carry the hint so e.g. an aligned
     menu-trigger overlay child validates. *)
  Alcotest.(check bool) "alignment lands on restrictive kinds" true
    (property_supported MenuTrigger AlignmentValue);
  Alcotest.(check bool) "root drops alignment" false
    (property_supported Root AlignmentValue);
  Alcotest.(check bool) "edge-inset takes foreground" true
    (property_supported EdgeInset ForegroundValue);
  Alcotest.(check bool) "overlay takes foreground" true
    (property_supported Overlay ForegroundValue);
  Alcotest.(check bool) "view-that-fits takes foreground" true
    (property_supported ViewThatFits ForegroundValue);
  Alcotest.(check bool) "edge accepts top" true
    (property_value_supported EdgeValue (StringValue "top"));
  Alcotest.(check bool) "edge accepts leading" true
    (property_value_supported EdgeValue (StringValue "leading"));
  Alcotest.(check bool) "edge rejects side anchors" false
    (property_value_supported EdgeValue (StringValue "left"));
  Alcotest.(check bool) "visible takes a bool" true
    (property_value_supported Visible (BoolValue false));
  Alcotest.(check bool) "alignment accepts corner" true
    (property_value_supported AlignmentValue
       (StringValue "bottom-trailing"));
  Alcotest.(check bool) "alignment rejects anchor vocab" false
    (property_value_supported AlignmentValue (StringValue "above"));
  let props entries = List.to_seq entries |> Property_map.of_seq in
  Alcotest.(check bool) "edge-inset needs edge" false
    (node_properties_supported EdgeInset (props []));
  Alcotest.(check bool) "edge-inset with edge ok" true
    (node_properties_supported EdgeInset
       (props [ (EdgeValue, StringValue "bottom") ]))

let test_data_attrs_protocol () =
  let open Lui_protocol in
  (* name policy: data-*/aria-* prefixes plus the three bare names *)
  List.iter
    (fun name ->
       Alcotest.(check bool) name true (data_attr_name_ok name))
    [ "data-x"; "data-testid"; "aria-label"; "aria-hidden"; "role"
    ; "tabindex"; "draggable" ];
  List.iter
    (fun name ->
       Alcotest.(check bool) name false (data_attr_name_ok name))
    [ "id"; "class"; "style"; "onclick"; "data-"; "aria-"; "role-"
    ; "Data-x"; "data"; "aria" ];
  (* serialization round-trip *)
  let pairs =
    [ ("data-testid", "greeting"); ("role", "note")
    ; ("aria-label", "a b c"); ("tabindex", "-1") ]
  in
  Alcotest.(check (list (pair string string))) "round-trip" pairs
    (data_attrs_decode (data_attrs_encode pairs));
  Alcotest.(check (list (pair string string))) "empty decodes" []
    (data_attrs_decode (data_attrs_encode []));
  Alcotest.(check (list (pair string string))) "bare payload" []
    (data_attrs_decode "");
  (* call-time validation raises *)
  Alcotest.check_raises "encode rejects id"
    (Invalid_argument "data-attrs: unsupported attribute name: id")
    (fun () -> ignore (data_attrs_encode [ ("id", "x") ]));
  Alcotest.check_raises "encode rejects separator in value"
    (Invalid_argument "data-attrs: control character in name or value")
    (fun () -> ignore (data_attrs_encode [ ("data-x", "a\x1fb") ]));
  Alcotest.check_raises "decode rejects malformed"
    (Invalid_argument "data-attrs: malformed payload")
    (fun () -> ignore (data_attrs_decode "no-separator-here"));
  (* wire-value validation *)
  Alcotest.(check bool) "valid payload" true
    (data_attrs_value_ok
       (data_attrs_encode [ ("data-x", "1"); ("role", "note") ]));
  Alcotest.(check bool) "id payload rejected" false
    (data_attrs_value_ok "id\x1fx");
  Alcotest.(check bool) "mixed payload rejected" false
    (data_attrs_value_ok "data-x\x1f1\x1eonclick\x1fy");
  Alcotest.(check bool) "malformed payload rejected" false
    (data_attrs_value_ok "data-x");
  (* prop admit/deny per kind *)
  Alcotest.(check bool) "data-attrs on text" true
    (property_supported Text DataAttrs);
  Alcotest.(check bool) "data-attrs on toast" true
    (property_supported Toast DataAttrs);
  Alcotest.(check bool) "data-attrs on kbd" true
    (property_supported Kbd DataAttrs);
  Alcotest.(check bool) "data-attrs off tooltip" false
    (property_supported Tooltip DataAttrs);
  Alcotest.(check bool) "data-attrs off context-menu" false
    (property_supported ContextMenu DataAttrs);
  Alcotest.(check bool) "data-attrs string value" true
    (property_value_supported DataAttrs (StringValue "data-x\x1f1"));
  Alcotest.(check bool) "data-attrs rejects int" false
    (property_value_supported DataAttrs (IntValue 1))

let test_as_protocol () =
  let open Lui_protocol in
  (* phrasing kinds only *)
  Alcotest.(check bool) "as on text" true (property_supported Text As);
  Alcotest.(check bool) "as on heading" true (property_supported Heading As);
  Alcotest.(check bool) "as on paragraph" true
    (property_supported Paragraph As);
  Alcotest.(check bool) "as on label" true (property_supported Label As);
  Alcotest.(check bool) "as off button" false (property_supported Button As);
  Alcotest.(check bool) "as off box" false (property_supported Box As);
  Alcotest.(check bool) "as off tooltip" false (property_supported Tooltip As);
  (* vocabulary admits every supported kind tag, rejects unknown *)
  List.iter
    (fun tag ->
       Alcotest.(check bool) tag true (element_tag_known tag))
    [ "span"; "em"; "strong"; "b"; "i"; "u"; "s"; "del"; "mark"; "small"
    ; "code"; "kbd"; "sub"; "sup"; "pre"; "h1"; "h2"; "h3"; "h4"; "h5"
    ; "h6"; "p"; "div"; "label" ];
  Alcotest.(check bool) "marquee unknown" false
    (element_tag_known "marquee");
  Alcotest.(check bool) "a unknown" false (element_tag_known "a");
  (* per-kind gating: block tags on phrasing kinds are refused *)
  Alcotest.(check bool) "text em ok" true
    (property_value_supported_for_kind Text As (StringValue "em"));
  Alcotest.(check bool) "text div refused" false
    (property_value_supported_for_kind Text As (StringValue "div"));
  Alcotest.(check bool) "text h1 refused" false
    (property_value_supported_for_kind Text As (StringValue "h1"));
  Alcotest.(check bool) "heading h3 ok" true
    (property_value_supported_for_kind Heading As (StringValue "h3"));
  Alcotest.(check bool) "heading em refused" false
    (property_value_supported_for_kind Heading As (StringValue "em"));
  Alcotest.(check bool) "paragraph pre ok" true
    (property_value_supported_for_kind Paragraph As (StringValue "pre"));
  Alcotest.(check bool) "label label ok" true
    (property_value_supported_for_kind Label As (StringValue "label"));
  Alcotest.(check bool) "kind-less value check" true
    (property_value_supported As (StringValue "kbd"));
  Alcotest.(check bool) "non-string refused" false
    (property_value_supported_for_kind Text As (IntValue 1))

let data_attrs_view context _model _send =
  Lui_elements.column
    [
      Lui_elements.text ~as_:`Em ~value:"hello"
        ~data_attrs:[ ("data-testid", "greeting"); ("role", "note") ] [];
      Lui_elements.text ~value:"reactive"
        ~data_attrs_signal:
          (Signal.constant context.Lui_ui.ui_scheduler
             [ ("data-mood", "ok") ])
        [];
      Lui_elements.heading ~level:2 ~as_:`H2 ~value:"Title" [];
      Lui_elements.paragraph ~as_:`P ~value:"para" [];
      Lui_elements.label ~as_:`Span ~value:"lbl" [];
      Lui_elements.kbd ~data_attrs:[ ("aria-label", "key") ] ~value:"esc" [];
    ]

let test_data_attrs_and_as_emit () =
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      data_attrs_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let open Lui_protocol in
  let emitted property value =
    List.exists
      (function
        | SetProp (_, property', value') ->
            property' = property && value' = value
        | _ -> false)
      ops
  in
  Alcotest.(check bool) "data-attrs payload emitted" true
    (emitted DataAttrs
       (StringValue "data-testid\x1fgreeting\x1erole\x1fnote"));
  Alcotest.(check bool) "signal payload encoded" true
    (emitted DataAttrs (StringValue "data-mood\x1fok"));
  Alcotest.(check bool) "aria on kbd" true
    (emitted DataAttrs (StringValue "aria-label\x1fkey"));
  Alcotest.(check bool) "text as em" true
    (emitted As (StringValue "em"));
  Alcotest.(check bool) "heading as h2" true
    (emitted As (StringValue "h2"));
  Alcotest.(check bool) "paragraph as p" true
    (emitted As (StringValue "p"));
  Alcotest.(check bool) "label as span" true
    (emitted As (StringValue "span"))

let test_vocab_batch2 () =
  let open Lui_protocol in
  (* br leaf kind *)
  Alcotest.(check bool) "br is a leaf" false (can_contain_children Br);
  (* image url source + alt/loading/referrer-policy/on_load *)
  Alcotest.(check bool) "url allowed on image" true
    (property_supported Image UrlValue);
  Alcotest.(check bool) "alt allowed on image" true
    (property_supported Image AltValue);
  Alcotest.(check bool) "loading eager accepted" true
    (property_value_supported LoadingValue (StringValue "eager"));
  Alcotest.(check bool) "loading junk rejected" false
    (property_value_supported LoadingValue (StringValue "defer"));
  Alcotest.(check bool) "referrer-policy accepted" true
    (property_value_supported ReferrerPolicy
       (StringValue "strict-origin-when-cross-origin"));
  Alcotest.(check bool) "referrer-policy junk rejected" false
    (property_value_supported ReferrerPolicy (StringValue "always"));
  Alcotest.(check bool) "load is an image event" true
    (event_supported_for_properties Image Property_map.empty (Load 0));
  (* link ~target *)
  Alcotest.(check bool) "target allowed on link" true
    (property_supported Link TargetValue);
  Alcotest.(check bool) "blank accepted" true
    (property_value_supported TargetValue (StringValue "_blank"));
  Alcotest.(check bool) "junk target rejected" false
    (property_value_supported TargetValue (StringValue "popup"));
  (* ~opacity *)
  Alcotest.(check bool) "opacity allowed on column" true
    (property_supported Column Opacity);
  Alcotest.(check bool) "opacity rejected on leaf" false
    (property_supported Icon Opacity);
  Alcotest.(check bool) "opacity range check" false
    (property_value_supported Opacity (FloatValue 1.5));
  (* ~display:`contents *)
  Alcotest.(check bool) "display allowed on row" true
    (property_supported Row DisplayValue);
  Alcotest.(check bool) "contents accepted" true
    (property_value_supported DisplayValue (StringValue "contents"));
  Alcotest.(check bool) "grid rejected" false
    (property_value_supported DisplayValue (StringValue "grid"));
  (* ~tooltip/~shortcut_hint *)
  Alcotest.(check bool) "tooltip on button" true
    (property_supported Button TooltipText);
  Alcotest.(check bool) "tooltip-keys on menu-item" true
    (property_supported MenuItem TooltipKeys);
  Alcotest.(check bool) "tooltip rejected on column" false
    (property_supported Column TooltipText);
  (* input ~kind:`color (range stays mapped to `slider`) *)
  Alcotest.(check bool) "input-type on input" true
    (property_supported Input InputType);
  Alcotest.(check bool) "color accepted" true
    (property_value_supported InputType (StringValue "color"));
  Alcotest.(check bool) "range rejected" false
    (property_value_supported InputType (StringValue "range"));
  (* file_picker ~accept/~directory *)
  Alcotest.(check bool) "accept admitted" true
    (property_supported FilePicker PickerAccept);
  Alcotest.(check bool) "directory admitted" true
    (property_supported FilePicker PickerDirectory);
  Alcotest.(check bool) "accept rejected elsewhere" false
    (property_supported Button PickerAccept);
  (* popover *)
  Alcotest.(check bool) "popover hosts children" true
    (can_contain_children Popover);
  Alcotest.(check bool) "dismiss is a popover event" true
    (event_supported_for_properties Popover Property_map.empty (Dismiss 0));
  Alcotest.(check bool) "anchor props on popover" true
    (property_supported Popover AnchorValue);
  Alcotest.(check bool) "x on popover" true
    (property_supported Popover PopupX);
  Alcotest.(check bool) "x rejected elsewhere" false
    (property_supported Column PopupX);
  Alcotest.(check bool) "available-height on popover" true
    (property_supported Popover AvailableHeight);
  Alcotest.(check bool) "role on popover" true
    (property_supported Popover RoleValue);
  Alcotest.(check bool) "menu role accepted on popover" true
    (property_value_supported_for_kind Popover RoleValue
       (StringValue "menu"));
  Alcotest.(check bool) "treeitem role rejected on popover" false
    (property_value_supported_for_kind Popover RoleValue
       (StringValue "treeitem"));
  let with_x =
    Property_map.add PopupX (FloatValue 10.0) Property_map.empty
  in
  Alcotest.(check bool) "x without y rejected" false
    (node_properties_supported Popover with_x);
  let with_xy = Property_map.add PopupY (FloatValue 20.0) with_x in
  Alcotest.(check bool) "x and y accepted" true
    (node_properties_supported Popover with_xy);
  let with_xy_anchor =
    Property_map.add AnchorValue (StringValue "below") with_xy
  in
  Alcotest.(check bool) "point + anchor rejected" false
    (node_properties_supported Popover with_xy_anchor);
  let popover_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node popover_node
               (Lui_elements.popover ~at:(10.0, 20.0)
                  ~available_height:200.0 ~role:`menu []) ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let emitted property value =
    List.exists
      (function
         | Lui_protocol.SetProp (id, property', value') ->
           id = !popover_node && property' = property && value' = value
         | _ -> false)
      ops
  in
  Alcotest.(check bool) "popover node created" true
    (List.exists
       (function
          | Lui_protocol.CreateNode (id, Lui_protocol.Popover) ->
            id = !popover_node
          | _ -> false)
       ops);
  Alcotest.(check bool) "x emitted" true
    (emitted PopupX (FloatValue 10.0));
  Alcotest.(check bool) "y emitted" true
    (emitted PopupY (FloatValue 20.0));
  Alcotest.(check bool) "available-height emitted" true
    (emitted AvailableHeight (FloatValue 200.0));
  Alcotest.(check bool) "role emitted" true
    (emitted RoleValue (StringValue "menu"))

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
                || (kind <> Lui_protocol.Root
                    && property = Lui_protocol.AlignmentValue)
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

let test_number_stepper_props () =
  let changes = ref [] in
  let stepper_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node stepper_node
               (Lui_elements.number_stepper ~value:5.0 ~min:0.0 ~max:3660.0
                  ~step:1.0 ~text:"Days"
                  ~on_value_changed:(fun event ->
                     match event with
                     | Lui_protocol.ValueChanged (_, value) ->
                         changes := value :: !changes
                     | _ -> ())
                  []) ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  Alcotest.(check bool) "number-stepper created" true
    (List.exists
       (function
          | Lui_protocol.CreateNode (_, Lui_protocol.NumberStepper) -> true
          | _ -> false)
       ops);
  let emitted property value =
    List.exists
      (function
         | Lui_protocol.SetProp (_, property', value') ->
           property' = property && value' = value
         | _ -> false)
      ops
  in
  Alcotest.(check bool) "value" true
    (emitted Lui_protocol.ProgressValue (Lui_protocol.FloatValue 5.0));
  Alcotest.(check bool) "min" true
    (emitted Lui_protocol.MinValue (Lui_protocol.FloatValue 0.0));
  Alcotest.(check bool) "max" true
    (emitted Lui_protocol.MaxValue (Lui_protocol.FloatValue 3660.0));
  Alcotest.(check bool) "step" true
    (emitted Lui_protocol.StepValue (Lui_protocol.FloatValue 1.0));
  Alcotest.(check bool) "text" true
    (emitted Lui_protocol.TextValue (Lui_protocol.StringValue "Days"));
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.ValueChanged (!stepper_node, 5.0)));
  ignore
    (Lui_app.dispatch_event app
       (Lui_protocol.ValueChanged (!stepper_node, 6.0)));
  flush_app app;
  Alcotest.(check (list (float 0.0))) "echo dropped, change delivered"
    [ 6.0 ] !changes;
  ignore (Lui_app.dispose app)

let test_number_stepper_schema () =
  let open Lui_protocol in
  List.iter
    (fun (property, kinds) ->
       List.iter
         (fun kind ->
            Alcotest.(check bool)
              (Printf.sprintf "%s x %s"
                 (Lui_wire_schema.property_name property)
                 (Lui_wire_schema.node_kind_name kind))
              true (property_supported kind property))
         kinds)
    [ (MinValue, [ NumberStepper ]);
      (MaxValue, [ NumberStepper ]);
      (StepValue, [ NumberStepper ]);
      (Detents, [ Sheet ]);
      (Sizing, [ Sheet ]) ];
  Alcotest.(check bool) "min off slider" false
    (property_supported Slider MinValue);
  Alcotest.(check bool) "detents off stepper" false
    (property_supported NumberStepper Detents);
  Alcotest.(check bool) "value on stepper" true
    (property_supported NumberStepper ProgressValue);
  Alcotest.(check bool) "enabled on stepper" true
    (property_supported NumberStepper Enabled);
  Alcotest.(check bool) "value-changed on stepper" true
    (event_supported NumberStepper (ValueChanged (0, 1.0)));
  Alcotest.(check bool) "value-changed off button" false
    (event_supported Button (ValueChanged (0, 1.0)));
  Alcotest.(check bool) "positive step" true
    (property_value_supported StepValue (FloatValue 0.5));
  Alcotest.(check bool) "zero step rejected" false
    (property_value_supported StepValue (FloatValue 0.0));
  Alcotest.(check bool) "finite min" true
    (property_value_supported MinValue (FloatValue 1.0));
  Alcotest.(check bool) "sizing token" true
    (property_value_supported Sizing (StringValue "form"));
  Alcotest.(check bool) "unknown sizing rejected" false
    (property_value_supported Sizing (StringValue "huge"));
  Alcotest.(check bool) "detents is freeform" true
    (property_value_supported Detents (StringValue "medium,0.4,large"));
  let props entries = List.to_seq entries |> Property_map.of_seq in
  Alcotest.(check bool) "stepper node ok" true
    (node_properties_supported NumberStepper
       (props [ (TextValue, StringValue "Days");
                (ProgressValue, FloatValue 1.0);
                (MinValue, FloatValue 0.0);
                (MaxValue, FloatValue 10.0) ]));
  Alcotest.(check bool) "stepper needs value" false
    (node_properties_supported NumberStepper
       (props [ (TextValue, StringValue "Days") ]));
  Alcotest.(check bool) "stepper needs label or text" false
    (node_properties_supported NumberStepper
       (props [ (ProgressValue, FloatValue 1.0) ]));
  Alcotest.(check bool) "label suffices" true
    (node_properties_supported NumberStepper
       (props [ (AccessibilityLabel, StringValue "Days");
                (ProgressValue, FloatValue 1.0) ]));
  Alcotest.(check bool) "min over max rejected" false
    (node_properties_supported NumberStepper
       (props [ (TextValue, StringValue "Days");
                (ProgressValue, FloatValue 1.0);
                (MinValue, FloatValue 10.0);
                (MaxValue, FloatValue 0.0) ]))

let test_sheet_presentation_props () =
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_elements.sheet ~text:"Settings"
               ~detents:"medium,large" ~sizing:"form" [] ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  Alcotest.(check bool) "sheet created" true
    (List.exists
       (function
          | Lui_protocol.CreateNode (_, Lui_protocol.Sheet) -> true
          | _ -> false)
       ops);
  Alcotest.(check bool) "detents emitted" true
    (List.exists
       (function
          | Lui_protocol.SetProp (_, Lui_protocol.Detents,
                                  Lui_protocol.StringValue "medium,large") ->
            true
          | _ -> false)
       ops);
  Alcotest.(check bool) "sizing emitted" true
    (List.exists
       (function
          | Lui_protocol.SetProp (_, Lui_protocol.Sizing,
                                  Lui_protocol.StringValue "form") -> true
          | _ -> false)
       ops);
  Alcotest.(check bool) "detents only on sheet" true
    (Lui_protocol.property_supported Lui_protocol.Sheet Lui_protocol.Detents);
  Alcotest.(check bool) "detents off dialog" false
    (Lui_protocol.property_supported Lui_protocol.Dialog
       Lui_protocol.Detents);
  ignore (Lui_app.dispose app)

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

(* Lui_split: the Bonsplit-style tabbed split-pane extension set. *)

let split_fingerprint identifier =
  let registry = Lui_split.registry () in
  match Lui_extension.schema registry identifier with
  | Some schema -> Lui_extension.fingerprint schema
  | None -> Alcotest.fail ("unregistered schema " ^ identifier)

let test_split_fingerprints () =
  Alcotest.(check string) "split-view fingerprint"
    "lui-extension-v1|10:split-view|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:"
    (split_fingerprint "split-view");
  Alcotest.(check string) "split-branch fingerprint"
    "lui-extension-v1|12:split-branch|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]"
    (split_fingerprint "split-branch");
  Alcotest.(check string) "split-pane fingerprint"
    "lui-extension-v1|10:split-pane|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]"
    (split_fingerprint "split-pane");
  Alcotest.(check string) "split-tab fingerprint"
    "lui-extension-v1|9:split-tab|profiles:android/kotlin,ios/swiftui,linux/gpui,macos/gpui,macos/swiftui,web/web,windows/gpui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:"
    (split_fingerprint "split-tab")

(* Every host source that carries lui-extension-v1 literals is checked so
   drift fails here rather than as a blank screen on that platform. The
   files are read from the source tree directly; test/dune only tracks the
   gallery source as a dependency. *)
let split_host_sources () =
  let root = source_root () in
  [ "platform/apple/Sources/LUIAppleBackend/LUISplit.swift";
    "platform/android/lui/src/main/kotlin/dev/lui/LuiSplit.kt";
    "platform/web/src/lui-split.js" ]
  |> List.filter_map (fun rel ->
       let path = Filename.concat root rel in
       if Sys.file_exists path then Some (read_file path) else None)

let test_split_host_literals_in_sync () =
  let registry = Lui_split.registry () in
  let mismatches =
    split_host_sources ()
    |> List.concat_map (Lui_extension_check.check_registry registry)
  in
  match mismatches with
  | [] -> ()
  | _ ->
    Alcotest.failf "extension fingerprint drift:\n%s"
      (Lui_extension_check.describe_mismatches mismatches)

let split_view_fixture _context _model_source _send =
  Lui_split.split_view
    [ Lui_split.split_branch ~orientation:`horizontal ~ratio:0.4
        [ Lui_split.split_pane ~pane_id:"editor"
            [ Lui_split.split_tab ~tab_id:"welcome" ~title:"Welcome"
                [ Lui_elements.text ~value:"editor content" [] ];
              Lui_split.split_tab ~tab_id:"repl" ~title:"REPL" ~closable:false
                [ Lui_elements.text ~value:"repl content" [] ] ];
          Lui_split.split_pane ~pane_id:"outline"
            [ Lui_split.split_tab ~tab_id:"toc" ~title:"Outline"
                [ Lui_elements.text ~value:"outline content" [] ] ] ] ]

let test_split_extension_ops () =
  batches := [];
  let backend =
    {
      Lui_protocol.backend_profile =
        Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost;
      apply_batch = (fun batch -> batches := batch :: !batches; true);
    }
  in
  let app =
    Lui_app.create_with_extensions backend
      (Lui_split.registry ()) ()
      (fun model _action -> model)
      split_view_fixture
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let creates identifier =
    List.exists
      (function
       | Lui_protocol.CreateExtension (_, id, _) -> String.equal id identifier
       | _ -> false)
      ops
  in
  Alcotest.(check bool) "creates split-view" true (creates "split-view");
  Alcotest.(check bool) "creates split-branch" true (creates "split-branch");
  Alcotest.(check bool) "creates split-pane (x2)" true
    (List.length
       (List.filter
          (function
           | Lui_protocol.CreateExtension (_, "split-pane", _) -> true
           | _ -> false)
          ops)
     = 2);
  Alcotest.(check bool) "creates split-tab (x3)" true
    (List.length
       (List.filter
          (function
           | Lui_protocol.CreateExtension (_, "split-tab", _) -> true
           | _ -> false)
          ops)
     = 3);
  Alcotest.(check bool) "pane-id prop lands" true
    (List.exists
       (function
        | Lui_protocol.SetExtensionProp (_, "pane-id",
                                         Lui_protocol.StringValue "outline") ->
          true
        | _ -> false)
       ops);
  Alcotest.(check bool) "ratio prop lands" true
    (List.exists
       (function
        | Lui_protocol.SetExtensionProp (_, "ratio",
                                         Lui_protocol.FloatValue r) ->
          Float.abs (r -. 0.4) < 0.001
        | _ -> false)
       ops);
  Alcotest.(check bool) "orientation prop lands" true
    (List.exists
       (function
        | Lui_protocol.SetExtensionProp (_, "orientation",
                                         Lui_protocol.StringValue "horizontal") ->
          true
        | _ -> false)
       ops);
  ignore (Lui_app.dispose app)

let test_split_event_decoders () =
  let open Lui_protocol in
  let event name entries =
    ExtensionEvent
      (42, "split-pane", name,
       String_map.of_list entries)
  in
  (match
     Lui_split.decode_split_pane_tab_moved
       (event "tab-moved"
          [ ("tab", StringValue "a");
            ("index", IntValue 2);
            ("from-pane", StringValue "p1") ])
   with
   | Some { Lui_split.event_node; tab; index; from_pane } ->
     Alcotest.(check int) "node" 42 event_node;
     Alcotest.(check string) "tab" "a" tab;
     Alcotest.(check int) "index" 2 index;
     Alcotest.(check string) "from-pane" "p1" from_pane
   | None -> Alcotest.fail "tab-moved did not decode");
  (match
     Lui_split.decode_split_pane_split_drop
       (event "split-drop"
          [ ("tab", StringValue "a");
            ("from-pane", StringValue "p1");
            ("edge", StringValue "right") ])
   with
   | Some { Lui_split.event_node; tab; from_pane; edge } ->
     Alcotest.(check int) "node" 42 event_node;
     Alcotest.(check string) "tab" "a" tab;
     Alcotest.(check string) "from-pane" "p1" from_pane;
     Alcotest.(check string) "edge" "right" edge
   | None -> Alcotest.fail "split-drop did not decode");
  (* cross-identifier and missing-field events must not decode *)
  Alcotest.(check bool) "wrong identifier rejected" true
    (Lui_split.decode_split_pane_tab_selected
       (ExtensionEvent
          (42, "other", "tab-selected",
           String_map.of_list [ ("tab", StringValue "a") ]))
     = None);
  Alcotest.(check bool) "missing required field rejected" true
    (Lui_split.decode_split_pane_tab_moved
       (event "tab-moved" [ ("tab", StringValue "a") ])
     = None);
  match
    Lui_split.decode_split_branch_ratio_changed
      (ExtensionEvent
         (7, "split-branch", "ratio-changed",
          String_map.of_list [ ("ratio", FloatValue 0.7) ]))
  with
  | Some { Lui_split.event_node; ratio } ->
    Alcotest.(check int) "branch node" 7 event_node;
    Alcotest.(check bool) "ratio" true (Float.abs (ratio -. 0.7) < 0.001)
  | None -> Alcotest.fail "ratio-changed did not decode"


let two_pane_state () =
  Lui_split.Model.create ~focused:"editor"
    (Lui_split.Model.Split
       {
         split_id = "root-split";
         split_orientation = `horizontal;
         split_ratio = 0.5;
         split_first =
           Lui_split.Model.Leaf
             (Lui_split.Model.pane ~pane_id:"editor"
                [
                  Lui_split.Model.tab ~tab_id:"a" ~title:"A" ();
                  Lui_split.Model.tab ~tab_id:"b" ~title:"B" ();
                ]);
         split_second =
           Lui_split.Model.Leaf
             (Lui_split.Model.pane ~pane_id:"outline"
                [ Lui_split.Model.tab ~tab_id:"c" ~title:"C" () ]);
       })

let pane_ids node =
  let rec collect acc = function
    | Lui_split.Model.Leaf p -> p.pane_id :: acc
    | Split { split_first; split_second; _ } ->
      collect (collect acc split_first) split_second
  in
  List.rev (collect [] node)

let tab_ids pane =
  List.map (fun t -> t.Lui_split.Model.tab_id) pane.Lui_split.Model.pane_tabs

let find_pane pane_id node =
  let rec go = function
    | Lui_split.Model.Leaf p ->
      if String.equal p.pane_id pane_id then Some p else None
    | Split { split_first; split_second; _ } -> (
        match go split_first with
        | Some _ as hit -> hit
        | None -> go split_second)
  in
  go node

let test_split_model () =
  let open Lui_split.Model in
  let state = two_pane_state () in
  (* tab selection *)
  let state =
    update state (Select_tab ("editor", "b"))
  in
  Alcotest.(check (option string)) "selected tab" (Some "b")
    (find_pane "editor" (root state)
     |> Option.map (fun p -> p.pane_selected)
     |> Option.join);
  (* moving a tab across panes selects it in the target *)
  let state =
    update state
      (Move_tab
         { move_tab = "a"; move_from = "editor"; move_to = "outline";
           move_index = 1 })
  in
  Alcotest.(check (list string)) "outline tabs" [ "c"; "a" ]
    (find_pane "outline" (root state) |> Option.map tab_ids
     |> Option.value ~default:[]);
  Alcotest.(check (option string)) "moved tab selected" (Some "a")
    (find_pane "outline" (root state)
     |> Option.map (fun p -> p.pane_selected)
     |> Option.join);
  (* same-pane move adjusts the index for the removed slot *)
  let state =
    update state
      (Move_tab
         { move_tab = "c"; move_from = "outline"; move_to = "outline";
           move_index = 2 })
  in
  Alcotest.(check (list string)) "reordered" [ "a"; "c" ]
    (find_pane "outline" (root state) |> Option.map tab_ids
     |> Option.value ~default:[]);
  (* edge drop splits the pane and the dropped edge gets the small share;
     dropping a foreign tab keeps the source pane in place *)
  let state =
    update state
      (Split_drop
         { drop_tab = "c"; drop_from = "outline"; drop_target = "editor";
           drop_edge = `right })
  in
  Alcotest.(check int) "three panes" 3 (List.length (pane_ids (root state)));
  (match root state with
  | Split { split_first = Split s; _ } ->
    Alcotest.(check bool) "split axis" true
      (match s.split_orientation with
      | `horizontal -> true
      | `vertical -> false);
    Alcotest.(check (float 0.001)) "dropped edge share" 0.75 s.split_ratio;
    (match s.split_first with
    | Leaf p -> Alcotest.(check string) "source keeps id" "editor" p.pane_id
    | Split _ -> Alcotest.fail "expected leaf")
  | _ -> Alcotest.fail "expected an inner edge split");
  (* navigation crosses the split in the matching axis *)
  let state = update state (Focus_pane "editor") in
  let state = update state (Navigate ("editor", `right)) in
  Alcotest.(check (option string)) "focus moved right" (Some "pane-0")
    (focused state);
  let state = update state (Navigate ("pane-0", `up)) in
  Alcotest.(check (option string)) "no pane above" (Some "pane-0")
    (focused state);
  (* closing the last tab removes the pane and collapses the split *)
  let state =
    List.fold_left update state
      [ Close_tab ("outline", "a") ]
  in
  Alcotest.(check (list string)) "pane collapsed" [ "editor"; "pane-0" ]
    (pane_ids (root state));
  (* a stale move to a vanished pane leaves the tab in place *)
  let state =
    update state
      (Move_tab
         { move_tab = "b"; move_from = "editor"; move_to = "ghost";
           move_index = 0 })
  in
  Alcotest.(check bool) "tab survived stale move" true
    (Option.is_some
       (Option.bind
          (find_pane "editor" (root state))
          (fun p ->
            List.find_opt
              (fun t -> String.equal t.Lui_split.Model.tab_id "b")
              p.pane_tabs)));
  (* non-closable tabs reject Close_tab *)
  let guarded =
    create
      (Leaf
         (pane ~pane_id:"locked"
            [
              tab ~tab_id:"open" ~title:"Open" ();
              tab ~tab_id:"fixed" ~title:"Fixed" ~closable:false ();
            ]))
  in
  let guarded = update guarded (Close_tab ("locked", "fixed")) in
  Alcotest.(check int) "protected tab kept" 2
    (match find_pane "locked" (root guarded) with
    | Some p -> List.length p.pane_tabs
    | None -> -1);
  (* the last pane never closes *)
  let state = update state (Close_pane "editor") in
  let state = update state (Close_pane "pane-0") in
  Alcotest.(check int) "last pane survives" 1 (List.length (pane_ids (root state)))

let test_composer_content_sizing () =
  let root = ref 0 in
  let backend = recording_backend () in
  let app = Lui_app.create backend () (fun model _ -> model)
    (fun _context _model _send -> capture_node root
       (Lui_element_combine.composer ~placeholder:"Synthetic draft"
          ~text:"One line" ~attachments:(Lui_elements.text ~value:"Synthetic attachment" []) ())) in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let grows = List.exists (function
    | Lui_protocol.SetProp (node, Lui_protocol.GrowValue, Lui_protocol.FloatValue value)
        when node = !root -> value > 0.
    | _ -> false) ops in
  Alcotest.(check bool) "composer does not fill available overlay height" false grows;
  let textarea = List.find_map (function
    | Lui_protocol.CreateNode (node, Lui_protocol.Textarea) -> Some node | _ -> None) ops |> Option.get in
  Alcotest.(check bool) "textarea has a bounded content height" true
    (List.exists (function
      | Lui_protocol.SetProp (node, Lui_protocol.MaxHeight, Lui_protocol.IntValue value)
          when node = textarea -> value > 36 && value <= 200
      | _ -> false) ops);
  ignore (Lui_app.dispose app)

let test_composer_attachment_preview_and_remove () =
  List.iter (fun disabled ->
    let removals = ref 0 in
    let app = Lui_app.create (recording_backend ()) () (fun model _ -> model)
      (fun _context _model _send ->
         Lui_element_combine.composer_attachment ~disabled ~key:"synthetic-pdf"
           ~path:"/tmp/synthetic.pdf" ~title:"Synthetic PDF" ~file_type:"pdf"
           ~on_remove:(fun _ -> incr removals) ()) in
    ignore (Lui_app.start app); flush_app app;
    let labelled name = List.find_map (function
      | Lui_protocol.SetProp (node, Lui_protocol.AccessibilityLabel,
          Lui_protocol.StringValue value) when value = name -> Some node
      | _ -> None) (all_ops ()) |> Option.get in
    let preview = labelled "Preview Synthetic PDF" in
    let remove = labelled "Remove Synthetic PDF" in
    ignore (Lui_app.dispatch_event app (Lui_protocol.Press preview)); flush_app app;
    let native_preview = List.find_map (function
      | Lui_protocol.CreateNode (node, Lui_protocol.FilePreview) -> Some node
      | _ -> None) (all_ops ()) |> Option.get in
    ignore (Lui_app.dispatch_event app (Lui_protocol.Dismiss native_preview)); flush_app app;
    ignore (Lui_app.dispatch_event app (Lui_protocol.Press remove)); flush_app app;
    Alcotest.(check int) "disabled removal cannot mutate a saving draft"
      (if disabled then 0 else 1) !removals;
    ignore (Lui_app.dispose app)) [false; true]

let test_composer_feedback_above_actions () =
  let app = Lui_app.create (recording_backend ()) () (fun model _ -> model)
    (fun _context _model _send ->
       Lui_element_combine.composer ~placeholder:"Synthetic draft"
         ~feedback:(Lui_elements.text ~value:"Synthetic camera unavailable" []) ()) in
  ignore (Lui_app.start app); flush_app app;
  let ops = all_ops () in
  let node_for property value = List.find_map (function
    | Lui_protocol.SetProp (node, key, Lui_protocol.StringValue actual)
        when key = property && actual = value -> Some node | _ -> None) ops |> Option.get in
  let feedback = node_for Lui_protocol.TextValue "Synthetic camera unavailable" in
  let actions = node_for Lui_protocol.AccessibilityIdentifier "row.composer.controls" in
  let placement node = List.find_map (function
    | Lui_protocol.InsertChild (parent, child, index) when child = node -> Some (parent,index)
    | _ -> None) ops |> Option.get in
  let feedback_parent, feedback_index = placement feedback in
  let action_parent, action_index = placement actions in
  Alcotest.(check bool) "feedback shares surface and reserves space above controls"
    true (feedback_parent = action_parent && feedback_index < action_index);
  ignore (Lui_app.dispose app)



(* Navigation exercises the public component through a real retained runtime,
   including synchronous callback writes and covered signal subscriptions. *)
let test_navigation_path () =
  let module P = Lui_navigation.Path in
  let a = P.push "detail" P.empty in
  let b = P.push "detail" a in
  Alcotest.(check int) "duplicate routes have two entries" 2
    (List.length (P.entries b));
  let ids = List.map (fun (e : string Lui_navigation.entry) -> e.id) (P.entries b) in
  Alcotest.(check bool) "distinct identities" true
    (List.length (List.sort_uniq String.compare ids) = 2);
  Alcotest.(check bool) "pop preserves original path" true (P.entries (P.pop b) = P.entries a);
  Alcotest.(check int) "empty pop" 0 (List.length (P.entries (P.pop P.empty)));
  Alcotest.(check int) "root" 0 (List.length (P.entries (P.pop_to_root b)));
  let fork = P.push "detail" a in
  Alcotest.(check bool) "branch pushes allocate fresh identity" true
    (P.entries fork <> P.entries b);
  (* These two uses also exercise the covariant, polymorphic empty value. *)
  ignore (P.push 1 P.empty);
  ignore (P.push (fun () -> ()) P.empty)

let navigation_fixture ?host_profile ?(apple=true) ?(accept=true) ?(reenter=false) () =
  let root_mounts = ref 0 and destination_mounts = ref 0 in
  let root_disposes = ref 0 and destination_disposes = ref 0 in
  let callback_count = ref 0 and edit = ref None in
  let backend = recording_backend () in
  let backend = if apple then {backend with Lui_protocol.backend_profile =
    Lui_protocol.profile Lui_protocol.IOS Lui_protocol.SwiftUIHost} else backend in
  let label_slot = Signal.state_slot "navigation-root-label" in
  let backend = match host_profile with None -> backend
    | Some backend_profile -> {backend with Lui_protocol.backend_profile} in
  let view _context source send =
    let root context parent =
      let label = Signal.state_at context.Lui_ui.ui_scheduler
          context.Lui_ui.ui_state_scope label_slot "before" in
      edit := Some (fun value -> Signal.set label value);
      incr root_mounts;
      Signal.on_dispose context.Lui_ui.ui_scope (fun () -> incr root_disposes);
      Lui_elements.list [Lui_elements.list_item
        [Lui_elements.text ~value_signal:(Signal.value label) []]] context parent
    in
    Lui_navigation.navigation_stack ~path_signal:source
      ~on_path_change:(fun path ->
        incr callback_count;
        if accept then ignore (send (if reenter then Lui_navigation.Path.push "replacement" path else path)))
      ~destination:(fun entry context parent ->
        incr destination_mounts;
        Signal.on_dispose context.Lui_ui.ui_scope (fun () -> incr destination_disposes);
        Lui_elements.text ~value:entry.Lui_navigation.route [] context parent)
      ~root ()
  in
  let app = Lui_app.create_with_extensions backend (Lui_navigation.registry ())
      Lui_navigation.Path.empty (fun _ path -> path) view in
  ignore (Lui_app.start app); flush_app app;
  (app, root_mounts, destination_mounts, root_disposes, destination_disposes, callback_count, edit)

let navigation_prop app name =
  let root = Lui_app.root_node app in
  List.fold_left (fun value -> function
    | Lui_protocol.SetExtensionProp (node, property, v) when node = root && property = name -> Some v
    | _ -> value) None (all_ops ())

let navigation_revision app = match navigation_prop app "revision" with
  | Some (Lui_protocol.IntValue r) -> r
  | _ -> Alcotest.fail "navigation revision is absent"

let navigation_event app revision name length =
  let open Lui_protocol in
  let fields = String_map.(empty |> add "revision" (IntValue revision)
    |> add "length" (IntValue length)) in
  ignore (Lui_app.dispatch_event app (ExtensionEvent (Lui_app.root_node app, "navigation-stack", name, fields)));
  flush_app app

let test_navigation_retains () =
  let app, roots, destinations, root_disposes, destination_disposes, callbacks, edit = navigation_fixture () in
  let push () = ignore (Lui_app.send app (Lui_navigation.Path.push "detail" (Lui_app.model app))); flush_app app in
  push (); push ();
  Alcotest.(check int) "root mounted once" 1 !roots;
  Alcotest.(check int) "each duplicate destination mounted once" 2 !destinations;
  Alcotest.(check int) "covered scope alive" 0 !root_disposes;
  Alcotest.(check int) "covered destination scope alive" 0 !destination_disposes;
  Option.iter (fun edit -> edit "after") !edit; flush_app app;
  Alcotest.(check bool) "covered root still observes local edits" true
    (List.exists (function Lui_protocol.SetProp (_, Lui_protocol.TextValue, Lui_protocol.StringValue "after") -> true | _ -> false) (all_ops ()));
  ignore (Lui_app.send app (Lui_navigation.Path.pop_to_root (Lui_app.model app))); flush_app app;
  Alcotest.(check int) "programmatic changes do not echo" 0 !callbacks;
  Alcotest.(check int) "outgoing retained before settlement" 0 !destination_disposes;
  navigation_event app (navigation_revision app) "settled" 0;
  Alcotest.(check int) "outgoing released after settlement" 2 !destination_disposes;
  Alcotest.(check int) "root survives return" 1 !roots;
  ignore (Lui_app.dispose app);
  Alcotest.(check int) "root disposed once on owner teardown" 1 !root_disposes

let test_navigation_back () =
  List.iter (fun reenter ->
    let app, _, mounts, _, disposes, callbacks, _ = navigation_fixture ~reenter () in
    let path = Lui_navigation.Path.(push "b" (push "a" empty)) in
    ignore (Lui_app.send app path); flush_app app;
    let old = navigation_revision app in
    navigation_event app old "path-changed" 1;
    Alcotest.(check int) "one committed callback" 1 !callbacks;
    Alcotest.(check int) "callback path or reentrant replacement wins" (if reenter then 2 else 1)
      (List.length (Lui_navigation.Path.entries (Lui_app.model app)));
    navigation_event app old "path-changed" 0;
    navigation_event app old "settled" 1;
    Alcotest.(check int) "old revision ignored" 1 !callbacks;
    Alcotest.(check int) "old settlement cannot drop outgoing" 0 !disposes;
    navigation_event app (navigation_revision app) "settled" (if reenter then 2 else 1);
    Alcotest.(check int) "removed entry released exactly once" 1 !disposes;
    Alcotest.(check int) "retained entry not rebuilt" (if reenter then 3 else 2) !mounts;
    ignore (Lui_app.dispose app)) [false; true]

let test_navigation_rejects_invalid () =
  let app, _, _, _, _, callbacks, _ = navigation_fixture ~accept:false () in
  let path = Lui_navigation.Path.push "detail" Lui_navigation.Path.empty in
  ignore (Lui_app.send app path); flush_app app;
  let revision = navigation_revision app in
  List.iter (fun length -> navigation_event app revision "path-changed" length) [-1; 1; 2];
  Alcotest.(check int) "invalid and echo paths ignored" 0 !callbacks;
  navigation_event app revision "path-changed" 0;
  Alcotest.(check int) "proposal delivered" 1 !callbacks;
  Alcotest.(check int) "owner may reject proposal" 1 (List.length (Lui_navigation.Path.entries (Lui_app.model app)));
  Alcotest.(check bool) "rejection publishes a fresh revision" true (revision <> navigation_revision app);
  navigation_event app revision "path-changed" 0;
  Alcotest.(check int) "rejected proposal cannot repeat" 1 !callbacks;
  ignore (Lui_app.dispose app)

let test_navigation_rapid_and_switch () =
  let app, _, mounts, _, disposes, _, _ = navigation_fixture () in
  let first = Lui_navigation.Path.push "first" Lui_navigation.Path.empty in
  ignore (Lui_app.send app first); flush_app app;
  let old = navigation_revision app in
  ignore (Lui_app.send app Lui_navigation.Path.empty); flush_app app;
  ignore (Lui_app.send app first); flush_app app;
  Alcotest.(check int) "repush outgoing identity reuses subtree" 1 !mounts;
  navigation_event app old "settled" 1;
  Alcotest.(check int) "stale completion leaves live entry" 0 !disposes;
  let replacement = Lui_navigation.Path.push "new graph" Lui_navigation.Path.empty in
  ignore (Lui_app.send app replacement); flush_app app;
  navigation_event app old "path-changed" 0;
  Alcotest.(check bool) "old graph callback cannot overwrite new graph" true (Lui_app.model app = replacement);
  navigation_event app (navigation_revision app) "settled" 1;
  Alcotest.(check int) "old graph entry cleaned" 1 !disposes;
  ignore (Lui_app.dispose app);
  Alcotest.(check int) "all destination scopes cleaned" 2 !disposes

let test_navigation_fallback () =
  let open Lui_protocol in
  List.iter (fun host_profile ->
  let app, roots, mounts, root_disposes, disposes, callbacks, _ = navigation_fixture ~host_profile ~apple:false () in
  ignore (Lui_app.send app Lui_navigation.Path.(push "b" (push "a" empty))); flush_app app;
  Alcotest.(check int) "fallback retains root" 1 !roots;
  Alcotest.(check int) "fallback mounts both entries" 2 !mounts;
  Alcotest.(check int) "covered fallback scope alive" 0 !root_disposes;
  let back = List.find_map (function
    | Lui_protocol.CreateNode (node, Lui_protocol.Button) -> Some node | _ -> None) (all_ops ()) |> Option.get in
  ignore (Lui_app.dispatch_event app (Lui_protocol.Press back)); flush_app app;
  Alcotest.(check int) "fallback Back commits one proposal" 1 !callbacks;
  Alcotest.(check int) "fallback Back returns to covered entry" 1
    (List.length (Lui_navigation.Path.entries (Lui_app.model app)));
  Alcotest.(check int) "fallback Back preserves entry mount" 2 !mounts;
  ignore (Lui_app.send app Lui_navigation.Path.empty); flush_app app;
  Alcotest.(check int) "no-animation fallback cleans immediately" 2 !disposes;
  Alcotest.(check int) "fallback programmatic path does not echo" 1 !callbacks;
  ignore (Lui_app.dispose app))
    [generic_profile (); profile WebOS WebHost;
     profile LinuxOS GPUIHost; profile WindowsOS GPUIHost]

let test_navigation_queued_stale () =
  let app, _, _, _, _, callbacks, _ = navigation_fixture () in
  ignore (Lui_app.send app Lui_navigation.Path.(push "old" empty)); flush_app app;
  let revision = navigation_revision app in
  let replacement = Lui_navigation.Path.(push ("new" ^ " graph") empty) in
  (* The owner write is staged, but not flushed before the old host event. *)
  ignore (Lui_app.send app replacement);
  navigation_event app revision "path-changed" 0;
  Alcotest.(check int) "queued owner write invalidates old callback" 0 !callbacks;
  Alcotest.(check bool) "queued replacement wins" true (Lui_app.model app = replacement);
  ignore (Lui_app.dispose app)

let test_navigation_host_fingerprint () =
  let source = read_file (Filename.concat (source_root ())
      "platform/apple/Sources/LUIAppleBackend/LUINavigation.swift") in
  let mismatches = Lui_extension_check.check_registry (Lui_navigation.registry ()) source in
  if mismatches <> [] then Alcotest.fail (Lui_extension_check.describe_mismatches mismatches)

let test_navigation_entry_state () =
  let open Lui_navigation in
  let slot = Signal.state_slot "detail-local" in
  let states = Hashtbl.create 4 in
  let backend = { (recording_backend ()) with Lui_protocol.backend_profile =
      Lui_protocol.profile Lui_protocol.IOS Lui_protocol.SwiftUIHost } in
  let app = Lui_app.create_with_extensions backend (registry ()) Path.empty
      (fun _ path -> path) (fun _ source send ->
    navigation_stack ~path_signal:source ~on_path_change:(fun path -> ignore (send path))
      ~root:(Lui_elements.box [])
      ~destination:(fun entry context parent ->
        let local = Signal.state_at context.Lui_ui.ui_scheduler context.Lui_ui.ui_state_scope slot 0 in
        Hashtbl.add states entry.id (local, context.Lui_ui.ui_state_scope);
        Lui_elements.text ~value_signal:(Signal.map string_of_int (Signal.value local)) [] context parent) ()) in
  ignore (Lui_app.start app); flush_app app;
  let a = Path.push (fun () -> "same") Path.empty in
  let b = Path.push (fun () -> "same") a in
  ignore (Lui_app.send app b); flush_app app;
  let entries = Path.entries b in
  let first = (List.hd entries).id and second = (List.hd (List.tl entries)).id in
  let first_state, first_scope = Hashtbl.find states first in
  let second_state, second_scope = Hashtbl.find states second in
  Signal.set first_state 7; Signal.set second_state 9; flush_app app;
  ignore (Lui_app.send app (Path.pop b)); flush_app app;
  Alcotest.(check int) "covered local state preserved" 7 (Signal.get_state first_state);
  Alcotest.(check bool) "covered entry state scope active" true (not !(first_scope.Signal.disposed_scope));
  Alcotest.(check bool) "outgoing state lives during transition" true (not !(second_scope.Signal.disposed_scope));
  navigation_event app (navigation_revision app) "settled" 1;
  Alcotest.(check bool) "only removed entry state disposed" false (not !(second_scope.Signal.disposed_scope));
  Alcotest.(check bool) "remaining entry state still active" true (not !(first_scope.Signal.disposed_scope));
  ignore (Lui_app.dispose app);
  Alcotest.(check bool) "owner teardown disposes surviving state" false (not !(first_scope.Signal.disposed_scope))


let () =
  Alcotest.run "lui"
    [
      ("navigation", [
        Alcotest.test_case "entry local states and function routes" `Quick test_navigation_entry_state;
        Alcotest.test_case "queued owner write versus stale host event" `Quick test_navigation_queued_stale;
        Alcotest.test_case "Apple extension fingerprints" `Quick test_navigation_host_fingerprint;
        Alcotest.test_case "typed paths and duplicate identity" `Quick test_navigation_path;
        Alcotest.test_case "root, covered scopes and transition lifetime" `Quick test_navigation_retains;
        Alcotest.test_case "native back and synchronous reentry" `Quick test_navigation_back;
        Alcotest.test_case "invalid, echo and rejected proposals" `Quick test_navigation_rejects_invalid;
        Alcotest.test_case "rapid push/pop and graph replacement" `Quick test_navigation_rapid_and_switch;
        Alcotest.test_case "fallback retention and cleanup" `Quick test_navigation_fallback;
      ]);
      ( "app",
        [
          Alcotest.test_case "composer content sizing" `Quick test_composer_content_sizing;
          Alcotest.test_case "composer attachment preview and removal" `Quick test_composer_attachment_preview_and_remove;
          Alcotest.test_case "composer feedback above actions" `Quick test_composer_feedback_above_actions;
          Alcotest.test_case "lifecycle" `Quick test_app_lifecycle;
          Alcotest.test_case "backend patches" `Quick
            test_backend_receives_patches;
          Alcotest.test_case "same-batch create+drop renumbers" `Quick
            test_same_batch_create_drop_renumbers;
          Alcotest.test_case "same-batch drop adjusts foreign move" `Quick
            test_same_batch_drop_adjusts_foreign_move;
          Alcotest.test_case "same-batch drop tracks foreign remove" `Quick
            test_same_batch_drop_tracks_foreign_remove;
          Alcotest.test_case "same-batch drop untracked aborts" `Quick
            test_same_batch_drop_untracked_aborts;
          Alcotest.test_case "same-batch drop poisoned parent aborts" `Quick
            test_same_batch_drop_poisoned_parent_aborts;
        ] );
      ( "protocol",
        [
          Alcotest.test_case "helpers" `Quick test_protocol_helpers;
          Alcotest.test_case "menu-trigger rules" `Quick
            test_menu_trigger_rules;
          Alcotest.test_case "list suite rules" `Quick
            test_list_suite_rules;
          Alcotest.test_case "file-picker rules" `Quick test_file_picker;
          Alcotest.test_case "vocab batch 2" `Quick test_vocab_batch2;
          Alcotest.test_case "media file rules" `Quick test_media_file_rules;
          Alcotest.test_case "media file mount" `Quick test_media_file_mount;
          Alcotest.test_case "edge/overlay/fit rules" `Quick
            test_edge_overlay_fit_rules;
          Alcotest.test_case "property matrix sync" `Quick
            test_property_matrix_sync;
          Alcotest.test_case "data-attrs protocol" `Quick
            test_data_attrs_protocol;
          Alcotest.test_case "as protocol" `Quick test_as_protocol;
          Alcotest.test_case "data-attrs + as emit" `Quick
            test_data_attrs_and_as_emit;
        ] );
      ( "dyn",
        [
          Alcotest.test_case "equal skips remount" `Quick
            test_dyn_equal_skips_remount;
          Alcotest.test_case "default remounts" `Quick
            test_dyn_default_remounts;
          Alcotest.test_case "bare dyn as dyn branch" `Quick
            test_dyn_nested_bare;
          Alcotest.test_case "extension names allow underscore" `Quick
            test_extension_names_allow_underscore;
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
          Alcotest.test_case "default (=) equal" `Quick
            test_dyn_default_equal;
          Alcotest.test_case "if_ test toggles" `Quick
            test_if_test_toggles;
          Alcotest.test_case "owns derived source" `Quick
            test_dyn_shared_source_survives_remount;
          Alcotest.test_case "keyed source diffs" `Quick
            test_keyed_source;
        ] );
      ( "dispatch",
        [
          Alcotest.test_case "pointer events" `Quick test_pointer_events;
          Alcotest.test_case "pointer dispatch" `Quick test_pointer_dispatch;
          Alcotest.test_case "value echoes dropped" `Quick
            test_dispatch_drops_value_echoes;
          Alcotest.test_case "unset default echoes dropped" `Quick
            test_dispatch_drops_unset_default_echoes;
        ] );
      ( "number stepper + sheet sizing",
        [
          Alcotest.test_case "props + value-changed" `Quick
            test_number_stepper_props;
          Alcotest.test_case "schema surface" `Quick
            test_number_stepper_schema;
          Alcotest.test_case "sheet detents + sizing" `Quick
            test_sheet_presentation_props;
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
          Alcotest.test_case "menu action" `Quick
            test_glass_button_menu_action;
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
      ( "split",
        [
          Alcotest.test_case "canonical fingerprints" `Quick
            test_split_fingerprints;
          Alcotest.test_case "host literals in sync" `Quick
            test_split_host_literals_in_sync;
          Alcotest.test_case "extension ops" `Quick test_split_extension_ops;
          Alcotest.test_case "event decoders" `Quick test_split_event_decoders;
          Alcotest.test_case "model reduce" `Quick test_split_model;
        ] );
    ]
