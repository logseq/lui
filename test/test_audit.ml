open Lui_protocol

let backend apply_batch = { backend_profile = generic_profile (); apply_batch }
let runtime () = Lui_runtime.create (Signal.scheduler ()) (backend (fun _ -> true))
let attempt f = try f (); None with exn -> Some exn
let check_failure label result = Alcotest.(check bool) label true (Option.is_some result)

type closure_model = { callback : unit -> string }

let boundary_fixture () =
  let emitted = ref [] in
  let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun batch ->
    emitted := batch.ops; true)) in
  let scope = Signal.scope "boundary-tests" in
  app, scope, Lui_ui.context app scope, emitted

let text_values app =
  Hashtbl.fold (fun _ properties values ->
    match Property_map.find_opt TextValue properties with
    | Some (StringValue value) -> value :: values
    | _ -> values) app.Lui_runtime.runtime_properties []

let partial_view context parent =
  ignore (Lui_elements.text ~value:"partial" [] context parent);
  failwith "view failed"

let boundary_initial_mount () =
  let app, scope, context, emitted = boundary_fixture () in
  let sibling = Lui_ui.text context "sibling" in
  let diagnostic = ref None in
  ignore (Lui_elements.error_boundary ~fallback:(fun error ->
    diagnostic := Some error;
    Lui_elements.text ~value:"fallback" []) partial_view context None);
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "failed mount reports its exception and phase" true
    (match !diagnostic with
     | Some { exception_ = Failure message; phase = `Mount; state_path; _ } ->
         message = "view failed" && state_path <> ""
     | _ -> false);
  Alcotest.(check bool) "unrelated pending node survives rollback" true
    (Lui_runtime.node_live app sibling);
  Alcotest.(check (list string)) "only sibling and fallback survive" ["fallback"; "sibling"]
    (List.sort String.compare (text_values app));
  Alcotest.(check bool) "partial writes do not reach the batch" false
    (List.exists (function SetProp (_, TextValue, StringValue "partial") -> true | _ -> false) !emitted);
  Signal.dispose_scope scope

let boundary_shared_publication_work () =
  let measure count =
    let app, scope, context, _ = boundary_fixture () in
    let source = Signal.state context.ui_scheduler "before" in
    let child context parent =
      let container = Lui_ui.column context in
      Lui_elements.attach context parent container;
      for _ = 1 to count do
        let node = Lui_ui.text_signal context (Signal.value source) in
        Lui_elements.attach context (Some container) node
      done;
      container in
    ignore (Lui_elements.error_boundary
      ~fallback:(fun _ -> Lui_elements.text ~value:"unexpected" []) child context None);
    Signal.mount scope;
    ignore (Lui_runtime.flush app);
    Gc.full_major ();
    let allocated = Gc.allocated_bytes () and started = Sys.time () in
    Signal.set source "after";
    ignore (Lui_runtime.flush app);
    let elapsed = Sys.time () -. started in
    let allocated = Gc.allocated_bytes () -. allocated in
    Printf.printf "boundary publication N=%d allocated=%.0f bytes time=%.6fs\n%!"
      count allocated elapsed;
    Alcotest.(check int) "every binding publishes" count
      (List.length (List.filter ((=) "after") (text_values app)));
    Signal.dispose_scope scope;
    allocated in
  let small = measure 100 and large = measure 1000 in
  Alcotest.(check bool) "tenfold fanout has linear checkpoint allocation" true
    (large < 25. *. small)

let boundary_publication_rollback () =
  List.iter (fun broken_fallback ->
    let app, scope, context, emitted = boundary_fixture () in
    let outside = Lui_ui.text context "outside" in
    let source = Signal.state context.ui_scheduler "before" in
    let inner_errors = ref 0 and outer_errors = ref 0 in
    let child context parent =
      let first = Lui_ui.map context (fun value ->
        if value = "bad" then begin
          Lui_ui.string_property context outside TextValue "partial";
          "partial"
        end else value) (Signal.value source) in
      let node = Lui_ui.text_signal context first in
      Lui_elements.attach context parent node;
      let second = Lui_ui.map context (fun value ->
        if value = "bad" then failwith "late publication failure" else value)
          (Signal.value source) in
      let node = Lui_ui.text_signal context second in
      Lui_elements.attach context parent node;
      node in
    let inner = Lui_elements.error_boundary ~fallback:(fun _ ->
      incr inner_errors;
      if broken_fallback then partial_view else Lui_elements.text ~value:"inner" []) child in
    ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
      incr outer_errors;
      Lui_elements.text ~value:"outer" [])
      (Lui_elements.column [Lui_elements.text ~value:"stable" []; inner]) context None);
    Signal.mount scope;
    ignore (Lui_runtime.flush app);
    Signal.set source "successful";
    ignore (Lui_runtime.flush app);
    Alcotest.(check int) "successful wave updates both bindings" 2
      (List.length (List.filter ((=) "successful") (text_values app)));
    Signal.set source "bad";
    ignore (Lui_runtime.flush app);
    Alcotest.(check int) "inner boundary catches first" 1 !inner_errors;
    Alcotest.(check int) "fallback failures propagate outward"
      (if broken_fallback then 1 else 0) !outer_errors;
    Alcotest.(check (list string)) "whole publication rolls back opaque writes"
      (if broken_fallback then ["outer"; "outside"] else ["inner"; "outside"; "stable"])
      (List.sort String.compare (text_values app));
    Alcotest.(check bool) "partial writes never reach the host" false
      (List.exists (function
        | SetProp (_, TextValue, StringValue "partial") -> true | _ -> false) !emitted);
    Signal.dispose_scope scope) [false; true]

let boundary_interleaved_fallbacks () =
  let app, scope, context, _ = boundary_fixture () in
  let source = Signal.state context.ui_scheduler "before" in
  let deferred = ref (fun () -> ()) in
  let first_errors = ref 0 and second_errors = ref 0 in
  let bind context parent project =
    let value = Lui_ui.map context project (Signal.value source) in
    let node = Lui_ui.text_signal context value in
    Lui_elements.attach context parent node;
    node in
  let fail value = if value = "bad" then failwith "interleaved failure" else value in
  ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
    incr second_errors; Lui_elements.text ~value:"second fallback" [])
    (fun context parent ->
      let node = bind context parent Fun.id in
      deferred := (fun () -> ignore (bind context parent fail));
      node) context None);
  ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
    incr first_errors; Lui_elements.text ~value:"first fallback" [])
    (fun context parent -> bind context parent fail) context None);
  !deferred ();
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Signal.set source "bad";
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "first sibling latched" 1 !first_errors;
  Alcotest.(check int) "second sibling latched" 1 !second_errors;
  Alcotest.(check (list string)) "both committed fallbacks survive interleaved callbacks"
    ["first fallback"; "second fallback"] (List.sort String.compare (text_values app));
  Signal.set source "later";
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "latched fallbacks remain mounted"
    ["first fallback"; "second fallback"] (List.sort String.compare (text_values app));
  Signal.dispose_scope scope

let boundary_sibling_mount_work () =
  let measure count =
    let app, scope, context, _ = boundary_fixture () in
    Gc.full_major ();
    let allocated = Gc.allocated_bytes () and started = Sys.time () in
    for _ = 1 to count do
      ignore (Lui_elements.error_boundary
        ~fallback:(fun _ -> Lui_elements.text ~value:"unexpected" [])
        (Lui_elements.text ~value:"child" []) context None)
    done;
    Signal.mount scope;
    ignore (Lui_runtime.flush app);
    let elapsed = Sys.time () -. started in
    let allocated = Gc.allocated_bytes () -. allocated in
    Printf.printf "boundary sibling mount N=%d allocated=%.0f bytes time=%.6fs\n%!"
      count allocated elapsed;
    Alcotest.(check int) "all sibling contents mount" count
      (List.length (List.filter ((=) "child") (text_values app)));
    Signal.dispose_scope scope;
    allocated in
  let small = measure 100 and large = measure 1000 in
  Alcotest.(check bool) "tenfold sibling count has linear mount allocation" true
    (large < 25. *. small)

let boundary_committed_outer_recovery () =
  let app, scope, context, emitted = boundary_fixture () in
  let outside = Lui_ui.text context "outside" in
  let source = Signal.state context.ui_scheduler "before" in
  let bind context parent project =
    let value = Lui_ui.map context project (Signal.value source) in
    let node = Lui_ui.text_signal context value in
    Lui_elements.attach context parent node;
    node in
  let fail value = if value = "bad" then failwith "outer publication" else value in
  let inner = Lui_elements.error_boundary ~fallback:(fun _ context parent ->
    Lui_ui.string_property context outside ForegroundValue "#334455";
    Lui_elements.text ~value:"inner fallback" [] context parent)
    (fun context parent -> bind context parent fail) in
  ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
    Lui_elements.text ~value:"outer fallback" [])
    (fun context parent ->
      ignore (bind context parent (fun value ->
        if value = "bad" then Lui_ui.string_property context outside TextValue "partial";
        value));
      ignore (inner context parent);
      bind context parent fail) context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Signal.set source "bad";
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "outer rollback restores its writes but replaces nested content"
    ["outer fallback"; "outside"] (List.sort String.compare (text_values app));
  Alcotest.(check bool) "committed recovery on another property survives outer rollback" true
    (Property_map.find_opt ForegroundValue (Hashtbl.find app.runtime_properties outside)
      = Some (StringValue "#334455"));
  Alcotest.(check bool) "uncommitted outer writes never reach the host" false
    (List.exists (function SetProp (_, TextValue, StringValue "partial") -> true | _ -> false) !emitted);
  Signal.dispose_scope scope

let boundary_journal_savepoints () =
  let app, scope, context, emitted = boundary_fixture () in
  let parent = Lui_ui.column context in
  let outside = Lui_ui.text context "outside" in
  let stable = Lui_ui.text context "stable" in
  Lui_ui.append context parent stable;
  ignore (Lui_runtime.flush app);
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context outside TextValue "partial";
  let transient = Lui_ui.text context "transient" in
  Lui_ui.append context parent transient;
  Lui_runtime.on_event scope app outside (fun _ -> ());
  let recovery = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context outside ForegroundValue "#334455";
  let permanent = Lui_ui.text context "permanent" in
  Lui_ui.append context parent permanent;
  Lui_runtime.on_event scope app outside (fun _ -> ());
  Lui_runtime.commit_boundary_recovery app recovery;
  Lui_runtime.rollback_boundary app saved;
  Alcotest.(check (list int)) "committed insertion survives rollback of a sibling insertion"
    [stable; permanent] (Lui_runtime.children app parent);
  Alcotest.(check bool) "uncommitted node removed" false (Lui_runtime.node_live app transient);
  Alcotest.(check (list string)) "independent properties roll back separately"
    ["outside"; "permanent"; "stable"] (List.sort String.compare (text_values app));
  Alcotest.(check bool) "committed foreground retained" true
    (Property_map.find_opt ForegroundValue (Hashtbl.find app.runtime_properties outside)
      = Some (StringValue "#334455"));
  Alcotest.(check int) "only committed handler survives" 1 (Lui_runtime.handler_count app);
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "committed insertion is reindexed for the host" true
    (List.exists (function InsertChild (owner, child, 1) ->
      owner = parent && child = permanent | _ -> false) !emitted);
  Alcotest.(check bool) "partial operations dropped" false
    (List.exists (function SetProp (_, TextValue, StringValue ("partial" | "transient")) -> true
      | _ -> false) !emitted);
  Alcotest.(check int) "journal compacted after recovery flush" 0
    (List.length app.runtime_journal.journal_entries);
  check_failure "stale savepoint rejected" (attempt (fun () -> Lui_runtime.rollback_boundary app saved));
  Signal.dispose_scope scope

let boundary_nested_mount_rollback () =
  let app, scope, context, emitted = boundary_fixture () in
  let inner = Lui_elements.error_boundary ~fallback:(fun _ ->
    Lui_elements.text ~value:"inner fallback" [])
    (fun _ _ -> failwith "inner mount") in
  ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
    Lui_elements.text ~value:"outer fallback" [])
    (fun context parent ->
      ignore (inner context parent);
      failwith "outer mount") context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "only enclosing fallback remains"
    ["outer fallback"] (text_values app);
  Alcotest.(check bool) "no insert refers to a rolled back parent" true
    (List.for_all (function InsertChild (parent, _, _) -> Lui_runtime.node_live app parent
      | _ -> true) !emitted);
  Signal.dispose_scope scope

let boundary_echo_rollback () =
  let app, scope, context, _ = boundary_fixture () in
  let node = Lui_ui.text_field context in
  Lui_ui.string_property context node TextValue "before";
  ignore (Lui_runtime.flush app);
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context node TextValue "discarded";
  let recovery = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context node ForegroundValue "#334455";
  Lui_runtime.commit_boundary_recovery app recovery;
  Lui_runtime.rollback_boundary app saved;
  Alcotest.(check bool) "discarded text is not a host echo" false
    (Lui_runtime.event_is_value_echo app node (TextChanged (node, "discarded")));
  Signal.dispose_scope scope

let boundary_journal_compaction () =
  List.iter (fun outcome ->
    let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun _ ->
      match outcome with
      | `Applied -> true
      | `Rejected -> false
      | `Exception -> failwith "backend failure"
      | `Empty -> Alcotest.fail "empty flush called the host")) in
    let saved = Lui_runtime.boundary_savepoint app in
    (match outcome with `Empty -> () | _ -> ignore (Lui_runtime.create_node app Text));
    let error = attempt (fun () -> ignore (Lui_runtime.flush app)) in
    Alcotest.(check bool) "backend failures propagate"
      (outcome = `Exception || outcome = `Rejected)
      (Option.is_some error);
    Alcotest.(check int) "journal entries released" 0
      (List.length app.runtime_journal.journal_entries);
    Alcotest.(check int) "journal versions released" 0
      (Hashtbl.length app.runtime_journal.journal_versions);
    Alcotest.(check bool) "savepoint expires at flush end" false
      (Lui_runtime.boundary_savepoint_valid app saved))
    [`Empty; `Applied; `Rejected; `Exception]

let rollback_host_fixture () =
  let host = Hashtbl.create 16 and parents = Hashtbl.create 16 in
  let tweaks = Hashtbl.create 16 in
  let children node = match Hashtbl.find_opt host node with
    | Some children -> children
    | None -> Alcotest.failf "host references missing node %d" node in
  let unlink parent child =
    let current = children parent in
    if not (List.mem child current) then Alcotest.fail "host removes a missing edge";
    Hashtbl.replace host parent (List.filter ((<>) child) current);
    Hashtbl.remove parents child in
  let rec detach node =
    List.iter detach (children node);
    Option.iter (fun parent -> unlink parent node) (Hashtbl.find_opt parents node);
    Hashtbl.remove host node in
  let insert parent child index =
    ignore (children child);
    if Hashtbl.mem tweaks child && List.length (children child) <> 1 then
      Alcotest.fail "host attaches an incomplete tweak";
    let current = children parent in
    if index < 0 || index > List.length current then Alcotest.fail "host insert index";
    Hashtbl.replace host parent (Lui_runtime.insert_list index child current);
    Hashtbl.replace parents child parent in
  let registry = Lui_extension.registry () in
  Lui_extension.register_tweak registry
    (Lui_extension.tweak "boundary-tweak" [generic_profile ()] []);
  let app = Lui_runtime.create_with_extensions (Signal.scheduler ())
    (backend (fun batch ->
      List.iter (function
        | CreateNode (node, _) -> Hashtbl.replace host node []
        | CreateExtension (node, _, _) ->
            Hashtbl.replace host node []; Hashtbl.replace tweaks node ()
        | InsertChild (parent, child, index) -> insert parent child index
        | RemoveChild (parent, child) ->
            ignore (children child); unlink parent child
        | MoveChild (parent, child, index) -> unlink parent child; insert parent child index
        | DropNode node | DetachSubtree node -> detach node
        | _ -> ()) batch.ops;
      true)) registry in
  let scope = Signal.scope "rollback-host" in
  let verify () =
    let ids table = Hashtbl.to_seq_keys table |> List.of_seq |> List.sort Int.compare in
    let expected = List.sort Int.compare
      (ids app.mounted_nodes @ ids app.runtime_extension_nodes) in
    Alcotest.(check (list int)) "host has exactly the runtime nodes" expected (ids host);
    Hashtbl.iter (fun parent actual ->
      Alcotest.(check (list int)) "host child order matches runtime"
        (Lui_runtime.children app parent) actual) host in
  app, scope, Lui_ui.context app scope, verify

let boundary_host_detach_descendants () =
  let app, scope, context, verify = rollback_host_fixture () in
  let parent = Lui_ui.column context in
  let content = Lui_ui.column context in
  Lui_ui.append context parent content;
  Lui_ui.append context content (Lui_ui.text context "descendant");
  ignore (Lui_runtime.flush app);
  verify ();
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context parent BackgroundValue "#334455";
  Lui_runtime.rollback_boundary app saved;
  Lui_runtime.drop_subtree app content;
  ignore (Lui_runtime.flush app);
  verify ();
  Signal.dispose_scope scope

let boundary_host_detach_unlink () =
  let app, scope, context, verify = rollback_host_fixture () in
  let parent = Lui_ui.column context in
  let child = Lui_ui.column context in
  Lui_ui.append context parent child;
  Lui_ui.append context child (Lui_ui.text context "descendant");
  ignore (Lui_runtime.flush app);
  Lui_runtime.drop_subtree app child;
  ignore (Lui_runtime.flush app);
  verify ();
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context parent BackgroundValue "#334455";
  Lui_runtime.rollback_boundary app saved;
  ignore (Lui_runtime.flush app);
  verify ();
  Signal.dispose_scope scope

let boundary_host_tweak_order () =
  for offset = 0 to 15 do
    let app, scope, context, verify = rollback_host_fixture () in
    for _ = 1 to offset do ignore (Lui_ui.box context) done;
    let parent = Lui_ui.column context in
    ignore (Lui_runtime.flush app);
    let saved = Lui_runtime.boundary_savepoint app in
    Lui_ui.string_property context parent BackgroundValue "#334455";
    Lui_runtime.rollback_boundary app saved;
    let recovery = Lui_runtime.boundary_savepoint app in
    let tweak = Lui_ui.platform_tweak context "boundary-tweak" in
    Lui_ui.append context tweak (Lui_ui.text context "fallback");
    Lui_ui.append context parent tweak;
    Lui_runtime.commit_boundary_recovery app recovery;
    ignore (Lui_runtime.flush app);
    verify ();
    Signal.dispose_scope scope
  done

let boundary_resync_selection () =
  let app, scope, context, emitted = boundary_fixture () in
  let node = Lui_ui.text context "before" in
  ignore (Lui_runtime.flush app);
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_runtime.rollback_boundary app saved;
  Alcotest.(check bool) "empty rollback needs no resync" false
    !(app.runtime_resync_required);
  Lui_ui.string_property context node TextValue "successful";
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "successful publication stays incremental" false
    (List.exists (function DetachSubtree _ -> true | _ -> false) !emitted);
  Lui_ui.string_property context node TextValue "pending";
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context node TextValue "partial";
  Lui_runtime.rollback_boundary app saved;
  Alcotest.(check bool) "queued rollback schedules authoritative resync" true
    !(app.runtime_resync_required);
  Alcotest.(check int) "entire pending delta is discarded" 0
    (List.length !(app.pending_ops));
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "resync removes the accepted host root" true
    (List.exists (function DetachSubtree root -> root = node | _ -> false) !emitted);
  Alcotest.(check bool) "resync preserves earlier pending state" true
    (List.exists (function SetProp (root, TextValue, StringValue "pending") ->
      root = node | _ -> false) !emitted);
  Alcotest.(check bool) "failed writes are not serialized" false
    (List.exists (function SetProp (_, TextValue, StringValue "partial") -> true
      | _ -> false) !emitted);
  Signal.dispose_scope scope

let boundary_resync_sizes () =
  let app, scope, context, emitted = boundary_fixture () in
  let node = Lui_ui.box context in
  ignore (Lui_runtime.flush app);
  Lui_runtime.set_prop app node WidthValue (IntValue 10);
  Lui_runtime.set_prop app node MinWidth (IntValue 100);
  let saved = Lui_runtime.boundary_savepoint app in
  Lui_ui.string_property context node BackgroundValue "#334455";
  Lui_runtime.rollback_boundary app saved;
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "surviving sizes normalize before resync" true
    (Property_map.find_opt WidthValue (Hashtbl.find app.runtime_properties node)
      = Some (IntValue 100));
  Lui_runtime.remove_prop app node MinWidth;
  ignore (Lui_runtime.flush app);
  Lui_runtime.set_prop app node WidthValue (IntValue 10);
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "later authored width is not skipped" true
    (List.exists (function SetProp (owner, WidthValue, IntValue 10) ->
      owner = node | _ -> false) !emitted);
  Signal.dispose_scope scope

let boundary_reactive_update () =
  let app, scope, context, emitted = boundary_fixture () in
  let source = Signal.state context.ui_scheduler 0 in
  let mounts = ref 0 and failures = ref 0 in
  let child context parent =
    let parent = Option.get parent in
    ignore (Lui_dynamic.switch context parent (Signal.value source) Int.equal
      (fun context value ->
        incr mounts;
        if value = 1 then partial_view context None
        else begin
          let node = Lui_ui.text context (string_of_int value) in
          Lui_ui.on_event context node (fun _ -> ());
          node
        end));
    parent in
  ignore (Lui_elements.error_boundary ~fallback:(fun error ->
    incr failures;
    Alcotest.(check bool) "update diagnostic" true (error.phase = `Update);
    Lui_elements.text ~value:"fallback" []) child context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "successful initial view" ["0"] (text_values app);
  Signal.set source 2;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "successful reactive update" ["2"] (text_values app);
  Signal.set source 1;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "failed branch replaced" ["fallback"] (text_values app);
  Alcotest.(check bool) "partial reactive writes discarded" false
    (List.exists (function SetProp (_, TextValue, StringValue "partial") -> true | _ -> false) !emitted);
  Signal.set source 3;
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "failed child is not retried" 3 !mounts;
  Alcotest.(check int) "diagnostic emitted once" 1 !failures;
  Alcotest.(check int) "failed subscriptions released" 0 (Lui_runtime.dynamic_segment_count app);
  Alcotest.(check int) "rolled-back handlers are released" 0 !(app.runtime_handler_count);
  Alcotest.(check (list string)) "fallback stays latched" ["fallback"] (text_values app);
  Signal.dispose_scope scope

let boundary_nested () =
  List.iter (fun broken_fallback ->
    let app, scope, context, _ = boundary_fixture () in
    let outer_errors = ref 0 and inner_errors = ref 0 in
    let inner = Lui_elements.error_boundary ~fallback:(fun _ ->
      incr inner_errors;
      if broken_fallback then partial_view
      else Lui_elements.text ~value:"inner" []) partial_view in
    ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
      incr outer_errors;
      Lui_elements.text ~value:"outer" []) inner context None);
    ignore (Lui_runtime.flush app);
    Alcotest.(check int) "nearest boundary handles the child" 1 !inner_errors;
    Alcotest.(check int) "fallback failure reaches enclosing boundary"
      (if broken_fallback then 1 else 0) !outer_errors;
    Alcotest.(check (list string)) "no partial nested view survives"
      [if broken_fallback then "outer" else "inner"] (text_values app);
    Signal.dispose_scope scope) [false; true]

let boundary_property_projection () =
  let app, scope, context, _ = boundary_fixture () in
  let source = Signal.state context.ui_scheduler "ok" in
  let child context parent =
    let projected = Lui_ui.map context (fun value ->
      if value = "bad" then failwith "projection failed" else value) (Signal.value source) in
    let node = Lui_ui.text_signal context projected in
    Lui_elements.attach context parent node;
    node in
  ignore (Lui_elements.error_boundary
    ~fallback:(fun _ -> Lui_elements.text ~value:"fallback" []) child context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Signal.set source "bad";
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "owned projection failures are isolated" ["fallback"] (text_values app);
  Signal.dispose_scope scope

let boundary_reactive_attributes () =
  let app, scope, context, _ = boundary_fixture () in
  let attributes = Signal.state context.ui_scheduler [] in
  let failures = ref 0 in
  let child = Lui_elements.row ~data_attrs_signal:(Signal.value attributes)
    [Lui_elements.text ~value:"child" []] in
  ignore (Lui_elements.error_boundary ~fallback:(fun error ->
    incr failures;
    Alcotest.(check bool) "attribute update diagnostic" true (error.phase = `Update);
    Lui_elements.text ~value:"fallback" []) child context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "empty attributes mount" ["child"] (text_values app);
  Signal.set attributes ["data-state", "ready"];
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "valid attributes publish" true
    (Hashtbl.fold (fun _ properties found -> found ||
      Property_map.find_opt DataAttrs properties =
        Some (StringValue (data_attrs_encode ["data-state", "ready"])))
      app.Lui_runtime.runtime_properties false);
  Signal.set attributes ["id", "unsupported"];
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "encoding failure caught once" 1 !failures;
  Alcotest.(check (list string)) "attribute failure isolated" ["fallback"] (text_values app);
  Signal.set attributes [];
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "attribute fallback stays latched" ["fallback"] (text_values app);
  Signal.dispose_scope scope

let boundary_retained_rows () =
  List.iter (fun virtualized ->
    let app, scope, context, _ = boundary_fixture () in
    let source = Signal.state context.ui_scheduler [1, "ok"] in
    let failures = ref 0 in
    let mount item_source context parent =
      let projected = Lui_ui.map context (fun (_, value) ->
        if value = "bad" then failwith "row projection failed" else value) item_source in
      let node = Lui_ui.text_signal context projected in
      Lui_elements.attach context parent node;
      node in
    let source = Signal.value source, source in
    let rows = if virtualized then
        Lui_elements.virtual_list [Lui_elements.virtual_rows ~source:(fst source)
          ~key:fst ~cmp:Int.compare ~mount ()]
      else Lui_elements.column [Lui_elements.keyed ~source:(fst source)
        ~key:fst ~cmp:Int.compare ~mount] in
    ignore (Lui_elements.error_boundary ~fallback:(fun _ ->
      incr failures; Lui_elements.text ~value:"fallback" []) rows context None);
    Signal.mount scope;
    ignore (Lui_runtime.flush app);
    Alcotest.(check (list string)) "initial row" ["ok"] (text_values app);
    Signal.set (snd source) [1, "updated"];
    ignore (Lui_runtime.flush app);
    Alcotest.(check (list string)) "retained row updates" ["updated"] (text_values app);
    Signal.set (snd source) [1, "bad"];
    ignore (Lui_runtime.flush app);
    Alcotest.(check int) "row failure caught once" 1 !failures;
    Alcotest.(check (list string)) "row failure isolated" ["fallback"] (text_values app);
    Signal.set (snd source) [];
    ignore (Lui_runtime.flush app);
    Alcotest.(check (list string)) "row fallback stays latched" ["fallback"] (text_values app);
    Alcotest.(check int) "row subscriptions released" 0 (Lui_runtime.dynamic_segment_count app);
    Signal.dispose_scope scope) [false; true]

let numeric_normalization () =
  List.iter (fun property ->
    List.iter (fun number ->
      Alcotest.(check bool) "nonnegative scalar canonicalized" true
        (normalize_property_value property (IntValue number) = IntValue (max 0 number)))
      [-7; 0; 12])
    [WidthValue; HeightValue; MinWidth; MaxWidth; MinHeight; MaxHeight; Gap;
     PaddingValue; PaddingHorizontal; PaddingVertical; PaddingTop; PaddingRight;
     PaddingBottom; PaddingLeft; BorderWidth; CornerRadius; TooltipDelay;
     DurationValue; ResizeDuration];
  List.iter (fun property ->
    List.iter (fun (number, expected) ->
      Alcotest.(check bool) "opacity canonicalized with finite fallback" true
        (normalize_property_value property (FloatValue number) = FloatValue expected))
      [-0.5, 0.; 0.4, 0.4; 1.5, 1.; nan, 1.; infinity, 1.; neg_infinity, 1.])
    [Opacity; LabelOpacity; HoverOpacity; PressedOpacity; DisabledOpacity];
  Alcotest.(check bool) "empty dimensions stay absent" true
    (Property_map.is_empty (normalize_size_properties Property_map.empty));
  let emitted = ref [] in
  let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun batch ->
    emitted := batch.ops; true)) in
  let node = Lui_runtime.create_node app Box in
  List.iter (fun (property, value) -> Lui_runtime.set_prop app node property value)
    [WidthValue, IntValue 10; MinWidth, IntValue 100; MaxWidth, IntValue 50;
     HeightValue, IntValue 500; MinHeight, IntValue (-5); MaxHeight, IntValue 200;
     PaddingValue, IntValue (-4); Opacity, FloatValue nan];
  ignore (Lui_runtime.flush app);
  let properties = List.fold_left (fun properties -> function
    | SetProp (id, property, value) when id = node -> Property_map.add property value properties
    | _ -> properties) Property_map.empty !emitted in
  List.iter (fun (property, expected) ->
    Alcotest.(check bool) "wire carries canonical value" true
      (Property_map.find_opt property properties = Some expected))
    [WidthValue, IntValue 100; MinWidth, IntValue 100; MaxWidth, IntValue 100;
     HeightValue, IntValue 200; MinHeight, IntValue 0; MaxHeight, IntValue 200;
     PaddingValue, IntValue 0; Opacity, FloatValue 1.];
  Alcotest.check_raises "wrong types still reject"
    (Invalid_argument "invalid property value: kind=box prop=width value=\"bad\"")
    (fun () -> Lui_runtime.set_prop app node WidthValue (StringValue "bad"));
  Lui_runtime.set_prop app node WidthValue (IntValue 1000);
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "later fixed size clamps to effective maximum" true
    (List.exists (function SetProp (_, WidthValue, IntValue 100) -> true | _ -> false) !emitted)

let closure_subtree_publication () =
  let app = runtime () in
  let scheduler = app.Lui_runtime.runtime_scheduler in
  let scope = Signal.scope "closure-switch" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let initial = { callback = (fun () -> "initial") } in
  let source = Signal.state scheduler initial in
  let mounts = ref 0 in
  ignore (Lui_dynamic.switch context parent (Signal.value source)
    Lui_elements.default_subtree_equal (fun row model ->
      incr mounts; Lui_ui.text row (model.callback ())));
  Signal.set source initial;
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "physical republish retains branch" 1 !mounts;
  List.iter (fun label ->
    Signal.set source { callback = (fun () -> label) };
    ignore (Lui_runtime.flush app)) ["second"; "third"];
  Alcotest.(check int) "functional publications mount repeatedly" 3 !mounts;
  Signal.dispose_scope scope

let duplicate_keyed_publication () =
  let app = runtime () in
  let scheduler = app.Lui_runtime.runtime_scheduler in
  let scope = Signal.scope "duplicate-rows" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let source = Signal.state scheduler [1; 1; 2] in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item -> Lui_ui.text row (string_of_int (Signal.sample item))));
  ignore (Lui_runtime.flush app);
  let initial = Lui_runtime.children app parent in
  Alcotest.(check int) "all duplicates mount" 3 (List.length initial);
  Signal.set source [1; 2; 1];
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "occurrences retain deterministic identities"
    [List.nth initial 0; List.nth initial 2; List.nth initial 1]
    (Lui_runtime.children app parent);
  Signal.set source [];
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "empty publication clears duplicates" []
    (Lui_runtime.children app parent);
  Signal.dispose_scope scope

let rejected_batch_resync () =
  let reject = ref false and batches = ref [] in
  let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun batch ->
    batches := batch :: !batches; not !reject)) in
  let node = Lui_runtime.create_node app Text in
  Lui_runtime.set_prop app node TextValue (StringValue "initial");
  ignore (Lui_runtime.flush app);
  reject := true;
  Lui_runtime.set_prop app node TextValue (StringValue "rejected");
  check_failure "rejection reported" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check bool) "rejected delta not requeued" true (!(app.pending_ops) = []);
  let snapshot = DetachSubtree node :: (Lui_runtime.resync_batch app).ops in
  check_failure "rejected recovery remains scheduled"
    (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check bool) "recovery runs without new pending operations" true
    ((List.hd !batches).ops = snapshot);
  Lui_runtime.set_prop app node TextValue (StringValue "latest");
  let expected = DetachSubtree node :: (Lui_runtime.resync_batch app).ops in
  reject := false;
  ignore (Lui_runtime.flush app);
  let recovered = List.hd !batches in
  Alcotest.(check bool) "next turn sends authoritative latest snapshot" true
    (recovered.ops = expected);
  Alcotest.(check int) "recovery uses next host generation" 2 recovered.generation;
  let count = List.length !batches in
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "idle turn sends no further snapshot" count (List.length !batches);
  Lui_runtime.set_prop app node TextValue (StringValue "after");
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "later deltas progress" 3 (List.hd !batches).generation

let keyed_states () =
  let app = runtime () in
  let scheduler = app.Lui_runtime.runtime_scheduler in
  let scope = Signal.scope "rows" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let source = Signal.state scheduler [1; 2] in
  let slot = Signal.state_slot "draft" in
  let states = Hashtbl.create 2 in
  let rows = Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item ->
      let key = Signal.sample item in
      let value = Signal.state_at scheduler row.Lui_ui.ui_state_scope slot key in
      Hashtbl.replace states key (value, row.ui_state_scope);
      Lui_ui.text row (string_of_int key)) in
  let first, _ = Hashtbl.find states 1 in
  let second, second_scope = Hashtbl.find states 2 in
  Alcotest.(check int) "independent row initialization" 2 (Signal.get_state second);
  Signal.set first 99;
  Signal.set source [2; 1];
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "other row unchanged" 2 (Signal.get_state second);
  Alcotest.(check (list int)) "reordered nodes" [Lui_dynamic.keyed_node rows 2; Lui_dynamic.keyed_node rows 1]
    (Lui_runtime.children app parent);
  Signal.set source [1]; ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "removed row state disposed" true (Signal.scope_is_disposed second_scope);
  Signal.set source [1; 2]; ignore (Lui_runtime.flush app);
  let fresh, _ = Hashtbl.find states 2 in
  Alcotest.(check bool) "reinsertion has fresh state" false (fresh == second);
  Signal.dispose_scope scope

let extension_retry () =
  let calls = ref 0 in
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry
    (Lui_extension.component "audit-widget" [generic_profile ()] false []
      [Lui_extension.property "title" StringScalar true None] []);
  let app = Lui_runtime.create_with_extensions (Signal.scheduler ())
    (backend (fun _ -> incr calls; true)) registry in
  let node = Lui_runtime.create_extension_node app "audit-widget" in
  let flush () = ignore (Lui_runtime.flush app) in
  check_failure "first invalid batch rejected" (attempt flush);
  check_failure "retry still rejected" (attempt flush);
  Alcotest.(check int) "invalid batch never reaches host" 0 !calls;
  Lui_runtime.set_extension_prop app node "title" (StringValue "valid");
  flush ();
  Alcotest.(check int) "corrected batch commits" 1 !calls

let backend_failure () =
  let batches = ref [] and app_ref = ref None in
  let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun batch ->
    batches := batch :: !batches;
    if batch.generation = 1 then begin
      let app = Option.get !app_ref in
      Lui_runtime.set_prop app 1 TextValue (StringValue "reentrant");
      failwith "commit uncertain"
    end;
    true)) in
  app_ref := Some app;
  let node = Lui_runtime.create_node app Text in
  Alcotest.(check int) "node id" 1 node;
  check_failure "exception preserved" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check int) "failed generation consumed" 1 (Lui_runtime.generation app);
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "sequential generations" [1; 2]
    (List.map (fun batch -> batch.generation) (List.rev !batches));
  Alcotest.(check bool) "reentrant write retained" true
    (List.exists (function SetProp (_, TextValue, StringValue "reentrant") -> true | _ -> false)
      (List.hd !batches).ops)

let subscription_failure () =
  let cancelled = ref 0 in
  let subscription = Signal.make_subscription (fun () -> incr cancelled) in
  let coordinator = Lui_subscriptions.create () in
  let spec key start = { Lui_subscriptions.subscription_key = key;
    subscription_fingerprint = "v1"; start_subscription = start } in
  ignore (attempt (fun () -> ignore (Lui_subscriptions.reconcile coordinator 1
    [spec "first" (fun () -> subscription); spec "second" (fun () -> failwith "startup failed")])));
  Lui_subscriptions.dispose coordinator;
  Alcotest.(check int) "started subscription cancelled" 1 !cancelled

let view ?(mount_failure=false) label _context _model _send context _parent =
  if mount_failure then Signal.on_mount context.Lui_ui.ui_scope (fun () -> failwith "mount failed");
  Lui_ui.text context label

let check_resync mirror application =
  let restored = Drive.Model.create () in
  let snapshot = Lui_runtime.resync_batch application in
  Drive.Model.apply_batch restored snapshot;
  Alcotest.(check int) "all live nodes restored" (Drive.Model.node_count mirror)
    (Drive.Model.node_count restored);
  Hashtbl.iter
    (fun id (expected : Drive.Model.node) ->
      let actual = Hashtbl.find restored.Drive.Model.nodes id in
      Alcotest.(check string) "node kind restored" expected.kind actual.kind;
      Alcotest.(check (option int)) "parent restored" expected.parent actual.parent;
      Alcotest.(check (list int)) "child order restored"
        (Drive.Model.node_children expected) (Drive.Model.node_children actual);
      let props node =
        Hashtbl.to_seq node.Drive.Model.props |> List.of_seq |> List.sort compare
      in
      Alcotest.(check bool) "properties restored" true (props expected = props actual))
    mirror.Drive.Model.nodes;
  Alcotest.(check int) "current generation restored" (Drive.Model.generation mirror)
    (Drive.Model.generation restored);
  restored

let resync_default_app () =
  let mirror = Drive.Model.create () in
  let next = ref None in
  let app = Lui_app.create (backend (fun batch ->
    next := Some batch; Drive.Model.apply_batch mirror batch; true))
    () (fun model () -> model) (view "snow\000雪😀") in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  let restored = check_resync mirror (Lui_app.runtime app) in
  let root = Lui_app.root_node app in
  Lui_runtime.set_prop (Lui_app.runtime app) root TextValue (StringValue "updated");
  ignore (Lui_app.flush app);
  Drive.Model.apply_batch restored (Option.get !next);
  let node = Hashtbl.find restored.Drive.Model.nodes root in
  Alcotest.(check bool) "later deltas update restored tree" true
    (Hashtbl.find node.props "text" = StringValue "updated")

let resync_detached_nodes () =
  let mirror = Drive.Model.create () in
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry
    (Lui_extension.component "audit-widget" [generic_profile ()] true []
      [Lui_extension.property "title" StringScalar true None] []);
  let app = Lui_runtime.create_with_extensions (Signal.scheduler ())
    (backend (fun batch -> Drive.Model.apply_batch mirror batch; true)) registry in
  let root = Lui_runtime.create_node app Root in
  let child = Lui_runtime.create_node app Column in
  Lui_runtime.insert_child app root child 0;
  let floating = Lui_runtime.create_extension_node app "audit-widget" in
  Lui_runtime.set_extension_prop app floating "title" (StringValue "floating");
  let first = Lui_runtime.create_node app Text in
  let second = Lui_runtime.create_node app Text in
  Lui_runtime.insert_child app floating first 0;
  Lui_runtime.insert_child app floating second 1;
  ignore (Lui_runtime.flush app);
  ignore (check_resync mirror app);
  Lui_runtime.drop_subtree app first;
  ignore (Lui_runtime.flush app);
  ignore (check_resync mirror app)

let reload_app apply =
  let app = Lui_app.create_reloadable (backend apply) "old" "contract" ()
    (fun model () -> model) (view "old") in
  ignore (Lui_app.start app); ignore (Lui_app.flush app); app

let reload_mount_failure () =
  let calls = ref 0 in
  let app = reload_app (fun _ -> incr calls; true) in
  let state = Option.get app.Lui_app.app_reload_state in
  let old = !(state.reload_view_scope) in
  let request = Lui_app.request_reload app in
  let status = Lui_app.reload_view app request "new" "contract" (view ~mount_failure:true "new") 0 in
  Alcotest.(check bool) "reload rejected" true
    (match status with Lui_hot_reload.ReloadRejected _ -> true | _ -> false);
  Alcotest.(check int) "mount failure happens before host commit" 1 !calls;
  Alcotest.(check bool) "old scope remains mounted" true (Signal.active old);
  Alcotest.(check bool) "scope reference remains valid" true (!(state.reload_view_scope) == old);
  let request = Lui_app.request_reload app in
  ignore (Lui_app.reload_view app request "valid" "contract" (view "valid") 0);
  Alcotest.(check string) "next reload works" "valid" (Lui_hot_reload.source_hash state.reload_session)

let reload_commit_failure () =
  let throwing = ref false in
  let app = reload_app (fun _ -> if !throwing then invalid_arg "host commit uncertain" else true) in
  throwing := true;
  let request = Lui_app.request_reload app in
  let status = Lui_app.reload_view app request "new" "contract" (view "new") 0 in
  Alcotest.(check bool) "unknown commit requests restart" true
    (match status with Lui_hot_reload.ReloadRestartRequired (_, "host commit uncertain") -> true | _ -> false);
  let state = Option.get app.Lui_app.app_reload_state in
  Alcotest.(check bool) "current scope is live" false (Signal.scope_is_disposed !(state.reload_view_scope));
  throwing := false;
  let request = Lui_app.request_reload app in
  let status = Lui_app.reload_view app request "old" "contract" (view "old") 0 in
  Alcotest.(check bool) "uncertain session cannot silently continue" true
    (match status with Lui_hot_reload.ReloadRestartRequired _ -> true | _ -> false)

let reload_cleanup_failure () =
  let app = reload_app (fun _ -> true) in
  let state = Option.get app.Lui_app.app_reload_state in
  let old = !(state.reload_view_scope) in
  Signal.on_unmount old (fun () -> failwith "cleanup failed");
  let request = Lui_app.request_reload app in
  let status = Lui_app.reload_view app request "new" "contract" (view "new") 0 in
  Alcotest.(check bool) "cleanup failure requires restart" true
    (match status with Lui_hot_reload.ReloadRestartRequired _ -> true | _ -> false);
  Alcotest.(check bool) "committed scope replaces old reference" false (!(state.reload_view_scope) == old);
  Alcotest.(check bool) "committed scope remains active" true (Signal.active !(state.reload_view_scope))

let allocated f =
  Gc.full_major ();
  let words () = Gc.allocated_bytes () /. 8. in
  let before = words () in f (); words () -. before

let keyed_scaling () =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "keyed") in
  let parent = Lui_ui.virtual_list context in
  let source = Signal.state context.ui_scheduler (List.init 1000 Fun.id) in
  let comparisons = ref 0 in
  let compare a b = incr comparisons; Int.compare a b in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id compare
    (fun row item -> Lui_ui.text row (string_of_int (Signal.sample item))));
  Alcotest.(check bool) "keyed lookup is subquadratic" true (!comparisons < 100_000);
  let ids = Lui_runtime.children app parent in
  Signal.set source (List.rev (Signal.get_state source)); ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "reverse retains identity" (List.rev ids) (Lui_runtime.children app parent)

let child_scaling () =
  let mount n =
    let app = runtime () in
    let parent = Lui_runtime.create_node app VirtualList in
    allocated (fun () -> for index = 0 to n - 1 do
      let node = Lui_runtime.create_node app Text in
      Lui_runtime.insert_child app parent node index
    done) in
  let small = mount 500 and large = mount 2000 in
  Alcotest.(check bool) "flat tree allocation grows subquadratically" true (large < small *. 7.)

let switch_scaling () =
  let update n =
    let app = runtime () in
    let context = Lui_ui.context app (Signal.scope "switch") in
    let parent = Lui_ui.column context in
    for _ = 1 to n do ignore (Lui_ui.text context "retained") done;
    let source = Signal.state context.ui_scheduler 0 in
    ignore (Lui_dynamic.switch context parent (Signal.value source) Int.equal
      (fun row key -> Lui_ui.text row (string_of_int key)));
    ignore (Lui_runtime.flush app);
    allocated (fun () -> Signal.set source 1; ignore (Lui_runtime.flush app)) in
  let small = update 1000 and large = update 5000 in
  Alcotest.(check bool) "local update ignores unrelated nodes" true (large < small *. 2.)

let switch_parent_and_rollback () =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "nested") in
  let root = Lui_ui.column context and parent = Lui_ui.column context in
  Lui_runtime.insert_child app root parent 0;
  let sibling = Lui_ui.text context "sibling" in
  Lui_runtime.insert_child app root sibling 1;
  let state = Signal.state context.ui_scheduler 0 in
  let fail = ref false in
  let branch = Lui_dynamic.switch context parent (Signal.value state) Int.equal
    (fun row value ->
      if !fail then Signal.on_mount row.Lui_ui.ui_scope (fun () -> failwith "mount rejected");
      Lui_ui.text row (string_of_int value)) in
  ignore (Lui_runtime.flush app);
  Signal.set state 1; ignore (Lui_runtime.flush app);
  Alcotest.(check (option int)) "nested parent retains owner" (Some root)
    (Lui_runtime.recorded_parent app parent);
  let old_node = Lui_dynamic.switch_node branch in
  fail := true; Signal.set state 2;
  check_failure "failed candidate rejected" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check (list int)) "old subtree restored" [old_node] (Lui_runtime.children app parent);
  Alcotest.(check (list int)) "unrelated siblings preserved" [parent; sibling] (Lui_runtime.children app root)

let keyed_outer_drop () =
  let app = runtime () in
  let scope = Signal.scope "outer" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler [1; 2] in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row key -> Lui_ui.text row (string_of_int (Signal.sample key))));
  Lui_runtime.drop_subtree app parent;
  Signal.dispose_scope scope;
  Alcotest.(check int) "all segments disposed" 0 (Lui_runtime.dynamic_segment_count app)

let sequence_ordering () =
  let random = Random.State.make [|17|] in
  let values = ref [] and sequence = ref Lui_sequence.empty in
  for step = 0 to 2000 do
    let saved = !sequence and previous = !values in
    let length = List.length !values in
    if length = 0 || Random.State.bool random then begin
      let index = Random.State.int random (length + 1) in
      sequence := Lui_sequence.insert !sequence index step;
      values := List.filteri (fun i _ -> i < index) !values @ [step]
        @ List.filteri (fun i _ -> i >= index) !values
    end else begin
      let index = Random.State.int random length in
      Alcotest.(check int) "indexed value" (List.nth !values index) (Lui_sequence.get !sequence index);
      sequence := Lui_sequence.remove !sequence index;
      values := List.filteri (fun i _ -> i <> index) !values
    end;
    Alcotest.(check (list int)) "snapshot is persistent" previous (Lui_sequence.to_list saved);
    Alcotest.(check (list int)) "indexed sequence agrees with list" !values (Lui_sequence.to_list !sequence)
  done

let anchorless_restricted_ranges () =
  let app, scope, context, emitted = boundary_fixture () in
  let items = Signal.state context.ui_scheduler [1; 2] in
  let parts = Signal.state context.ui_scheduler ["a"; "b"] in
  let visible = Signal.state context.ui_scheduler true in
  let open Lui_elements in
  let parent = toolbar ~label:"Actions"
    [ toolbar_text ~value:"before" [];
      keyed_toolbar ~source:(Signal.value items) ~key:Fun.id ~cmp:Int.compare
        ~mount:(fun item ->
          if_toolbar ~test:(Signal.value visible)
            (keyed_toolbar ~source:(Signal.value parts) ~key:Fun.id ~cmp:String.compare
              ~mount:(fun part -> toolbar_button
                ~text:(string_of_int (Signal.sample item) ^ Signal.sample part)
                ~on_press:(fun () -> ()) [])));
      toolbar_text ~value:"after" [] ] context None in
  Signal.mount scope;
  let flush expected =
    ignore (Lui_runtime.flush app);
    Alcotest.(check bool) "no dynamic anchor nodes" false
      (List.exists (function CreateNode (_, Box) -> true | _ -> false) !emitted);
    let labels = List.map (fun node ->
      match Property_map.find_opt TextValue (Hashtbl.find app.runtime_properties node) with
      | Some (StringValue text) -> text | _ -> "") (Lui_runtime.children app parent) in
    Alcotest.(check (list string)) "slot order" ("before" :: expected @ ["after"]) labels in
  flush ["1a"; "1b"; "2a"; "2b"];
  Signal.set visible false;
  flush [];
  Alcotest.(check bool) "toggle removes ranges" true
    (List.exists (function RemoveChild _ -> true | _ -> false) !emitted);
  Signal.set items [2; 1; 3];
  flush [];
  Signal.set visible true;
  flush ["2a"; "2b"; "1a"; "1b"; "3a"; "3b"];
  let retained = List.sort Int.compare (Lui_runtime.children app parent) in
  Signal.set items [1; 3; 2];
  flush ["1a"; "1b"; "3a"; "3b"; "2a"; "2b"];
  Alcotest.(check (list int)) "reorder preserves ids" retained
    (List.sort Int.compare (Lui_runtime.children app parent));
  Alcotest.(check bool) "reorder emits move operations" true
    (List.exists (function MoveChild _ -> true | _ -> false) !emitted);
  Signal.set parts ["b"];
  flush ["1b"; "3b"; "2b"];
  Signal.set items [];
  flush [];
  Signal.set parts [];
  Signal.set items [9];
  flush [];
  Signal.set parts ["z"];
  flush ["9z"];
  Lui_runtime.drop_subtree app parent;
  Signal.dispose_scope scope;
  Alcotest.(check int) "ranges released on outer drop" 0 (Lui_runtime.dynamic_segment_count app)

let anchorless_boundary_rollback () =
  let app, scope, context, emitted = boundary_fixture () in
  let source = Signal.state context.ui_scheduler 0 in
  let rows = Signal.state context.ui_scheduler [1; 2] in
  let visible = Signal.state context.ui_scheduler true in
  let failures = ref 0 in
  let open Lui_elements in
  let child = toolbar ~label:"Recoverable"
    [reactive_toolbar (fun value ->
      scoped_toolbar (fun row ->
        if value = 2 then Signal.on_mount row.Lui_ui.ui_scope
          (fun () -> failwith "range mount rejected");
        if_toolbar ~test:(Signal.value visible)
          (keyed_toolbar ~source:(Signal.value rows) ~key:Fun.id ~cmp:Int.compare
            ~mount:(fun item -> toolbar_button
              ~text:(if value = 2 then "partial" else string_of_int (value + Signal.sample item))
              ~on_press:(fun () -> ()) [])))) (Signal.value source)] in
  ignore (error_boundary ~fallback:(fun diagnostic ->
    incr failures;
    Alcotest.(check bool) "update failure" true (diagnostic.phase = `Update);
    text ~value:"recovered" []) child context None);
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  Signal.set source 1;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "multi-root switch updates" ["2"; "3"]
    (List.sort String.compare (text_values app));
  Signal.set source 2;
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list string)) "failed range rolls back before fallback" ["recovered"] (text_values app);
  Alcotest.(check bool) "partial writes discarded" false
    (List.exists (function SetProp (_, TextValue, StringValue "partial") -> true | _ -> false) !emitted);
  Alcotest.(check int) "all failed ranges released" 0 (Lui_runtime.dynamic_segment_count app);
  Alcotest.(check int) "all failed handlers released" 0 !(app.runtime_handler_count);
  Signal.set source 3;
  Signal.set rows [3];
  Signal.set visible false;
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "fallback latched" 1 !failures;
  Signal.dispose_scope scope

let anchorless_registration_allocation () =
  let measure count =
    let _app, scope, context, _ = boundary_fixture () in
    let parent = Lui_ui.column context in
    let items = Signal.constant context.ui_scheduler (List.init count Fun.id) in
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    Lui_dynamic.keyed_range context parent items Fun.id Int.compare (fun _ _ -> ());
    let allocated = Gc.allocated_bytes () -. before in
    Signal.dispose_scope scope;
    allocated in
  let small = measure 500 and large = measure 2000 in
  Alcotest.(check bool) "keyed range registration allocation scales linearly" true (large < small *. 6.)

let anchorless_static_sibling () =
  let app, scope, context, _ = boundary_fixture () in
  let parent = Lui_ui.column context in
  let visible = Signal.state context.ui_scheduler true in
  let revision = Signal.state context.ui_scheduler 0 in
  let text context value = ignore (Lui_elements.text ~value [] context (Some parent)) in
  text context "prefix";
  Lui_dynamic.switch_range context parent (Signal.value revision) Int.equal
    (fun branch _ ->
      text branch "before";
      Lui_dynamic.conditional_range branch parent (Signal.value visible)
        (fun nested -> text nested "dynamic");
      text branch "after");
  text context "suffix";
  Signal.mount scope;
  let check expected =
    ignore (Lui_runtime.flush app);
    let values = List.map (fun node -> match Property_map.find_opt TextValue
      (Hashtbl.find app.runtime_properties node) with
      | Some (StringValue value) -> value | _ -> "") (Lui_runtime.children app parent) in
    Alcotest.(check (list string)) "nested toggle preserves static siblings" expected values in
  check ["prefix"; "before"; "dynamic"; "after"; "suffix"];
  Signal.set visible false;
  check ["prefix"; "before"; "after"; "suffix"];
  Signal.set visible true;
  check ["prefix"; "before"; "dynamic"; "after"; "suffix"];
  Signal.set revision 1;
  check ["prefix"; "before"; "dynamic"; "after"; "suffix"];
  Signal.set visible false;
  check ["prefix"; "before"; "after"; "suffix"];
  Signal.dispose_scope scope;
  Alcotest.(check int) "all ranges released" 0 (Lui_runtime.dynamic_segment_count app)

let anchorless_virtual_replacement () =
  let backend = { backend_profile = profile IOS SwiftUIHost; apply_batch = (fun _ -> true) } in
  let app = Lui_runtime.create ~virtual_capabilities:[Lui_virtual.Shared_viewport_retention_v1]
    (Signal.scheduler ()) backend in
  let scope = Signal.scope "range-virtual" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let revision = Signal.state context.ui_scheduler 0 in
  let items = Signal.constant context.ui_scheduler ["row"] in
  let owner = Lui_virtual.create_owner () in
  let source = Lui_virtual.root_source owner ~key:"rows" in
  Lui_dynamic.switch_range context parent (Signal.value revision) Int.equal
    (fun branch value ->
      if value = 2 then Signal.on_mount branch.Lui_ui.ui_scope (fun () -> failwith "reject virtual range");
      let open Lui_elements in
      ignore (scroll ~virtual_owner:owner
        [virtual_list ~viewport:source [virtual_rows ~source:items ~key:Fun.id ~cmp:String.compare
          ~scroll_key:Fun.id ~mount:(fun item -> text ~value:(Signal.sample item) []) ()]]
        branch (Some parent)));
  Signal.mount scope;
  ignore (Lui_runtime.flush app);
  let binding () = Option.get (Signal.sample (Lui_virtual.binding source)) in
  let first = binding () in
  Signal.set revision 1;
  ignore (Lui_runtime.flush app);
  let second = binding () in
  Alcotest.(check int) "virtual node reconciled" first.node second.node;
  Alcotest.(check bool) "replacement receives a fresh lease" true (first.lease <> second.lease);
  Signal.set revision 2;
  check_failure "candidate mount is rejected" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check int) "rollback restores the live lease" second.lease (binding ()).lease;
  Signal.set revision 3;
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "replacement still works after rollback" true ((binding ()).lease <> second.lease);
  Signal.dispose_scope scope;
  Alcotest.(check bool) "unmount releases the borrowed source binding" true
    (Signal.sample (Lui_virtual.binding source) = None);
  Lui_virtual.dispose_owner owner

let anchorless_state_lifetime () =
  let app = runtime () in
  let scope = Signal.scope "range-states" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let items = Signal.state context.ui_scheduler [1; 2] in
  let revision = Signal.state context.ui_scheduler 0 in
  let slot = Signal.state_slot "draft" in
  let states = Hashtbl.create 2 in
  Lui_dynamic.keyed_range context parent (Signal.value items) Fun.id Int.compare
    (fun row item ->
      let key = Signal.sample item in
      Lui_dynamic.switch_range row parent (Signal.value revision) Int.equal
        (fun branch _ ->
          let state = Signal.state_at branch.Lui_ui.ui_scheduler branch.ui_state_scope slot key in
          Hashtbl.replace states key (state, branch.ui_state_scope);
          Lui_ui.append branch parent (Lui_ui.text branch (string_of_int (Signal.get_state state)))));
  let first, _ = Hashtbl.find states 1 in
  let second, second_scope = Hashtbl.find states 2 in
  Signal.set first 99;
  Signal.set revision 1;
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "branch retains state on remount" true (fst (Hashtbl.find states 1) == first);
  Signal.set items [2; 1];
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "reordered row retains draft" 99 (Signal.get_state first);
  Signal.set items [1];
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "removed row state disposed" true (Signal.scope_is_disposed second_scope);
  Signal.set items [1; 2];
  ignore (Lui_runtime.flush app);
  let fresh, _ = Hashtbl.find states 2 in
  Alcotest.(check bool) "reinsertion gets fresh state" false (fresh == second);
  Signal.set items [];
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "empty range removes all nodes" [] (Lui_runtime.children app parent);
  Signal.dispose_scope scope;
  Alcotest.(check int) "all state ranges released" 0 (Lui_runtime.dynamic_segment_count app)

let existing_tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f)
  ["anchorless restricted ranges", anchorless_restricted_ranges;
   "anchorless boundary rollback", anchorless_boundary_rollback;
   "anchorless registration allocation", anchorless_registration_allocation;
   "anchorless static sibling", anchorless_static_sibling;
   "anchorless virtual replacement", anchorless_virtual_replacement;
   "anchorless state lifetime", anchorless_state_lifetime;
   "keyed state isolation and lifetime", keyed_states;
   "boundary initial mount rollback", boundary_initial_mount;
   "boundary shared publication work", boundary_shared_publication_work;
   "boundary publication rollback", boundary_publication_rollback;
   "boundary interleaved committed fallbacks", boundary_interleaved_fallbacks;
   "boundary sibling mount work", boundary_sibling_mount_work;
   "boundary committed outer recovery", boundary_committed_outer_recovery;
   "boundary journal savepoints", boundary_journal_savepoints;
   "boundary journal compaction", boundary_journal_compaction;
   "boundary nested mount rollback", boundary_nested_mount_rollback;
   "boundary echo rollback", boundary_echo_rollback;
   "boundary host detach descendants", boundary_host_detach_descendants;
   "boundary host detach unlink", boundary_host_detach_unlink;
   "boundary host tweak order", boundary_host_tweak_order;
   "boundary resync selection", boundary_resync_selection;
   "boundary resync sizes", boundary_resync_sizes;
   "boundary reactive failure and latched fallback", boundary_reactive_update;
   "nested boundaries and fallback failures", boundary_nested;
   "boundary owned property projection", boundary_property_projection;
   "boundary reactive attribute encoding", boundary_reactive_attributes;
   "boundary retained keyed and virtual rows", boundary_retained_rows;
   "closure-bearing subtree publications", closure_subtree_publication;
   "numeric normalization and runtime emission", numeric_normalization;
   "duplicate keyed publications", duplicate_keyed_publication;
   "rejected batch authoritative recovery", rejected_batch_resync;
   "extension validation retries", extension_retry;
   "backend exceptions and reentrant writes", backend_failure;
   "subscription startup cleanup", subscription_failure;
   "resync ordinary application and subsequent deltas", resync_default_app;
   "resync root and detached extension trees", resync_detached_nodes;
   "reload mount rollback", reload_mount_failure;
   "reload uncertain commit", reload_commit_failure;
   "reload postcommit cleanup failure", reload_cleanup_failure;
   "keyed scaling and reversal", keyed_scaling;
   "flat child scaling", child_scaling;
   "local switch scaling", switch_scaling;
   "nested switch ownership and rollback", switch_parent_and_rollback;
   "keyed cleanup after outer drop", keyed_outer_drop;
   "persistent sequence ordering", sequence_ordering]


let review_sibling_state () =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "siblings") in
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler 0 in
  let slot = Signal.state_slot "draft" in
  let states = ref [] in
  let mount initial row _ =
    let state = Signal.state_at row.Lui_ui.ui_scheduler row.ui_state_scope slot initial in
    states := state :: !states;
    Lui_ui.text row (string_of_int (Signal.get_state state)) in
  ignore (Lui_dynamic.switch context parent (Signal.value source) Int.equal (mount 10));
  ignore (Lui_dynamic.switch context parent (Signal.value source) Int.equal (mount 20));
  let second, first = match !states with [second; first] -> second, first | _ -> assert false in
  Alcotest.(check int) "second owner initializes independently" 20 (Signal.get_state second);
  Signal.set first 99;
  Alcotest.(check int) "sibling draft remains independent" 20 (Signal.get_state second);
  Signal.set source 1; ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "both owners retain their drafts on remount" [20; 99]
    (List.map Signal.get_state (List.filteri (fun index _ -> index < 2) !states))

let review_keyed_candidate_failure hook_failure =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "candidate-owner") in
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler [1] in
  let scopes = ref [] in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item ->
      let key = Signal.sample item in
      if key > 1 then scopes := row.Lui_ui.ui_scope :: !scopes;
      let node = Lui_ui.text row (string_of_int key) in
      if key = 3 then begin
        if hook_failure then Signal.on_mount row.ui_scope (fun () -> failwith "candidate failed")
        else failwith "candidate failed"
      end;
      node));
  ignore (Lui_runtime.flush app);
  let old = Lui_runtime.children app parent in
  Signal.set source [1; 2; 3];
  check_failure "candidate rejected" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check int) "unpublished nodes removed" 2 (Lui_runtime.mounted_count app);
  Alcotest.(check (list int)) "published rows retained" old (Lui_runtime.children app parent);
  List.iter (fun scope -> Alcotest.(check bool) "candidate scope disposed" true
    (Signal.scope_is_disposed scope)) !scopes;
  Signal.set source [1; 4]; ignore (Lui_runtime.flush app);
  Alcotest.(check int) "later publication succeeds without leaked nodes" 3 (Lui_runtime.mounted_count app)

let review_keyed_cleanup_failure () =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "cleanup-owner") in
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler [1] in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item ->
      if Signal.sample item = 1 then Signal.on_dispose row.Lui_ui.ui_scope (fun () -> failwith "retirement failed");
      Lui_ui.text row "row"));
  ignore (Lui_runtime.flush app);
  Signal.set source [];
  check_failure "cleanup error reported" (attempt (fun () -> ignore (Lui_runtime.flush app)));
  Alcotest.(check (list int)) "committed removal remains committed" [] (Lui_runtime.children app parent);
  Signal.set source [2]; ignore (Lui_runtime.flush app);
  Alcotest.(check int) "next publication works" 1 (Lui_runtime.child_count app parent)

let review_segment_checkpoint () =
  let app = runtime () in
  let parent = Lui_runtime.create_node app Column in
  let segment = Lui_runtime.register_dynamic_segment app parent in
  Lui_runtime.resize_dynamic_segment app segment 1;
  let saved = Lui_runtime.checkpoint app in
  Lui_runtime.release_dynamic_segment app segment;
  Lui_runtime.restore app saved;
  Alcotest.(check int) "segment size restored independently" 1
    !(segment.Lui_runtime.dynamic_segment_size)

let review_library_derived_ownership () =
  let app = runtime () in
  let owner = Signal.scope "derived-owner" in
  let context = Lui_ui.context app owner in
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler ["accent", Lui_ui.Fixed "blue"] in
  let branch = Signal.state context.ui_scheduler 0 in
  ignore (Lui_dynamic.switch context parent (Signal.value branch) Int.equal
    (fun row _ ->
      let node = Lui_ui.column row in
      Lui_ui.theme_signal row node (Signal.value source);
      node));
  ignore (Lui_runtime.flush app);
  for index = 1 to 20 do Signal.set branch index; ignore (Lui_runtime.flush app) done;
  Signal.set source ["accent", Lui_ui.Fixed "green"];
  Signal.stabilize context.ui_scheduler;
  Alcotest.(check int) "property conversion does not add reactive computations" 1
    (Signal.last_stabilization context.ui_scheduler).stabilization_dirty_tasks;
  Signal.dispose_scope owner;
  Signal.set source ["accent", Lui_ui.Fixed "red"];
  Signal.stabilize context.ui_scheduler;
  Alcotest.(check int) "owner releases all derivations" 1
    (Signal.last_stabilization context.ui_scheduler).stabilization_dirty_tasks;
  Alcotest.(check bool) "borrowed source remains usable" true
    (Signal.get_state source = ["accent", Lui_ui.Fixed "red"])

let review_retired_event () =
  let app = runtime () in
  let scope = Signal.scope "old-handler" in
  let node = Lui_runtime.create_node app Button in
  Lui_runtime.set_prop app node TextValue (StringValue "press");
  let calls = ref 0 in
  Lui_runtime.on_event scope app node (fun _ -> incr calls);
  ignore (Lui_runtime.dispatch app (Press node));
  Signal.dispose_scope scope;
  let replacement_scope = Signal.scope "new-handler" in
  Lui_runtime.on_event replacement_scope app node (fun _ -> calls := !calls + 10);
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "retired registration cannot receive a queued event" 0 !calls;
  ignore (Lui_runtime.dispatch app (Press node)); ignore (Lui_runtime.flush app);
  Alcotest.(check int) "new event reaches current handler" 10 !calls

let review_subscription_retirement () =
  let coordinator = Lui_subscriptions.create () in
  let cancelled = ref [] in
  let spec version fail = {Lui_subscriptions.subscription_key = "one";
    subscription_fingerprint = version; start_subscription = (fun () ->
      Signal.make_subscription (fun () ->
        cancelled := version :: !cancelled;
        if fail then failwith "retirement failed"))} in
  ignore (Lui_subscriptions.reconcile coordinator 1 [spec "old" true]);
  check_failure "retirement error reported" (attempt (fun () ->
    ignore (Lui_subscriptions.reconcile coordinator 2 [spec "new" false])));
  Lui_subscriptions.dispose coordinator;
  Alcotest.(check (list string)) "replacement remains owned and cancellable" ["new"; "old"] !cancelled

let review_keyed_locality () =
  let update unrelated =
    let app = runtime () in
    let context = Lui_ui.context app (Signal.scope "local-keyed") in
    for _ = 1 to unrelated do ignore (Lui_ui.text context "unrelated") done;
    let parent = Lui_ui.column context in
    let source = Signal.state context.ui_scheduler [1; 2] in
    ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
      (fun row item -> Lui_ui.text row (string_of_int (Signal.sample item))));
    ignore (Lui_runtime.flush app);
    allocated (fun () ->
      Signal.set source [2; 1; 3]; ignore (Lui_runtime.flush app)) in
  let small = update 1000 and large = update 10000 in
  Alcotest.(check bool) "keyed update does not copy unrelated application nodes" true (large < small *. 3.)

let review_keyed_unchanged () =
  let app = runtime () in
  let context = Lui_ui.context app (Signal.scope "unchanged-keyed") in
  for _ = 1 to 1000 do ignore (Lui_ui.text context "unrelated") done;
  let parent = Lui_ui.column context in
  let source = Signal.state context.ui_scheduler [1] in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item -> Lui_ui.text row (string_of_int (Signal.sample item))));
  ignore (Lui_runtime.flush app);
  let bytes = allocated (fun () -> Signal.set source [1]; ignore (Lui_runtime.flush app)) in
  Alcotest.(check bool) "unchanged publication has bounded bookkeeping" true (bytes < 2048.)

let keyed_retained_subtree_allocation () =
  let app = runtime () in
  let scope = Signal.scope "retained-keyed-subtrees" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let initial = List.init 128 Fun.id in
  let source = Signal.state context.ui_scheduler initial in
  let mounts = ref 0 in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item ->
      incr mounts;
      let root = Lui_ui.column row in
      for _ = 1 to 32 do
        Lui_ui.append row root (Lui_ui.text row (string_of_int (Signal.sample item)))
      done;
      root));
  ignore (Lui_runtime.flush app);
  let original = Lui_runtime.children app parent in
  List.iter (fun (label,items,expected_mounts) ->
    let before = Gc.allocated_bytes () in
    Signal.set source items;
    ignore (Lui_runtime.flush app);
    let bytes = Gc.allocated_bytes () -. before in
    Printf.printf "keyed %s over retained subtrees allocated %.0f bytes\n%!" label bytes;
    Alcotest.(check bool) "keyed mutation does not snapshot retained row subtrees" true
      (bytes <= 524288.);
    Alcotest.(check int) "retained rows do not remount" expected_mounts !mounts
  ) ["append",initial @ [128],129; "reorder",128 :: List.rev initial,129];
  Alcotest.(check (list int)) "reorder retains original row identities"
    (List.rev original) (List.tl (Lui_runtime.children app parent));
  Signal.dispose_scope scope

let keyed_removed_subtree_rollback () =
  let app = runtime () in
  let scope = Signal.scope "removed-keyed-subtrees" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.table context in
  let source = Signal.state context.ui_scheduler [1;2] in
  let buttons = Hashtbl.create 4 in
  let clicks = ref 0 and disposed = ref [] in
  let mount row item =
    let key = Signal.sample item in
    if key=3 then Lui_ui.text row "invalid table child"
    else begin
      Signal.on_dispose row.Lui_ui.ui_scope (fun () -> disposed := key :: !disposed);
      let root = Lui_ui.table_row row in
      let cell = Lui_ui.table_cell row in
      Lui_ui.append row root cell;
      let button = Lui_ui.button row in
      Lui_runtime.on_event row.Lui_ui.ui_scope app button (fun _ -> incr clicks);
      Lui_ui.append row cell button;
      Hashtbl.replace buttons key button;
      root
    end in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare mount);
  let following = Signal.state context.ui_scheduler [100] in
  ignore (Lui_dynamic.keyed context parent (Signal.value following) Fun.id Int.compare mount);
  ignore (Lui_runtime.flush app);
  let original = Lui_runtime.resync_batch app in
  Signal.set source [2;3];
  check_failure "insertion after removal rejects invalid child" (attempt (fun () ->
    ignore (Lui_runtime.flush app)));
  Alcotest.(check bool) "rollback restores removed subtree and following segment" true
    (Lui_runtime.resync_batch app = original);
  Alcotest.(check (list int)) "rollback keeps removed row scope alive" [] !disposed;
  ignore (Lui_runtime.dispatch app (Press (Hashtbl.find buttons 1)));
  ignore (Lui_runtime.flush app);
  Alcotest.(check int) "restored descendant handler still receives input" 1 !clicks;
  Signal.set source [2;4];
  ignore (Lui_runtime.flush app);
  Alcotest.(check (list int)) "successful replacement disposes removed owner once" [1] !disposed;
  Alcotest.(check int) "following collection retains its row" 3 (Lui_runtime.child_count app parent);
  Signal.dispose_scope scope

let review_wide_reorder () =
  let measure count =
    let app = runtime () in
    let parent = Lui_runtime.create_node app VirtualList in
    let old = List.init count (fun index -> index + 2) in
    let desired = List.rev old in
    let reparented = Hashtbl.create 0 in
    let before = Sys.time () in
    Lui_runtime.emit_child_diff app reparented parent old desired;
    let elapsed = Sys.time () -. before in
    let moves = List.length (List.filter (function MoveChild _ -> true | _ -> false) !(app.Lui_runtime.pending_ops)) in
    Alcotest.(check int) "reversal emits the required moves" (count - 1) moves;
    elapsed in
  ignore (measure 500);
  let small = measure 4000 and large = measure 16000 in
  Alcotest.(check bool) "wide reconciliation scales subquadratically" true
    (large < small *. 9. +. 0.03)

let property_binding_retention () =
  let retained dynamic =
    Gc.full_major ();
    let before = (Gc.stat ()).Gc.live_words * 8 in
    let app = runtime () in
    let scope = Signal.scope "property-retention" in
    let context = Lui_ui.context app scope in
    let source = Signal.state context.ui_scheduler "initial" in
    for _ = 1 to 2000 do
      if dynamic then ignore (Lui_ui.text_signal context (Signal.value source))
      else ignore (Lui_ui.text context "initial")
    done;
    ignore (Lui_runtime.flush app);
    Gc.full_major ();
    let bytes = (Gc.stat ()).Gc.live_words * 8 - before in
    ignore (Sys.opaque_identity (app, context, source));
    Signal.dispose_scope scope;
    bytes in
  let plain = retained false in
  let bound = retained true in
  let per_binding = float (bound - plain) /. 2000. in
  Printf.printf "Reactive property retained overhead: %.0f bytes/binding\n%!" per_binding;
  if per_binding > 768. then
    Alcotest.failf "A scalar property binding retains %.0f extra bytes" per_binding

let property_value app node property =
  Property_map.find property (Hashtbl.find app.Lui_runtime.runtime_properties node)

let property_binding_values () =
  let batches = ref [] in
  let app = Lui_runtime.create (Signal.scheduler ())
    (backend (fun batch -> batches := batch :: !batches; true)) in
  let scope = Signal.scope "typed-property-values" in
  let context = Lui_ui.context app scope in
  let text = Signal.state context.ui_scheduler "initial" in
  let enabled = Signal.state context.ui_scheduler true in
  let number = Signal.state context.ui_scheduler 0.25 in
  let level = Signal.state context.ui_scheduler 1 in
  let mode = Signal.state context.ui_scheduler `light in
  let tokens = Signal.state context.ui_scheduler ["accent", Lui_ui.Fixed "blue"] in
  let texts = [Lui_ui.text_signal context (Signal.value text);
    Lui_ui.heading_signal context 2 (Signal.value text);
    Lui_ui.paragraph_signal context (Signal.value text);
    Lui_ui.label_signal context (Signal.value text)] in
  let button = Lui_ui.button context and disabled = Lui_ui.button context in
  Lui_ui.bool_property_signal context button Enabled (Signal.value enabled);
  Lui_ui.disabled_signal context disabled (Signal.value enabled);
  let panel = Lui_ui.column context in
  Lui_ui.float_property_signal context panel Opacity (Signal.value number);
  Lui_ui.theme_mode_signal context panel (Signal.value mode);
  Lui_ui.theme_signal context panel (Signal.value tokens);
  let heading = Lui_ui.heading context 1 "heading" in
  Lui_ui.int_property_signal context heading HeadingLevel (Signal.value level);
  let slider = Lui_ui.slider context (Signal.value number) in
  ignore (Lui_runtime.flush app);
  List.iter (fun id -> Alcotest.(check bool) "initial text is delivered" true
    (property_value app id TextValue = StringValue "initial")) texts;
  Alcotest.(check bool) "initial disabled conversion" true
    (property_value app disabled Enabled = BoolValue false);
  batches := [];
  Signal.set text "intermediate";
  Signal.set text "final";
  Signal.set enabled false;
  Signal.set number 0.75;
  Signal.set level 3;
  Signal.set mode `dark;
  Signal.set tokens ["accent", Lui_ui.Fixed "green"];
  ignore (Lui_runtime.flush app);
  List.iter (fun id ->
    Alcotest.(check bool) "latest text is delivered" true
      (property_value app id TextValue = StringValue "final");
    let updates = List.concat_map (fun (batch:patch_batch) -> batch.ops) !batches
      |> List.filter (function SetProp (node, TextValue, _) -> node=id | _ -> false) in
    Alcotest.(check int) "a batched property emits one final update" 1 (List.length updates)) texts;
  List.iter (fun (node,property,value) ->
    Alcotest.(check bool) "typed property updates" true (property_value app node property = value))
    [button,Enabled,BoolValue false; disabled,Enabled,BoolValue true;
     panel,Opacity,FloatValue 0.75; heading,HeadingLevel,IntValue 3;
     slider,ProgressValue,FloatValue 0.75; panel,ThemeMode,StringValue "dark";
     panel,ThemeValue,StringValue (Lui_ui.theme_tokens_json ["accent", Lui_ui.Fixed "green"])];
  Signal.dispose_scope scope

let property_binding_borrowed_source () =
  let app = runtime () in
  let first = Signal.scope "first-property-reader" and second = Signal.scope "second-property-reader" in
  let a = Lui_ui.context app first and b = Lui_ui.context app second in
  let source = Signal.state a.ui_scheduler "initial" in
  let left = Lui_ui.text_signal a (Signal.value source) in
  let right = Lui_ui.text_signal b (Signal.value source) in
  ignore (Lui_runtime.flush app);
  Signal.dispose_scope first;
  Signal.set source "updated";
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "disposed binding stops writing" true
    (property_value app left TextValue = StringValue "initial");
  Alcotest.(check bool) "shared source still updates its other reader" true
    (property_value app right TextValue = StringValue "updated");
  Signal.dispose_scope second;
  Signal.set source "after disposal";
  Signal.stabilize a.ui_scheduler;
  Alcotest.(check int) "disposed bindings retain no computations" 1
    (Signal.last_stabilization a.ui_scheduler).stabilization_dirty_tasks;
  Alcotest.(check bool) "the source is borrowed" false (Signal.signal_is_disposed (Signal.value source))

let property_binding_diamond () =
  let updates = ref [] in
  let app = Lui_runtime.create (Signal.scheduler ()) (backend (fun batch ->
    updates := List.rev_append batch.ops !updates; true)) in
  let caller = Signal.scope "property-source-owner" and scope = Signal.scope "property-diamond" in
  let context = Lui_ui.context app scope in
  let left = Signal.state context.ui_scheduler "a" and right = Signal.state context.ui_scheduler "b" in
  let joined = Signal.own_signal caller (Signal.map2 ( ^ ) (Signal.value left) (Signal.value right)) in
  let node = Lui_ui.text_signal context joined in
  ignore (Lui_runtime.flush app);
  updates := [];
  Signal.set left "A"; Signal.set right "B";
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "a derived source publishes the settled value" true
    (property_value app node TextValue = StringValue "AB");
  let texts = List.filter_map (function SetProp (id,TextValue,StringValue text) when id=node -> Some text
    | _ -> None) !updates in
  Alcotest.(check (list string)) "a diamond emits no intermediate property values" ["AB"] (List.rev texts);
  Signal.dispose_scope scope;
  Alcotest.(check bool) "the derived source belongs to its caller" false (Signal.signal_is_disposed joined);
  Signal.dispose_scope caller

let property_binding_queued_disposal () =
  List.iter (fun drop ->
    let app = runtime () in
    let scope = Signal.scope "queued-property-reader" in
    let context = Lui_ui.context app scope in
    let source = Signal.state context.ui_scheduler "initial" in
    let node = Lui_ui.text context "initial" in
    let retiring = Signal.subscribe ~emit_initial:false (Signal.value source) (fun _ ->
      if drop then Lui_runtime.drop_node app node else Signal.dispose_scope scope) in
    Lui_ui.string_property_signal context node TextValue (Signal.value source);
    ignore (Lui_runtime.flush app);
    Signal.set source "queued";
    ignore (Lui_runtime.flush app);
    if drop then Alcotest.(check bool) "retired node is not revived" false (Lui_runtime.node_live app node)
    else Alcotest.(check bool) "retired scope discards its queued write" true
      (property_value app node TextValue = StringValue "initial");
    Signal.dispose_subscription retiring;
    Signal.dispose_scope scope) [false;true]

let phase4_rows_are_not_disclosures () =
  List.iter (fun build ->
    List.iter (fun row ->
      let app, scope, context, _ = boundary_fixture () in
      let root = build row context None in
      let rec check node =
        let children = Lui_runtime.children app node in
        if Lui_runtime.require_standard_node_kind app node = ListItem then
          Alcotest.(check bool) "content rows do not become collapsed disclosures" false
            (List.exists (fun child ->
              Lui_runtime.require_standard_node_kind app child = ListItem) children);
        List.iter check children
      in
      check root;
      Signal.dispose_scope scope)
      [Lui_element_combine.settings_row ~label:"Setting" ();
       Lui_elements.list_item ~text:"Item" []])
    [(fun row -> Lui.Ui.form_section [row]);
     (fun row -> Lui.Ui.data_list ~label:"Rows" [row])]

let phase4_form_sheet_sections () =
  let app, scope, context, _ = boundary_fixture () in
  let sheet = Lui.Ui.form_sheet ~title:"Edit"
    [Lui.Ui.form_section ~title:"Identity" ~footer:"Required"
       [Lui.Ui.form_field ~label:"Name" (Lui_elements.text_field []);
        Lui_elements.toggle ~text:"Enabled" []];
     Lui.Ui.form_section ~title:"Other" [Lui_elements.text_field []]]
    context None in
  let form = List.hd (Lui_runtime.children app sheet) in
  let list = List.hd (Lui_runtime.children app form) in
  Alcotest.(check bool) "explicit sections have an admitted list parent" true
    (Lui_runtime.require_standard_node_kind app list = ListContainer);
  let sections = Lui_runtime.children app list in
  Alcotest.(check int) "separate native sections" 2 (List.length sections);
  List.iter2 (fun section row_count ->
    let children = Lui_runtime.children app section in
    let kind node = Lui_runtime.require_standard_node_kind app node in
    Alcotest.(check bool) "section headers remain explicit" true
      (List.exists (fun node -> kind node = ListSectionHeader) children);
    Alcotest.(check int) "each control remains a native row" row_count
      (List.length (List.filter (fun node -> kind node = ListItem) children)))
    sections [2;1];
  Alcotest.(check bool) "footer remains in its section" true
    (List.exists (fun node ->
      Lui_runtime.require_standard_node_kind app node = ListSectionFooter)
      (Lui_runtime.children app (List.hd sections)));
  Signal.dispose_scope scope

let phase4_authoring_contract () =
  let app, scope, context, _ = boundary_fixture () in
  let module Compatible : module type of struct include Lui_ui end = Lui.Ui in
  let raw = Compatible.text context "raw compatibility" in
  Lui.Raw.padding context raw 3;
  Alcotest.(check bool) "raw aliases share context and nodes" true
    (property_value app raw PaddingValue = IntValue 3);
  let text = Lui_elements.text ~role:`caption ~truncate:true
    ~style_class:"application" ~value:"long" [] context None in
  List.iter (fun (property, expected) ->
    Alcotest.(check bool) "truncation and role emit admitted properties" true
      (property_value app text property = expected))
    [WhiteSpace, StringValue "nowrap"; TextOverflow, StringValue "ellipsis";
     Overflow, StringValue "hidden"; LineClamp, IntValue 1;
     MinWidth, IntValue 0; StyleClass, StringValue "caption single-line application"];
  List.iter (fun view ->
    let node = view context None in
    Alcotest.(check bool) "every text family supports roles and truncation" true
      (property_value app node StyleClass = StringValue "body single-line"
       && property_value app node LineClamp = IntValue 1))
    [Lui_elements.heading ~role:`body ~truncate:true ~value:"Heading" [];
     Lui_elements.paragraph ~role:`body ~truncate:true ~value:"Paragraph" [];
     Lui_elements.label ~role:`body ~truncate:true ~value:"Label" []];
  let plain = Lui_elements.text ~truncate:false ~value:"" [] context None in
  Alcotest.(check bool) "empty untruncated text retains existing overflow" false
    (Property_map.mem WhiteSpace (Hashtbl.find app.Lui_runtime.runtime_properties plain));
  let row = Lui.Ui.hstack [] context None in
  let column = Lui.Ui.vstack ~gap:`none [] context None in
  Alcotest.(check bool) "stack defaults and explicit overrides" true
    (property_value app row Gap = IntValue 8
     && property_value app row CrossAlignment = StringValue "center"
     && property_value app row MinWidth = IntValue 0
     && property_value app column Gap = IntValue 0
     && property_value app column MinHeight = IntValue 0);
  List.iter (fun view -> ignore (view context None))
    [Lui.Ui.page ~title:"Page" []; Lui.Ui.form_sheet ~title:"Form" [];
     Lui.Ui.form_section ~title:"Section" [];
     Lui.Ui.form_field ~label:"Name" (Lui_elements.text_field []);
     Lui.Ui.form_field ~label:"Invalid" ~help:"hidden help" ~error:"validation error"
       (Lui_elements.text_field []);
     Lui.Ui.data_list ~label:"Rows" [];
     Lui.Ui.data_list ~label:"Rows" ~empty:(Lui_elements.text ~value:"empty rows" []) [];
     Lui.Ui.nav_bar ~title:"Navigation" ()];
  Alcotest.(check bool) "validation error takes precedence over help" true
    (List.mem "validation error" (text_values app) && not (List.mem "hidden help" (text_values app)));
  let errors = Signal.state context.ui_scheduler None in
  let control = ref None in
  ignore (Lui.Ui.form_field ~label:"Reactive name" ~help:"live help"
    ~error_signal:(Signal.value errors)
    (fun context parent ->
      let node = Lui_elements.text_field ~text:"editing" [] context parent in
      control := Some node; node) context None);
  let mounted_control = !control in
  ignore (Lui_runtime.flush app);
  Signal.set errors (Some "live error");
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "reactive validation preserves control identity and hides help" true
    (!control = mounted_control && List.mem "live error" (text_values app)
      && not (List.mem "live help" (text_values app)));
  Signal.set errors None;
  ignore (Lui_runtime.flush app);
  Alcotest.(check bool) "cleared error restores help without remount" true
    (!control = mounted_control && List.mem "live help" (text_values app));
  Alcotest.(check bool) "all composite output passes admission" true (Lui_runtime.flush app);
  Alcotest.(check string) "custom token is retained" "brand" (Lui_tokens.color_value (`token "brand"));
  Alcotest.(check string) "empty custom token is safe" "transparent" (Lui_tokens.color_value (`token " "));
  Alcotest.(check string) "hex encoding" "#123456" (Lui_tokens.color_value (`hex 0x123456));
  Alcotest.(check int) "negative spacing is normalized" 0 (Lui_tokens.space_value (`px (-1)));
  Alcotest.(check (list int)) "space scale" [0;4;8;12;16;24;16]
    (List.map Lui_tokens.space_value [`none;`xs;`sm;`md;`lg;`xl;`page]);
  Alcotest.(check (list int)) "radius scale and negative escape" [0;4;6;8;12;9999;0]
    (List.map Lui_tokens.radius_value [`none;`sm;`md;`lg;`xl;`full;`px (-1)]);
  Signal.dispose_scope scope

let tests = existing_tests @ List.map (fun (name, test) -> Alcotest.test_case name `Quick test)
  ["review wide child reorder", review_wide_reorder;
   "review sibling owner identity", review_sibling_state;
   "review keyed candidate rollback", (fun () -> review_keyed_candidate_failure false);
   "review keyed mount hook rollback", (fun () -> review_keyed_candidate_failure true);
   "review keyed cleanup commit", review_keyed_cleanup_failure;
   "review deep segment rollback", review_segment_checkpoint;
   "review library derivation ownership", review_library_derived_ownership;
   "review retired queued event", review_retired_event;
   "review subscription retirement", review_subscription_retirement;
   "review keyed locality", review_keyed_locality;
   "review unchanged keyed publication", review_keyed_unchanged;
   "keyed retained subtree allocation", keyed_retained_subtree_allocation;
   "keyed removed subtree rollback", keyed_removed_subtree_rollback;
   "property binding retention", property_binding_retention;
   "property binding values", property_binding_values;
   "property binding borrowed source", property_binding_borrowed_source;
   "property binding queued disposal", property_binding_queued_disposal;
   "property binding diamond", property_binding_diamond;
   "Phase 4 row visibility", phase4_rows_are_not_disclosures;
   "Phase 4 native form sections", phase4_form_sheet_sections;
   "Phase 4 authoring contract", phase4_authoring_contract]
