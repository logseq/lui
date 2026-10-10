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

let todo_reducer model action =
  match action with
  | `Done item -> List.filter (fun x -> x <> item) model
  | `Add item -> model @ [ item ]

(* Scenario fixtures re-render on model change: content that must update
   sits under a dyn bound to the model source, since a bare Signal.sample
   does not subscribe the view. *)
let todo_drive_view _context model_source send =
  Lui_elements.column ~gap:8
    [ Lui_elements.text ~value:"Todos" [];
      Lui_elements.dyn ~equal:( = )
        (fun (items : string list) ->
           Lui_elements.column ~gap:8
             (List.map
                (fun item ->
                   Lui_elements.row
                     [ Lui_elements.text ~value:item [];
                       Lui_elements.button ~text:"Done"
                         ~on_press:(Lui_elements.press send (`Done item)) [] ])
                items))
        model_source ]

(* Counter fixture shared with the counter.drive scenario. *)
let counter_view _context model_source send =
  Lui_elements.column
    [ Lui_elements.dyn ~equal:( = )
        (fun n ->
           Lui_elements.text ~value:("count=" ^ string_of_int n) [])
        model_source;
      Lui_elements.button ~text:"Increment"
        ~on_press:(Lui_elements.press send `Increment) [] ]

let counter_reducer model `Increment = model + 1

let test_app_lifecycle () =
  let app =
    Lui_app.create (recording_backend ()) [ "write tests" ]
      todo_reducer todo_view
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
  List.iter
    (function
      | Lui_protocol.CreateNode (id, _)
      | Lui_protocol.CreateExtension (id, _, _) ->
        Hashtbl.replace runtime.Lui_runtime.pending_creates id ()
      | _ -> ())
    ops;
  Lui_runtime.enqueue_drop runtime ghost;
  List.rev !(runtime.Lui_runtime.pending_ops)

let describe_op (operation : Lui_protocol.patch_op) =
  let open Lui_protocol in
  match operation with
  | CreateNode (id, kind) ->
    Printf.sprintf "create:%d:%s" id (Lui_wire_schema.node_kind_name kind)
  | CreateExtension (id, _, _) -> Printf.sprintf "create-ext:%d" id
  | DropNode id -> Printf.sprintf "drop:%d" id
  | DetachSubtree id -> Printf.sprintf "detach:%d" id
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
  List.exists
    (function
      | Lui_protocol.DropNode _ | Lui_protocol.DetachSubtree _ -> true
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

(* Drive-backed sessions mount the app against a replayed node tree, so
   behavior tests dispatch semantic events and assert on the tree a host
   would see — wire-named kinds and props, child order — instead of
   scanning raw patch ops. *)

let drive_mount ?registry ?(profile = Lui_protocol.generic_profile ())
    ~initial ~reducer ~view () =
  Drive.Session.mount ?registry ~profile ~initial ~reducer ~view ()

let drive_app (s : _ Drive.Session.t) = s.Drive.Session.app
let drive_tree (s : _ Drive.Session.t) = s.Drive.Session.tree
let drive_send s ev = (Drive.Session.driver s).send_event ev
let drive_flush s = Drive.Session.flush s
let drive_dispose s = Drive.Session.dispose s

let drive_node s sel =
  match Drive.Model.first (drive_tree s) sel with
  | Some n -> n
  | None ->
    Alcotest.failf "no node matches selector; tree:\n%s"
      (Drive.Model.dump (drive_tree s))

let drive_children s (n : Drive.Model.node) =
  Drive.Model.children (drive_tree s) n.Drive.Model.id

let drive_kind_names s (n : Drive.Model.node) =
  List.map (fun (c : Drive.Model.node) -> c.Drive.Model.kind)
    (drive_children s n)

let drive_prop s (n : Drive.Model.node) name =
  Drive.Model.prop (drive_tree s) n.Drive.Model.id name

let drive_press s sel =
  Drive.Session.press s (drive_node s sel).Drive.Model.id

let test_glass_button_actions () =
  let single_presses = ref 0 in
  let information_presses = ref 0 in
  let settings_presses = ref 0 in
  let action label icon presses : Lui_element_combine.action =
    Lui_element_combine.Press
      { label; icon; text = None; on_press = (fun _ -> incr presses) }
  in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_element_combine.buttons
               ~actions:[ action "New note" `plus single_presses ];
             Lui_element_combine.buttons
               ~actions:
                 [ action "Information" `info information_presses;
                   action "Settings" `settings settings_presses ];
           ])
      ()
  in
  let labelled label =
    Drive.Model.(
      All
        [ Kind "button";
          Prop ("accessibility-label", Lui_protocol.StringValue label) ])
  in
  let group_children =
    drive_children s (drive_node s (Drive.Model.Kind "button-group"))
  in
  Alcotest.(check int) "group has two actions" 2 (List.length group_children);
  drive_press s (labelled "New note");
  List.iter
    (fun (n : Drive.Model.node) -> Drive.Session.press s n.Drive.Model.id)
    group_children;
  Alcotest.(check (list int)) "each action has its own callback"
    [ 1; 1; 1 ]
    [ !single_presses; !information_presses; !settings_presses ];
  drive_dispose s

let test_glass_buttons_require_an_action () =
  let rejected =
    try
      let _element = Lui_element_combine.buttons ~actions:[] in
      false
    with Invalid_argument _ -> true
  in
  Alcotest.(check bool) "empty group rejected" true rejected

let test_glass_button_text_is_optional () =
  let action : Lui_element_combine.action =
    Lui_element_combine.Press
      { label = "New note"; icon = `plus; text = None; on_press = (fun _ -> ()) }
  in
  let with_press ~label ~icon ~text : Lui_element_combine.action =
    Lui_element_combine.Press
      { label; icon; text; on_press = (fun _ -> ()) }
  in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_element_combine.buttons ~actions:[ action ];
             Lui_element_combine.buttons
               ~actions:
                 [ with_press ~label:"New note" ~icon:`plus
                     ~text:(Some "New note") ];
             Lui_element_combine.buttons
               ~actions:
                 [ with_press ~label:"Information" ~icon:`info
                     ~text:(Some "Info")
                 ; with_press ~label:"Settings" ~icon:`settings ~text:None
                 ];
           ])
      ()
  in
  let labelled label =
    Drive.Model.(
      All
        [ Kind "button";
          Prop ("accessibility-label", Lui_protocol.StringValue label) ])
  in
  let text_of (n : Drive.Model.node) = Drive.Model.string_prop n "text" in
  let new_note_buttons =
    Drive.Model.find (drive_tree s) (labelled "New note")
  in
  let icon_only =
    match List.find_opt (fun n -> text_of n = None) new_note_buttons with
    | Some n -> n
    | None -> Alcotest.fail "no icon-only New note button"
  in
  Alcotest.(check (option string)) "icon-only button keeps accessible label"
    (Some "New note")
    (Drive.Model.string_prop icon_only "accessibility-label");
  Alcotest.(check (option string)) "icon-only button has no visible text" None
    (text_of icon_only);
  Alcotest.(check bool) "text button shows its text" true
    (List.exists (fun n -> text_of n = Some "New note") new_note_buttons);
  let group_children =
    drive_children s (drive_node s (Drive.Model.Kind "button-group"))
  in
  Alcotest.(check int) "group has two actions" 2 (List.length group_children);
  Alcotest.(check (option string)) "first group action shows text" (Some "Info")
    (Drive.Model.string_prop (List.hd group_children) "text");
  Alcotest.(check bool) "second group action is icon-only" true
    (Drive.Model.string_prop (List.nth group_children 1) "text"
     <> Some "Settings");
  drive_dispose s

let test_glass_button_menu_action () =
  let picked = ref 0 in
  let menu_entries () =
    [ Lui_elements.menu_item ~text:"Duplicate"
        ~on_press:(fun _ -> incr picked) [] ]
  in
  let menu_action : Lui_element_combine.action =
    Lui_element_combine.Menu
      { label = "More actions"; icon = `ellipsis; text = None
      ; menu = menu_entries (); on_dismiss = None }
  in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_element_combine.buttons ~actions:[ menu_action ];
             Lui_element_combine.buttons
               ~actions:
                 [ Lui_element_combine.Press
                     { label = "New note"; icon = `plus; text = None
                     ; on_press = (fun _ -> ()) }
                 ; menu_action
                 ];
           ])
      ()
  in
  let group_with_children n =
    List.find_opt
      (fun (g : Drive.Model.node) ->
         List.length g.Drive.Model.children = n)
      (Drive.Model.find (drive_tree s) (Drive.Model.Kind "button-group"))
  in
  (* A lone menu action still shares the glass capsule shape: a one-member
     button group wraps the sizing cell (box is not a legal toolbar child). *)
  let single =
    match group_with_children 1 with
    | Some g -> g
    | None -> Alcotest.fail "single menu capsule missing"
  in
  Alcotest.(check (option string)) "single menu action capsule is glass"
    (Some "glass") (Drive.Model.string_prop single "background");
  Alcotest.(check (list string)) "single capsule wraps one cell" [ "box" ]
    (drive_kind_names s single);
  let cell = List.hd (drive_children s single) in
  Alcotest.(check (list string)) "single cell wraps one trigger"
    [ "menu-trigger" ] (drive_kind_names s cell);
  let trigger = List.hd (drive_children s cell) in
  Alcotest.(check (list string)) "trigger hosts one dropdown-menu"
    [ "dropdown-menu" ] (drive_kind_names s trigger);
  let menu = List.hd (drive_children s trigger) in
  Alcotest.(check (list string)) "menu has its items" [ "menu-item" ]
    (drive_kind_names s menu);
  (* Mixed press + menu actions share one group capsule *)
  let group =
    match group_with_children 2 with
    | Some g -> g
    | None -> Alcotest.fail "mixed group missing"
  in
  Alcotest.(check (list string)) "group cells" [ "button"; "box" ]
    (drive_kind_names s group);
  (* Menu items dispatch their own presses *)
  List.iter
    (fun (n : Drive.Model.node) -> Drive.Session.press s n.Drive.Model.id)
    (drive_children s menu);
  Alcotest.(check int) "menu item press fires its handler" 1 !picked;
  drive_dispose s

let test_dispatch_drops_value_echoes () =
  let inputs = ref 0 in
  let toggles = ref 0 in
  let presses = ref 0 in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [
             Lui_elements.text_field ~text:"hello"
               ~on_input:(fun _event -> incr inputs) [];
             Lui_elements.checkbox ~checked:false
               ~on_toggle:(fun _event -> incr toggles) [];
             Lui_elements.button
               ~on_press:(fun _event -> incr presses) [];
           ])
      ()
  in
  let field = (drive_node s (Drive.Model.Kind "text-field")).Drive.Model.id in
  let checkbox = (drive_node s (Drive.Model.Kind "checkbox")).Drive.Model.id in
  let button = (drive_node s (Drive.Model.Kind "button")).Drive.Model.id in
  Drive.Session.text_changed s field "hello";
  Drive.Session.toggle s checkbox false;
  Alcotest.(check int) "text echo suppressed" 0 !inputs;
  Alcotest.(check int) "toggle echo suppressed" 0 !toggles;
  Drive.Session.text_changed s field "hello!";
  Drive.Session.toggle s checkbox true;
  Drive.Session.press s button;
  Alcotest.(check int) "changed text delivered" 1 !inputs;
  Alcotest.(check int) "changed toggle delivered" 1 !toggles;
  Alcotest.(check int) "press still delivered" 1 !presses;
  drive_dispose s

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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [
             Lui_elements.button
               ~on_press_detail:(fun _event -> incr details)
               ~on_pointer_enter:(fun _event -> incr enters)
               ~on_pointer_leave:(fun _event -> incr leaves)
               ~on_context_menu:(fun _event -> incr menus) [];
           ])
      ()
  in
  let button = (drive_node s (Drive.Model.Kind "button")).Drive.Model.id in
  let detail =
    { Lui_protocol.x = 1.0; y = 2.0; modifiers = 0; button = 0;
      target_class = "" }
  in
  drive_send s (Lui_protocol.PressDetail (button, detail));
  drive_send s (Lui_protocol.PointerEnter button);
  drive_send s (Lui_protocol.PointerLeave button);
  drive_send s (Lui_protocol.ContextMenuPress (button, detail));
  Alcotest.(check (list int)) "pointer handlers fired" [ 1; 1; 1; 1 ]
    [ !details; !enters; !leaves; !menus ];
  (* kind-unsupported events are still rejected at dispatch *)
  Alcotest.check_raises "unsupported event rejected"
    (Invalid_argument "event is unsupported by node kind")
    (fun () ->
       ignore
         (Lui_app.dispatch_event (drive_app s)
            (Lui_protocol.ValueChanged (button, 0.5))));
  drive_dispose s

let test_dispatch_drops_unset_default_echoes () =
  let inputs = ref 0 in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [
             Lui_elements.text_field
               ~on_input:(fun _event -> incr inputs) [];
           ])
      ()
  in
  let field = (drive_node s (Drive.Model.Kind "text-field")).Drive.Model.id in
  Drive.Session.text_changed s field "";
  Alcotest.(check int) "empty echo on unset text suppressed" 0 !inputs;
  Drive.Session.text_changed s field "x";
  Alcotest.(check int) "typed text delivered" 1 !inputs;
  drive_dispose s

(* A control that already left its unset default must deliver the trip
   back to that default. "" / false / 0.0 are real input, not mount echoes. *)
let test_value_return_to_default_is_delivered () =
  let inputs = ref 0 in
  let toggles = ref 0 in
  let slides = ref 0 in
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [
             Lui_elements.text_field ~text:"hello"
               ~on_input:(fun _event -> incr inputs) [];
             Lui_elements.checkbox ~checked:true
               ~on_toggle:(fun _event -> incr toggles) [];
             Lui_elements.slider ~value:0.5
               ~on_change:(fun _event -> incr slides) [];
           ])
      ()
  in
  let field = (drive_node s (Drive.Model.Kind "text-field")).Drive.Model.id in
  let checkbox = (drive_node s (Drive.Model.Kind "checkbox")).Drive.Model.id in
  let slider = (drive_node s (Drive.Model.Kind "slider")).Drive.Model.id in
  Drive.Session.text_changed s field "";
  Alcotest.(check int) "cleared text delivered" 1 !inputs;
  Drive.Session.toggle s checkbox false;
  Alcotest.(check int) "unchecked box delivered" 1 !toggles;
  Drive.Session.value_changed s slider 0.0;
  Alcotest.(check int) "slider zero delivered" 1 !slides;
  drive_dispose s

let test_drop_large_subtree_is_one_detach () =
  let mount count =
    batches := [];
    let app =
      Lui_app.create (recording_backend ()) true
        (fun shown _action -> not shown)
        (fun _context model_source _send ->
          Lui_elements.column
            [
              Lui_elements.if_ ~test:model_source
                (Lui_elements.column
                   (List.init count (fun index ->
                        Lui_elements.text ~value:(string_of_int index) [])));
            ])
    in
    ignore (Lui_app.start app);
    flush_app app;
    batches := [];
    let started = Sys.time () in
    ignore (Lui_app.send app ());
    flush_app app;
    let elapsed = Sys.time () -. started in
    let ops = all_ops () in
    ignore (Lui_app.dispose app);
    (elapsed, ops)
  in
  let count_kind predicate ops =
    List.length (List.filter predicate ops)
  in
  let detaches ops =
    count_kind (function Lui_protocol.DetachSubtree _ -> true | _ -> false) ops
  in
  let removes ops =
    count_kind (function Lui_protocol.RemoveChild _ -> true | _ -> false) ops
  in
  let _elapsed_small, ops_small = mount 50 in
  let elapsed_small, _ = mount 200 in
  let elapsed_large, ops_large = mount 800 in
  Alcotest.(check int) "small drop is one detach" 1 (detaches ops_small);
  Alcotest.(check int) "large drop is one detach" 1 (detaches ops_large);
  (* The branch root is unlinked with one remove-child; descendants leave
     with the detach and are not removed one by one. *)
  Alcotest.(check int) "only the branch root is removed" 1 (removes ops_large);
  if elapsed_large > (elapsed_small *. 12.) +. 0.25 then
    Alcotest.failf "dropping 4x nodes took %gs after %gs" elapsed_large
      elapsed_small

let test_float_encoding_rejects_non_finite () =
  let open Lui_protocol in
  Alcotest.check_raises "nan rejected"
    (Invalid_argument "float value is not finite") (fun () ->
      ignore (Lui_wire.encode_value (FloatValue nan)));
  Alcotest.check_raises "infinity rejected"
    (Invalid_argument "float value is not finite") (fun () ->
      ignore (Lui_wire.encode_value (FloatValue infinity)));
  Alcotest.(check string) "integral float keeps a decimal" "1.0"
    (Lui_wire.encode_value (FloatValue 1.0));
  let precise = 1.0 +. epsilon_float in
  Alcotest.(check string) "round-trip digits"
    (Printf.sprintf "%.17g" precise)
    (Lui_wire.encode_value (FloatValue precise));
  Alcotest.(check bool) "progress rejects nan" false
    (property_value_supported ProgressValue (FloatValue nan));
  Alcotest.(check bool) "grow rejects infinity" false
    (property_value_supported GrowValue (FloatValue infinity));
  Alcotest.(check bool) "anchor rejects nan" false
    (property_value_supported AnchorOffset (FloatValue nan))

let test_keyed_mount_failure_keeps_previous_rows () =
  let boom = ref false in
  let app =
    Lui_app.create (recording_backend ()) [ "a" ]
      (fun _model next -> next)
      (fun _context model_source _send ->
        Lui_elements.column
          [
            Lui_elements.keyed ~source:model_source ~key:(fun item -> item)
              ~cmp:String.compare
              ~mount:(fun item_source ->
                if !boom && Signal.sample item_source = "bad" then
                  failwith "keyed mount failed";
                Lui_elements.text ~value_signal:item_source []);
          ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  batches := [];
  boom := true;
  Alcotest.check_raises "mount failure" (Failure "keyed mount failed")
    (fun () ->
      ignore (Lui_app.send app [ "bad" ]);
      flush_app app);
  Alcotest.(check int) "failed mount committed no text" 0
    (creates_text_count (all_ops ()));
  Alcotest.(check bool) "failed mount dropped nothing" false
    (drops_node (all_ops ()));
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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_elements.file_picker ~source:`photos
               ~request:(`String "op-1") ~types:"public.image" ~multiple:true
               ~completion:(`String "")
               ~on_picked:(fun event ->
                 match event with
                 | Picked (_, payload) ->
                   picked_payloads := payload :: !picked_payloads
                 | _ -> ())
               ~on_dismiss:(fun _ -> incr dismissed)
               [];
             Lui_elements.file_picker ~request:(`Int 7) [] ])
      ()
  in
  let picker =
    drive_node s
      (Drive.Model.All
         [ Drive.Model.Kind "file-picker";
           Drive.Model.Prop ("request", StringValue "op-1") ])
  in
  Alcotest.(check bool) "int request wired" true
    (Drive.Model.exists (drive_tree s)
       (Drive.Model.All
          [ Drive.Model.Kind "file-picker";
            Drive.Model.Prop ("request", IntValue 7) ]));
  Alcotest.(check bool) "types wired" true
    (drive_prop s picker "types" = Some (StringValue "public.image"));
  Alcotest.(check bool) "multiple wired" true
    (drive_prop s picker "multiple" = Some (BoolValue true));
  Alcotest.(check bool) "source wired" true
    (drive_prop s picker "source" = Some (StringValue "photos"));
  Alcotest.(check bool) "completion wired" true
    (drive_prop s picker "completion" = Some (StringValue ""));
  drive_send s (Picked (picker.Drive.Model.id, {|{"request":"op-1","files":[]}|}));
  Drive.Session.dismiss s picker.Drive.Model.id;
  Alcotest.(check (list string)) "picked delivered"
    [ {|{"request":"op-1","files":[]}|} ] !picked_payloads;
  Alcotest.(check int) "dismiss delivered" 1 !dismissed;
  drive_dispose s

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
  (* no url requirement on Link: in-app navigation anchors carry no href *)
  Alcotest.(check bool) "link ok without url" true
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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:media_view ()
  in
  let tree = drive_tree s in
  let has sel = Drive.Model.exists tree sel in
  let open Drive.Model in
  Alcotest.(check bool) "link mounted" true (has (Kind "link"));
  Alcotest.(check bool) "file-image mounted" true (has (Kind "file-image"));
  Alcotest.(check bool) "file-preview mounted" true (has (Kind "file-preview"));
  Alcotest.(check bool) "url prop set" true
    (has (All [ Kind "link";
                Prop ("url", Lui_protocol.StringValue "https://example.com") ]));
  Alcotest.(check bool) "path prop set" true
    (has (All [ Kind "file-image";
                Prop ("path", Lui_protocol.StringValue "/tmp/pic.png") ]));
  Alcotest.(check bool) "proportional fill prop set" true
    (has (All [ Kind "file-image";
                Prop ("image-fit", Lui_protocol.StringValue "fill") ]));
  Alcotest.(check bool) "max-pixel-size prop set" true
    (has (All [ Kind "file-image";
                Prop ("max-pixel-size", Lui_protocol.IntValue 512) ]));
  drive_dispose s

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
  (* Name policy includes documented DOM attributes and inline style. *)
  List.iter
    (fun name ->
       Alcotest.(check bool) name true (data_attr_name_ok name))
    [ "data-x"; "data-testid"; "aria-label"; "aria-hidden"; "role"
    ; "tabindex"; "draggable"; "style" ];
  List.iter
    (fun name ->
       Alcotest.(check bool) name false (data_attr_name_ok name))
    [ "id"; "class"; "onclick"; "data-"; "aria-"; "role-"
    ; "Data-x"; "data"; "aria" ];
  (* serialization round-trip *)
  let pairs =
    [ ("data-testid", "greeting"); ("role", "note")
    ; ("aria-label", "a b c"); ("tabindex", "-1")
    ; ("style", "--accent: teal; overflow-anchor: none") ]
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
  Alcotest.(check bool) "inline style payload" true
    (data_attrs_value_ok "style\x1f--accent: teal; overflow-anchor: none");
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
    (emitted RoleValue (StringValue "menu"));
  (* dropdown_menu ~at — programmatic point anchor *)
  Alcotest.(check bool) "x on dropdown-menu" true
    (property_supported DropdownMenu PopupX);
  Alcotest.(check bool) "y on dropdown-menu" true
    (property_supported DropdownMenu PopupY);
  Alcotest.(check bool) "available-height stays popover-only" false
    (property_supported DropdownMenu AvailableHeight);
  Alcotest.(check bool) "x without y rejected on dropdown-menu" false
    (node_properties_supported DropdownMenu with_x);
  Alcotest.(check bool) "x and y accepted on dropdown-menu" true
    (node_properties_supported DropdownMenu with_xy);
  Alcotest.(check bool) "point + anchor rejected on dropdown-menu" false
    (node_properties_supported DropdownMenu with_xy_anchor);
  let menu_node = ref 0 in
  let menu_app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node menu_node
               (Lui_elements.dropdown_menu ~at:(48.0, 96.0)
                  ~on_dismiss:(fun _event -> ())
                  [ Lui_elements.menu_item ~text:"Item" [] ]) ])
  in
  ignore (Lui_app.start menu_app);
  flush_app menu_app;
  let menu_ops = all_ops () in
  let menu_emitted property value =
    List.exists
      (function
         | Lui_protocol.SetProp (id, property', value') ->
           id = !menu_node && property' = property && value' = value
         | _ -> false)
      menu_ops
  in
  Alcotest.(check bool) "dropdown-menu node created" true
    (List.exists
       (function
          | Lui_protocol.CreateNode (id, Lui_protocol.DropdownMenu) ->
            id = !menu_node
          | _ -> false)
       menu_ops);
  Alcotest.(check bool) "dropdown-menu x emitted" true
    (menu_emitted PopupX (FloatValue 48.0));
  Alcotest.(check bool) "dropdown-menu y emitted" true
    (menu_emitted PopupY (FloatValue 96.0))

let test_visual_appearance_props () =
  let open Lui_protocol in
  (* Typed appearance props: typography, positioning, text overflow,
     user-select, shadows, state channels, viewport-relative sizes. *)
  Alcotest.(check bool) "font-size rem" true
    (property_value_supported FontSize (StringValue "0.75rem"));
  Alcotest.(check bool) "font-size px" true
    (property_value_supported FontSize (StringValue "12px"));
  Alcotest.(check bool) "font-weight range" true
    (property_value_supported FontWeight (IntValue 500));
  Alcotest.(check bool) "font-weight below range" false
    (property_value_supported FontWeight (IntValue 0));
  Alcotest.(check bool) "font-weight above range" false
    (property_value_supported FontWeight (IntValue 1001));
  Alcotest.(check bool) "line-height unitless" true
    (property_value_supported LineHeight (StringValue "1.5"));
  Alcotest.(check bool) "line-height px" true
    (property_value_supported LineHeight (StringValue "18px"));
  Alcotest.(check bool) "letter-spacing negative ok" true
    (property_value_supported LetterSpacing (FloatValue (-0.5)));
  Alcotest.(check bool) "letter-spacing non-finite rejected" false
    (property_value_supported LetterSpacing (FloatValue nan));
  Alcotest.(check bool) "position enum" true
    (property_value_supported Position (StringValue "absolute"));
  Alcotest.(check bool) "position rejects sticky" false
    (property_value_supported Position (StringValue "sticky"));
  Alcotest.(check bool) "inset finite" true
    (property_value_supported Inset (FloatValue 0.0));
  Alcotest.(check bool) "inset non-finite rejected" false
    (property_value_supported InsetTop (FloatValue infinity));
  Alcotest.(check bool) "z-index int" true
    (property_value_supported ZIndex (IntValue 40));
  Alcotest.(check bool) "white-space enum" true
    (property_value_supported WhiteSpace (StringValue "nowrap"));
  Alcotest.(check bool) "white-space rejects pre" false
    (property_value_supported WhiteSpace (StringValue "pre"));
  Alcotest.(check bool) "text-overflow enum" true
    (property_value_supported TextOverflow (StringValue "ellipsis"));
  Alcotest.(check bool) "overflow enum" true
    (property_value_supported Overflow (StringValue "hidden"));
  Alcotest.(check bool) "overflow rejects scroll" false
    (property_value_supported Overflow (StringValue "scroll"));
  Alcotest.(check bool) "user-select enum" true
    (property_value_supported UserSelect (StringValue "none"));
  Alcotest.(check bool) "cursor enum" true
    (property_value_supported Cursor (StringValue "pointer"));
  Alcotest.(check bool) "shadow inset ring" true
    (property_value_supported Shadow
       (StringValue "inset 0 0 0 1px var(--color-primary)"));
  Alcotest.(check bool) "shadow none" true
    (property_value_supported HoverShadow (StringValue "none"));
  Alcotest.(check bool) "state color props" true
    (property_value_supported HoverBackground (StringValue "accent")
     && property_value_supported PressedBackground (StringValue "accent")
     && property_value_supported SelectedBackground (StringValue "accent"));
  Alcotest.(check bool) "state opacity bounds" true
    (property_value_supported PressedOpacity (FloatValue 0.7)
     && property_value_supported DisabledOpacity (FloatValue 0.5));
  Alcotest.(check bool) "state opacity out of range" false
    (property_value_supported HoverOpacity (FloatValue 1.5));
  Alcotest.(check bool) "state shadow props" true
    (property_value_supported FocusShadow
       (StringValue "0 0 0 2px var(--color-ring)")
     && property_value_supported SelectedShadow
          (StringValue "inset 0 0 0 1px var(--color-primary)")
     && property_value_supported SelectedHoverShadow
          (StringValue "inset 0 0 0 1px var(--color-primary)"));
  Alcotest.(check bool) "viewport fraction" true
    (property_value_supported MaxHeightViewport (FloatValue 0.65));
  Alcotest.(check bool) "viewport out of range" false
    (property_value_supported WidthViewport (FloatValue 1.2));
  Alcotest.(check bool) "typography on text kinds" true
    (property_supported Text FontSize && property_supported Label LineHeight
     && property_supported Heading FontWeight
     && property_supported Paragraph LetterSpacing);
  Alcotest.(check bool) "typography not on icon" false
    (property_supported Icon FontSize);
  Alcotest.(check bool) "position on box" true
    (property_supported Box Position);
  Alcotest.(check bool) "position not on root" false
    (property_supported Root Position);
  Alcotest.(check bool) "position not on tooltip" false
    (property_supported Tooltip Position);
  Alcotest.(check bool) "position not on dialog" false
    (property_supported Dialog Inset);
  Alcotest.(check bool) "overflow on text" true
    (property_supported Text Overflow);
  Alcotest.(check bool) "overflow not on scroll" false
    (property_supported Scroll Overflow);
  Alcotest.(check bool) "state props on list-item" true
    (property_supported ListItem HoverBackground
     && property_supported ListItem SelectedShadow
     && property_supported ListItem DisabledOpacity
     && property_supported Button PressedOpacity
     && property_supported Button FocusShadow);
  Alcotest.(check bool) "state props not on tooltip/root" false
    (property_supported Tooltip HoverBackground
     || property_supported Root HoverBackground);
  Alcotest.(check bool) "viewport sizes on dialog" true
    (property_supported Dialog WidthViewport
     && property_supported Dialog MaxHeightViewport);
  Alcotest.(check bool) "min-viewport <= max-viewport" true
    (node_properties_supported Row
       (Property_map.add MinHeightViewport (FloatValue 0.3)
          (Property_map.add MaxHeightViewport (FloatValue 0.65)
             Property_map.empty)));
  Alcotest.(check bool) "min-viewport > max-viewport rejected" false
    (node_properties_supported Row
       (Property_map.add MinHeightViewport (FloatValue 0.8)
          (Property_map.add MaxHeightViewport (FloatValue 0.65)
             Property_map.empty)));
  let text_node = ref 0 in
  let row_node = ref 0 in
  let app =
    Lui_app.create (recording_backend ()) ()
      (fun model _action -> model)
      (fun _context _model_source _send ->
         Lui_elements.column
           [ capture_node text_node
               (Lui_elements.text ~font_size:"0.75rem" ~font_weight:500
                  ~line_height:"1.4" ~letter_spacing:(-0.5)
                  ~white_space:"nowrap" ~text_overflow:"ellipsis"
                  ~overflow:"hidden" []);
             capture_node row_node (fun context parent ->
                let node = Lui_elements.row ~grow:1.0 [] context parent in
                Lui_ui.string_property context node Position "absolute";
                Lui_ui.float_property context node Inset 0.0;
                Lui_ui.int_property context node ZIndex 40;
                Lui_ui.string_property context node UserSelect "none";
                Lui_ui.string_property context node Cursor "pointer";
                Lui_ui.string_property context node Shadow
                  "inset 0 0 0 1px var(--color-primary)";
                Lui_ui.string_property context node HoverBackground "accent";
                Lui_ui.float_property context node PressedOpacity 0.7;
                Lui_ui.string_property context node FocusShadow
                  "0 0 0 2px var(--color-ring)";
                Lui_ui.string_property context node SelectedShadow
                  "inset 0 0 0 1px var(--color-primary)";
                Lui_ui.float_property context node DisabledOpacity 0.5;
                Lui_ui.float_property context node MaxHeightViewport 0.65;
                node) ])
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  let emitted property value =
    List.exists
      (function
         | Lui_protocol.SetProp (id, property', value') ->
           (id = !text_node || id = !row_node)
           && property' = property && value' = value
         | _ -> false)
      ops
  in
  List.iter
    (fun (property, value) ->
       Alcotest.(check bool)
         (Printf.sprintf "emitted %s"
            (Lui_wire_schema.property_name property))
         true (emitted property value))
    [ (FontSize, StringValue "0.75rem");
      (FontWeight, IntValue 500);
      (LineHeight, StringValue "1.4");
      (LetterSpacing, FloatValue (-0.5));
      (WhiteSpace, StringValue "nowrap");
      (TextOverflow, StringValue "ellipsis");
      (Overflow, StringValue "hidden");
      (Position, StringValue "absolute");
      (Inset, FloatValue 0.0);
      (ZIndex, IntValue 40);
      (UserSelect, StringValue "none");
      (Cursor, StringValue "pointer");
      (Shadow, StringValue "inset 0 0 0 1px var(--color-primary)");
      (HoverBackground, StringValue "accent");
      (PressedOpacity, FloatValue 0.7);
      (FocusShadow, StringValue "0 0 0 2px var(--color-ring)");
      (SelectedShadow, StringValue "inset 0 0 0 1px var(--color-primary)");
      (DisabledOpacity, FloatValue 0.5);
      (MaxHeightViewport, FloatValue 0.65) ]

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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_elements.number_stepper ~value:5.0 ~min:0.0 ~max:3660.0
               ~step:1.0 ~text:"Days"
               ~on_value_changed:(fun event ->
                  match event with
                  | Lui_protocol.ValueChanged (_, value) ->
                      changes := value :: !changes
                  | _ -> ())
               [] ])
      ()
  in
  let stepper = drive_node s (Drive.Model.Kind "number-stepper") in
  let check_prop name value =
    Alcotest.(check bool) name true (drive_prop s stepper name = Some value)
  in
  check_prop "value" (Lui_protocol.FloatValue 5.0);
  check_prop "min" (Lui_protocol.FloatValue 0.0);
  check_prop "max" (Lui_protocol.FloatValue 3660.0);
  check_prop "step" (Lui_protocol.FloatValue 1.0);
  check_prop "text" (Lui_protocol.StringValue "Days");
  Drive.Session.value_changed s stepper.Drive.Model.id 5.0;
  Drive.Session.value_changed s stepper.Drive.Model.id 6.0;
  Alcotest.(check (list (float 0.0))) "echo dropped, change delivered"
    [ 6.0 ] !changes;
  drive_dispose s

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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model)
      ~view:(fun _context _model_source _send ->
         Lui_elements.column
           [ Lui_elements.sheet ~text:"Settings"
               ~detents:"medium,large" ~sizing:"form" [] ])
      ()
  in
  let sheet = drive_node s (Drive.Model.Kind "sheet") in
  Alcotest.(check bool) "detents emitted" true
    (drive_prop s sheet "detents"
     = Some (Lui_protocol.StringValue "medium,large"));
  Alcotest.(check bool) "sizing emitted" true
    (drive_prop s sheet "sizing" = Some (Lui_protocol.StringValue "form"));
  Alcotest.(check bool) "detents only on sheet" true
    (Lui_protocol.property_supported Lui_protocol.Sheet Lui_protocol.Detents);
  Alcotest.(check bool) "detents off dialog" false
    (Lui_protocol.property_supported Lui_protocol.Dialog
       Lui_protocol.Detents);
  drive_dispose s

let test_theme_tokens_json () =
  Alcotest.(check string) "fixed + adaptive values"
    {|{"background":{"light":"#fff","dark":"#000"},"primary":"#7c3aed"}|}
    (Lui_ui.theme_tokens_json
       [ ( "background",
           Lui_ui.Adaptive { light = "#fff"; dark = "#000" } );
         ("primary", Lui_ui.Fixed "#7c3aed") ])

(* ---------- Lui_json_view: the language-neutral view-model layer ---------- *)

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
  let s =
    drive_mount ~initial:()
      ~reducer:(fun model _action -> model) ~view ()
  in
  let tree = drive_tree s in
  List.iter
    (fun k ->
       Alcotest.(check bool)
         (Printf.sprintf "created %s" k)
         true (Drive.Model.exists tree (Drive.Model.Kind k)))
    [ "card"; "switch"; "slider"; "icon"; "toggle-button";
      "table"; "table-row"; "table-cell"; "radio-group"; "radio";
      "stepper"; "step"; "bottom-tabs"; "bottom-tab"; "input-group";
      "input-group-actions"; "button"; "split"; "textarea"; "text" ];
  (* unknown kinds render a visible placeholder, never a blank/raise *)
  Alcotest.(check bool) "placeholder text" true
    (Drive.Model.exists tree (Drive.Model.Text "unsupported component"));
  (* events on a node carrying "id" route through the event sink *)
  let b1 = drive_node s (Drive.Model.Kind "toggle-button") in
  Drive.Session.toggle s b1.Drive.Model.id true;
  Alcotest.(check (list (pair string string))) "event routed"
    [ ("b1", "toggle") ]
    (List.map (fun (id, k, _) -> (id, k)) !events);
  Alcotest.(check bool) "checked field decoded" true
    (match !events with
     | [ (_, _, [ ("checked", Lui_json_view.Bool true) ]) ] -> true
     | _ -> false);
  drive_dispose s

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
  let s =
    drive_mount ~initial:() ~reducer:(fun model _ -> model)
      ~view:(fun _context _model _send ->
        Lui_element_combine.composer ~placeholder:"Synthetic draft"
          ~text:"One line"
          ~attachments:(Lui_elements.text ~value:"Synthetic attachment" []) ())
      ()
  in
  let tree = drive_tree s in
  let composer_root =
    match
      Hashtbl.find_opt tree.Drive.Model.nodes (Lui_app.root_node (drive_app s))
    with
    | Some n -> n
    | None -> Alcotest.fail "composer root missing from drive tree"
  in
  Alcotest.(check bool) "composer does not fill available overlay height" true
    (match Drive.Model.prop tree composer_root.Drive.Model.id "grow" with
     | Some (Lui_protocol.FloatValue value) -> value <= 0.
     | _ -> true);
  let textarea = drive_node s (Drive.Model.Kind "textarea") in
  Alcotest.(check bool) "textarea has a bounded content height" true
    (match drive_prop s textarea "max-height" with
     | Some (Lui_protocol.IntValue value) -> value > 36 && value <= 200
     | _ -> false);
  drive_dispose s

let test_composer_attachment_preview_and_remove () =
  List.iter (fun disabled ->
    let removals = ref 0 in
    let s =
      drive_mount ~initial:() ~reducer:(fun model _ -> model)
        ~view:(fun _context _model _send ->
          Lui_element_combine.composer_attachment ~disabled
            ~key:"synthetic-pdf" ~path:"/tmp/synthetic.pdf"
            ~title:"Synthetic PDF" ~file_type:"pdf"
            ~on_remove:(fun _ -> incr removals) ())
        ()
    in
    let labelled name =
      Drive.Model.Prop ("accessibility-label", Lui_protocol.StringValue name)
    in
    drive_press s (labelled "Preview Synthetic PDF");
    let native_preview = drive_node s (Drive.Model.Kind "file-preview") in
    Drive.Session.dismiss s native_preview.Drive.Model.id;
    drive_press s (labelled "Remove Synthetic PDF");
    Alcotest.(check int) "disabled removal cannot mutate a saving draft"
      (if disabled then 0 else 1) !removals;
    drive_dispose s) [false; true]

let test_composer_feedback_above_actions () =
  let s =
    drive_mount ~initial:() ~reducer:(fun model _ -> model)
      ~view:(fun _context _model _send ->
        Lui_element_combine.composer ~placeholder:"Synthetic draft"
          ~feedback:(Lui_elements.text ~value:"Synthetic camera unavailable" [])
          ~on_send:(fun _ -> ())
          ())
      ()
  in
  let tree = drive_tree s in
  let feedback =
    drive_node s
      (Drive.Model.Prop
         ("text", Lui_protocol.StringValue "Synthetic camera unavailable"))
  in
  let actions =
    drive_node s
      (Drive.Model.Prop
         ("accessibility-identifier",
          Lui_protocol.StringValue "row.composer.controls"))
  in
  let index_in_parent (n : Drive.Model.node) =
    match n.Drive.Model.parent with
    | Some p -> (
      match Hashtbl.find_opt tree.Drive.Model.nodes p with
      | Some parent ->
        List.find_index (fun c -> c = n.Drive.Model.id)
          parent.Drive.Model.children
      | None -> None)
    | None -> None
  in
  Alcotest.(check bool) "feedback shares surface and reserves space above controls"
    true
    (match
       ( feedback.Drive.Model.parent
       , actions.Drive.Model.parent
       , index_in_parent feedback
       , index_in_parent actions )
     with
     | Some p, Some p', Some i, Some i' -> p = p' && i < i'
     | _ -> false);
  drive_dispose s

let test_composer_separate_input_and_cards () =
  let s =
    drive_mount ~initial:() ~reducer:(fun model _ -> model)
      ~view:(fun _context _model _send ->
        Lui_element_combine.composer ~placeholder:"Message"
          ~actions:[Lui_elements.button ~label:"Add attachment" []]
          ~on_send:(fun _ -> ())
          ~attachments:(Lui_elements.row ~gap:8
            [Lui_element_combine.composer_attachment
               ~key:"photo" ~path:"/tmp/photo.png" ~title:"Photo"
               ~file_type:"image/png" ~on_remove:(fun _ -> ()) ();
             Lui_element_combine.composer_attachment
               ~key:"document" ~path:"/tmp/report.pdf"
               ~title:"A very long report name that must stay inside its card.pdf"
               ~file_type:"application/pdf" ~on_remove:(fun _ -> ()) ()]) ()) ()
  in
  let labelled name = Drive.Model.Prop
      ("accessibility-label", Lui_protocol.StringValue name) in
  let field = drive_node s (Drive.Model.Kind "textarea") in
  let add = drive_node s (labelled "Add attachment") in
  let send = drive_node s (labelled "Send") in
  let input_row = match field.Drive.Model.parent with
    | Some id -> Option.get (Hashtbl.find_opt (drive_tree s).Drive.Model.nodes id)
    | None -> Alcotest.fail "input row missing" in
  Alcotest.(check (list string)) "input owns its whole row" ["textarea"]
    (drive_kind_names s input_row);
  Alcotest.(check bool) "actions never compete with input width" true
    (field.Drive.Model.parent <> add.Drive.Model.parent
     && field.Drive.Model.parent <> send.Drive.Model.parent);
  let image = drive_node s (Drive.Model.Kind "file-image") in
  Alcotest.(check bool) "MIME image fills a square thumbnail" true
    (drive_prop s image "width" = Some (Lui_protocol.IntValue 120)
     && drive_prop s image "height" = Some (Lui_protocol.IntValue 120)
     && drive_prop s image "image-fit" = Some (Lui_protocol.StringValue "fill"));
  let remove = drive_node s (labelled "Remove Photo") in
  Alcotest.(check bool) "removal uses a 44pt icon target" true
    (drive_prop s remove "width" = Some (Lui_protocol.IntValue 44)
     && drive_prop s remove "height" = Some (Lui_protocol.IntValue 44)
     && drive_prop s remove "text" = None);
  let title = drive_node s (Drive.Model.Prop
      ("text", Lui_protocol.StringValue "A very long report name that must stay inside its card.pdf")) in
  Alcotest.(check bool) "document name keeps its bounded leading-aligned area" true
    (drive_prop s title "max-width" = Some (Lui_protocol.IntValue 96)
     && drive_prop s title "text-alignment" = Some (Lui_protocol.StringValue "start"));
  let strip = drive_node s (Drive.Model.Kind "scroll") in
  Alcotest.(check bool) "attachments stay horizontally scrollable" true
    (drive_prop s strip "orientation" = Some (Lui_protocol.StringValue "horizontal"));
  let surface = match input_row.Drive.Model.parent with
    | Some id -> Option.get (Hashtbl.find_opt (drive_tree s).Drive.Model.nodes id)
    | None -> Alcotest.fail "composer surface missing" in
  let index id = Option.get (List.find_index ((=) id) surface.Drive.Model.children) in
  Alcotest.(check bool) "input precedes attachments and controls" true
    (index input_row.Drive.Model.id < index strip.Drive.Model.id);
  drive_dispose s

let test_composer_editing_with_busy_action_row () =
  List.iter (fun initial ->
    let edits = ref [] and sends = ref 0 and discards = ref 0 and adds = ref 0 in
    let s = drive_mount ~initial:() ~reducer:(fun model _ -> model)
      ~view:(fun _context _model _send ->
        Lui_element_combine.composer ~placeholder:"New thought…"
          ~text:initial
          ~on_input:(fun event -> match event with
            | Lui_protocol.TextChanged (_, text) -> edits := text :: !edits
            | _ -> ())
          ~actions:(List.init 5 (fun n -> Lui_elements.button
            ~width:44 ~height:44 ~label:("Action " ^ string_of_int n)
            ~on_press:(fun _ -> if n = 0 then incr adds else if n = 4 then incr discards) []))
          ~on_send:(fun _ -> incr sends) ()) () in
    let field = drive_node s (Drive.Model.Kind "textarea") in
    let input_row = match field.Drive.Model.parent with
      | Some id -> Option.get (Hashtbl.find_opt (drive_tree s).Drive.Model.nodes id)
      | None -> Alcotest.fail "input row missing" in
    Alcotest.(check (list string)) "five actions leave input alone" ["textarea"]
      (drive_kind_names s input_row);
    let action_strip = drive_node s (Drive.Model.Prop
      ("accessibility-identifier", Lui_protocol.StringValue "scroll.composer.actions")) in
    Alcotest.(check bool) "narrow screens can scroll actions without moving input or send" true
      (drive_prop s action_strip "orientation" = Some (Lui_protocol.StringValue "horizontal")
       && drive_prop s action_strip "min-width" = Some (Lui_protocol.IntValue 0));
    let edited = initial ^ "\n中文新行" in
    Drive.Session.text_changed s field.Drive.Model.id edited;
    Alcotest.(check (list string)) "multiline Unicode edit reaches owner" [edited] !edits;
    let next_field = drive_node s (Drive.Model.Kind "textarea") in
    Alcotest.(check int) "editing retains native field identity" field.Drive.Model.id next_field.Drive.Model.id;
    drive_press s (Drive.Model.Prop ("accessibility-label", Lui_protocol.StringValue "Action 0"));
    drive_press s (Drive.Model.Prop ("accessibility-label", Lui_protocol.StringValue "Action 4"));
    drive_press s (Drive.Model.Prop ("accessibility-label", Lui_protocol.StringValue "Send"));
    Alcotest.(check (list int)) "attachment, cancel and send still dispatch" [1; 1; 1] [!adds; !discards; !sends];
    drive_dispose s)
    [""; "Single line"; "First\nSecond\nThird"; "中文输入，随宽度自动换行。";
     String.make 800 'x'; String.concat "\n" (List.init 30 (fun n -> string_of_int n))]

let test_picked_files_batch () =
  let decode json = match Lui_picked_files.decode json with
    | Ok result -> result
    | Error message -> Alcotest.fail message in
  let batch = decode {|{"request":7,"failures":1,"files":[
    {"path":"/tmp/z.png","name":"图片.png","content-type":"image/png"},
    {"name":"missing path"},
    {"path":"/tmp/a.txt","name":"A \"note\".txt","content-type":"text/plain"}]}|} in
  Alcotest.(check (list string)) "ordered valid files survive partial failure"
    ["/tmp/z.png"; "/tmp/a.txt"]
    (List.map (fun (file : Lui_picked_files.file) -> file.path) batch.files);
  Alcotest.(check int) "each failed entry is visible" 2 batch.failures;
  Alcotest.(check bool) "numeric token is preserved" true (batch.request = `Int 7);
  let empty = decode {|{"request":"cancelled","files":[]}|} in
  Alcotest.(check int) "empty batch remains empty" 0 (List.length empty.files);
  List.iter (fun source -> Alcotest.(check bool) "invalid envelope rejected" true
    (Result.is_error (Lui_picked_files.decode source)))
    ["{}"; "[]"; "{\"request\":true,\"files\":[]}"; "{\"request\":1,\"files\":[] } trailing"]

let test_gallery_composer_batches () =
  let file n : Lui_picked_files.file =
    { path = Printf.sprintf "/tmp/synthetic-%d.txt" n;
      name = Printf.sprintf "Synthetic %d" n; content_type = "text/plain" } in
  let picked request files : Lui_picked_files.t =
    {request = `Int request; files; failures = 0} in
  let request m = Model.update m (Model.ComposerRequest `files) in
  let paths m = List.map (fun (f : Lui_picked_files.file) -> f.path) m.Model.composer_files in
  let first = request Model.initial in
  let first = Model.update first (Model.ComposerPicked (picked 1 [file 2; file 1])) in
  Alcotest.(check (list string)) "a whole selection arrives in order"
    [(file 2).path; (file 1).path] (paths first);
  let cancelled = Model.update (request first) Model.ComposerCancelled in
  Alcotest.(check (list string)) "cancel preserves attachments" (paths first) (paths cancelled);
  let next = request cancelled in
  let stale = Model.update next (Model.ComposerPicked (picked 1 [file 9])) in
  Alcotest.(check (list string)) "stale result cannot mutate the current request" (paths first) (paths stale);
  let next = Model.update next (Model.ComposerPicked
    (picked next.Model.composer_request [file 1; file 3; file 3; file 4])) in
  Alcotest.(check (list string)) "existing and in-batch duplicate paths are skipped"
    (List.map (fun n -> (file n).path) [2;1;3;4]) (paths next);
  let removed = Model.update next (Model.ComposerRemove (file 1).path) in
  let readded = request removed in
  let readded = Model.update readded (Model.ComposerPicked (picked readded.Model.composer_request [file 1])) in
  Alcotest.(check (list string)) "removed item can be readded at the end"
    (List.map (fun n -> (file n).path) [2;3;4;1]) (paths readded);
  let limited = request readded in
  let limited = Model.update limited (Model.ComposerPicked
    (picked limited.Model.composer_request (List.init 12 (fun n -> file (n + 10))))) in
  Alcotest.(check int) "demo caps pending attachments at eight" 8 (List.length limited.Model.composer_files);
  Alcotest.(check bool) "limit feedback is visible" true (limited.Model.composer_feedback <> "");
  let sent = Model.update limited Model.ComposerSend in
  Alcotest.(check int) "demo send clears owned attachments" 0 (List.length sent.Model.composer_files)



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
  let profile =
    match host_profile with
    | Some p -> p
    | None ->
      if apple then
        Lui_protocol.profile Lui_protocol.IOS Lui_protocol.SwiftUIHost
      else Lui_protocol.generic_profile ()
  in
  let label_slot = Signal.state_slot "navigation-root-label" in
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
  let s =
    drive_mount ~registry:(Lui_navigation.registry ()) ~profile
      ~initial:Lui_navigation.Path.empty ~reducer:(fun _ path -> path)
      ~view ()
  in
  (s, root_mounts, destination_mounts, root_disposes, destination_disposes, callback_count, edit)

let navigation_send s path =
  ignore (Lui_app.send (drive_app s) path);
  drive_flush s

let navigation_root s = Lui_app.root_node (drive_app s)

let navigation_prop s name =
  Drive.Model.prop (drive_tree s) (navigation_root s) name

let navigation_revision s =
  match navigation_prop s "revision" with
  | Some (Lui_protocol.IntValue r) -> r
  | _ -> Alcotest.fail "navigation revision is absent"

let navigation_event s revision name length =
  let open Lui_protocol in
  let fields = String_map.(empty |> add "revision" (IntValue revision)
    |> add "length" (IntValue length)) in
  Drive.Session.extension_event s ~node:(navigation_root s)
    ~identifier:"navigation-stack" ~name ~fields

let test_navigation_retains () =
  let s, roots, destinations, root_disposes, destination_disposes, callbacks, edit = navigation_fixture () in
  let push () = navigation_send s (Lui_navigation.Path.push "detail" (Lui_app.model (drive_app s))) in
  push (); push ();
  Alcotest.(check int) "root mounted once" 1 !roots;
  Alcotest.(check int) "each duplicate destination mounted once" 2 !destinations;
  Alcotest.(check int) "covered scope alive" 0 !root_disposes;
  Alcotest.(check int) "covered destination scope alive" 0 !destination_disposes;
  Option.iter (fun edit -> edit "after") !edit; drive_flush s;
  Alcotest.(check bool) "covered root still observes local edits" true
    (Drive.Model.exists (drive_tree s)
       (Drive.Model.Prop ("text", Lui_protocol.StringValue "after")));
  navigation_send s (Lui_navigation.Path.pop_to_root (Lui_app.model (drive_app s)));
  Alcotest.(check int) "programmatic changes do not echo" 0 !callbacks;
  Alcotest.(check int) "outgoing retained before settlement" 0 !destination_disposes;
  navigation_event s (navigation_revision s) "settled" 0;
  Alcotest.(check int) "outgoing released after settlement" 2 !destination_disposes;
  Alcotest.(check int) "root survives return" 1 !roots;
  drive_dispose s;
  Alcotest.(check int) "root disposed once on owner teardown" 1 !root_disposes

let test_navigation_back () =
  List.iter (fun reenter ->
    let s, _, mounts, _, disposes, callbacks, _ = navigation_fixture ~reenter () in
    let path = Lui_navigation.Path.(push "b" (push "a" empty)) in
    navigation_send s path;
    let old = navigation_revision s in
    navigation_event s old "path-changed" 1;
    Alcotest.(check int) "one committed callback" 1 !callbacks;
    Alcotest.(check int) "callback path or reentrant replacement wins" (if reenter then 2 else 1)
      (List.length (Lui_navigation.Path.entries (Lui_app.model (drive_app s))));
    navigation_event s old "path-changed" 0;
    navigation_event s old "settled" 1;
    Alcotest.(check int) "old revision ignored" 1 !callbacks;
    Alcotest.(check int) "old settlement cannot drop outgoing" 0 !disposes;
    navigation_event s (navigation_revision s) "settled" (if reenter then 2 else 1);
    Alcotest.(check int) "removed entry released exactly once" 1 !disposes;
    Alcotest.(check int) "retained entry not rebuilt" (if reenter then 3 else 2) !mounts;
    drive_dispose s) [false; true]

let test_navigation_rejects_invalid () =
  let s, _, _, _, _, callbacks, _ = navigation_fixture ~accept:false () in
  let path = Lui_navigation.Path.push "detail" Lui_navigation.Path.empty in
  navigation_send s path;
  let revision = navigation_revision s in
  List.iter (fun length -> navigation_event s revision "path-changed" length) [-1; 1; 2];
  Alcotest.(check int) "invalid and echo paths ignored" 0 !callbacks;
  navigation_event s revision "path-changed" 0;
  Alcotest.(check int) "proposal delivered" 1 !callbacks;
  Alcotest.(check int) "owner may reject proposal" 1 (List.length (Lui_navigation.Path.entries (Lui_app.model (drive_app s))));
  Alcotest.(check bool) "rejection publishes a fresh revision" true (revision <> navigation_revision s);
  navigation_event s revision "path-changed" 0;
  Alcotest.(check int) "rejected proposal cannot repeat" 1 !callbacks;
  drive_dispose s

let test_navigation_rapid_and_switch () =
  let s, _, mounts, _, disposes, _, _ = navigation_fixture () in
  let first = Lui_navigation.Path.push "first" Lui_navigation.Path.empty in
  navigation_send s first;
  let old = navigation_revision s in
  navigation_send s Lui_navigation.Path.empty;
  navigation_send s first;
  Alcotest.(check int) "repush outgoing identity reuses subtree" 1 !mounts;
  navigation_event s old "settled" 1;
  Alcotest.(check int) "stale completion leaves live entry" 0 !disposes;
  let replacement = Lui_navigation.Path.push "new graph" Lui_navigation.Path.empty in
  navigation_send s replacement;
  navigation_event s old "path-changed" 0;
  Alcotest.(check bool) "old graph callback cannot overwrite new graph" true (Lui_app.model (drive_app s) = replacement);
  navigation_event s (navigation_revision s) "settled" 1;
  Alcotest.(check int) "old graph entry cleaned" 1 !disposes;
  drive_dispose s;
  Alcotest.(check int) "all destination scopes cleaned" 2 !disposes

let test_navigation_fallback () =
  let open Lui_protocol in
  List.iter (fun host_profile ->
  let s, roots, mounts, root_disposes, disposes, callbacks, _ = navigation_fixture ~host_profile ~apple:false () in
  navigation_send s Lui_navigation.Path.(push "b" (push "a" empty));
  Alcotest.(check int) "fallback retains root" 1 !roots;
  Alcotest.(check int) "fallback mounts both entries" 2 !mounts;
  Alcotest.(check int) "covered fallback scope alive" 0 !root_disposes;
  drive_press s (Drive.Model.Kind "button");
  Alcotest.(check int) "fallback Back commits one proposal" 1 !callbacks;
  Alcotest.(check int) "fallback Back returns to covered entry" 1
    (List.length (Lui_navigation.Path.entries (Lui_app.model (drive_app s))));
  Alcotest.(check int) "fallback Back preserves entry mount" 2 !mounts;
  navigation_send s Lui_navigation.Path.empty;
  Alcotest.(check int) "no-animation fallback cleans immediately" 2 !disposes;
  Alcotest.(check int) "fallback programmatic path does not echo" 1 !callbacks;
  drive_dispose s)
    [generic_profile (); profile WebOS WebHost;
     profile LinuxOS GPUIHost; profile WindowsOS GPUIHost]

let test_navigation_queued_stale () =
  let s, _, _, _, _, callbacks, _ = navigation_fixture () in
  navigation_send s Lui_navigation.Path.(push "old" empty);
  let revision = navigation_revision s in
  let replacement = Lui_navigation.Path.(push ("new" ^ " graph") empty) in
  (* The owner write is staged, but not flushed before the old host event. *)
  ignore (Lui_app.send (drive_app s) replacement);
  navigation_event s revision "path-changed" 0;
  Alcotest.(check int) "queued owner write invalidates old callback" 0 !callbacks;
  Alcotest.(check bool) "queued replacement wins" true (Lui_app.model (drive_app s) = replacement);
  drive_dispose s

let test_navigation_host_fingerprint () =
  let source = read_file (Filename.concat (source_root ())
      "platform/apple/Sources/LUIAppleBackend/LUINavigation.swift") in
  let mismatches = Lui_extension_check.check_registry (Lui_navigation.registry ()) source in
  if mismatches <> [] then Alcotest.fail (Lui_extension_check.describe_mismatches mismatches)

let test_navigation_entry_state () =
  let open Lui_navigation in
  let slot = Signal.state_slot "detail-local" in
  let states = Hashtbl.create 4 in
  let s =
    drive_mount ~registry:(registry ())
      ~profile:(Lui_protocol.profile Lui_protocol.IOS Lui_protocol.SwiftUIHost)
      ~initial:Path.empty ~reducer:(fun _ path -> path)
      ~view:(fun _ source send ->
    navigation_stack ~path_signal:source ~on_path_change:(fun path -> ignore (send path))
      ~root:(Lui_elements.box [])
      ~destination:(fun entry context parent ->
        let local = Signal.state_at context.Lui_ui.ui_scheduler context.Lui_ui.ui_state_scope slot 0 in
        Hashtbl.add states entry.id (local, context.Lui_ui.ui_state_scope);
        Lui_elements.text ~value_signal:(Signal.map string_of_int (Signal.value local)) [] context parent) ()) ()
  in
  let a = Path.push (fun () -> "same") Path.empty in
  let b = Path.push (fun () -> "same") a in
  navigation_send s b;
  let entries = Path.entries b in
  let first = (List.hd entries).id and second = (List.hd (List.tl entries)).id in
  let first_state, first_scope = Hashtbl.find states first in
  let second_state, second_scope = Hashtbl.find states second in
  Signal.set first_state 7; Signal.set second_state 9; drive_flush s;
  navigation_send s (Path.pop b);
  Alcotest.(check int) "covered local state preserved" 7 (Signal.get_state first_state);
  Alcotest.(check bool) "covered entry state scope active" true (not !(first_scope.Signal.disposed_scope));
  Alcotest.(check bool) "outgoing state lives during transition" true (not !(second_scope.Signal.disposed_scope));
  navigation_event s (navigation_revision s) "settled" 1;
  Alcotest.(check bool) "only removed entry state disposed" false (not !(second_scope.Signal.disposed_scope));
  Alcotest.(check bool) "remaining entry state still active" true (not !(first_scope.Signal.disposed_scope));
  drive_dispose s;
  Alcotest.(check bool) "owner teardown disposes surviving state" false (not !(first_scope.Signal.disposed_scope))


(* .drive scenarios: the same selector/event DSL the CLI drives over FFI,
   socket and WebSocket attach, replayed here against the in-process driver
   so the scripts run in the unit suite. *)
let run_drive_scenario file s =
  let source =
    read_file
      (Filename.concat (source_root ())
         (Filename.concat "test/scenarios" file))
  in
  (match
     Drive.Scenario.run ~emit:ignore (Drive.Session.driver s) source
   with
   | [] -> ()
   | failures ->
     Alcotest.failf "%s\n%s" file
       (String.concat "\n"
          (List.map
             (fun (f : Drive.Scenario.failure) ->
                Printf.sprintf "line %d: %s" f.line f.message)
             failures)));
  drive_dispose s

let test_drive_scenarios () =
  run_drive_scenario "todo.drive"
    (drive_mount ~initial:[ "write tests" ] ~reducer:todo_reducer
       ~view:todo_drive_view ());
  run_drive_scenario "counter.drive"
    (drive_mount ~initial:0 ~reducer:counter_reducer ~view:counter_view ())

let test_toast_padding () =
  let open Lui_protocol in
  List.iter (fun property ->
      Alcotest.(check bool) "toast padding" true
        (property_supported Toast property))
    [ PaddingValue; PaddingHorizontal; PaddingVertical ]

let () =
  Alcotest.run "lui"
    [
      ("audit regressions", Test_audit.tests);
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
          Alcotest.test_case "composer separate input and square cards" `Quick test_composer_separate_input_and_cards;
          Alcotest.test_case "composer editing with busy action row" `Quick test_composer_editing_with_busy_action_row;
          Alcotest.test_case "ordered picked file batches" `Quick test_picked_files_batch;
          Alcotest.test_case "gallery composer batches" `Quick test_gallery_composer_batches;
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
          Alcotest.test_case "large subtree drop is one detach" `Quick
            test_drop_large_subtree_is_one_detach;
        ] );
      ( "protocol",
        [
          Alcotest.test_case "toast padding" `Quick test_toast_padding;
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
          Alcotest.test_case "visual appearance props" `Quick
            test_visual_appearance_props;
          Alcotest.test_case "data-attrs protocol" `Quick
            test_data_attrs_protocol;
          Alcotest.test_case "finite float encoding" `Quick
            test_float_encoding_rejects_non_finite;
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
          Alcotest.test_case "keyed mount failure keeps rows" `Quick
            test_keyed_mount_failure_keeps_previous_rows;
        ] );
      ( "dispatch",
        [
          Alcotest.test_case "pointer events" `Quick test_pointer_events;
          Alcotest.test_case "pointer dispatch" `Quick test_pointer_dispatch;
          Alcotest.test_case "value echoes dropped" `Quick
            test_dispatch_drops_value_echoes;
          Alcotest.test_case "unset default echoes dropped" `Quick
            test_dispatch_drops_unset_default_echoes;
          Alcotest.test_case "return to default is delivered" `Quick
            test_value_return_to_default_is_delivered;
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
      ( "scenarios",
        [
          Alcotest.test_case "drive scripts" `Quick test_drive_scenarios;
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
