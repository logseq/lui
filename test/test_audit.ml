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
  Alcotest.(check bool) "removed row state disposed" true !(second_scope.Signal.disposed_scope);
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
  let subscription = { Signal.disposed = ref false; cancel = (fun () -> incr cancelled) } in
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
  Alcotest.(check bool) "old scope remains mounted" true (!(old.Signal.mounted) && not !(old.disposed_scope));
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
  Alcotest.(check bool) "current scope is live" false !(!(state.reload_view_scope).Signal.disposed_scope);
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

let tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f)
  ["keyed state isolation and lifetime", keyed_states;
   "extension validation retries", extension_retry;
   "backend exceptions and reentrant writes", backend_failure;
   "subscription startup cleanup", subscription_failure;
   "reload mount rollback", reload_mount_failure;
   "reload uncertain commit", reload_commit_failure;
   "reload postcommit cleanup failure", reload_cleanup_failure;
   "keyed scaling and reversal", keyed_scaling;
   "flat child scaling", child_scaling;
   "local switch scaling", switch_scaling;
   "nested switch ownership and rollback", switch_parent_and_rollback;
   "keyed cleanup after outer drop", keyed_outer_drop;
   "persistent sequence ordering", sequence_ordering]
