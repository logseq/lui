open Lui_protocol

let backend apply_batch = { backend_profile = generic_profile (); apply_batch }
let runtime () = Lui_runtime.create (Signal.scheduler ()) (backend (fun _ -> true))
let attempt f = try f (); None with exn -> Some exn
let check_failure label result = Alcotest.(check bool) label true (Option.is_some result)

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

let existing_tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f)
  ["keyed state isolation and lifetime", keyed_states;
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
   "property binding diamond", property_binding_diamond]
