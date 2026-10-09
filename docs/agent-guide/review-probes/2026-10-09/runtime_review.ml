open Lui_protocol
let backend = {backend_profile=generic_profile (); apply_batch=(fun _ -> true)}
let runtime () = Lui_runtime.create (Signal.scheduler ()) backend
let flush app = ignore (Lui_runtime.flush app)
let attempt f = try f (); "ok" with e -> Printexc.to_string e
let count app = Lui_runtime.mounted_count app
let keyed_partial_failure () =
  let app=runtime () in
  let context=Lui_ui.context app (Signal.scope "owner") in
  let parent=Lui_ui.column context in
  let source=Signal.state context.ui_scheduler [1] in
  let boom=ref false in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item -> let key=Signal.sample item in
      let node=Lui_ui.text row (string_of_int key) in
      if !boom && key=3 then failwith "mount after creating node";
      node));
  flush app;
  let before=count app in
  boom:=true; Signal.set source [1;2;3];
  let failure=attempt (fun () -> flush app) in
  Printf.printf "keyed_partial_failure: before=%d after=%d children=%d pending=%d failure=%s\n" before (count app)
    (List.length (Lui_runtime.children app parent)) (List.length !(app.pending_ops)) failure;
  Signal.set source [1]; flush app;
  Printf.printf "keyed_partial_failure: after_recovery=%d\n" (count app)
let keyed_mount_hook_failure () =
  let app=runtime () in
  let context=Lui_ui.context app (Signal.scope "owner") in
  let parent=Lui_ui.column context in
  let source=Signal.state context.ui_scheduler [] in
  let candidate=ref None in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row _ -> candidate:=Some row.ui_scope;
      Signal.on_mount row.ui_scope (fun () -> failwith "mount hook");
      Lui_ui.text row "candidate"));
  flush app; Signal.set source [1];
  ignore (attempt (fun () -> flush app));
  let scope=Option.get !candidate in
  Printf.printf "keyed_mount_hook_failure: nodes=%d mounted=%b disposed=%b\n" (count app) !(scope.mounted) !(scope.disposed_scope)
let keyed_teardown_failure () =
  let app=runtime () in
  let context=Lui_ui.context app (Signal.scope "owner") in
  let parent=Lui_ui.column context in
  let source=Signal.state context.ui_scheduler [1] in
  let row_scope=ref None in
  ignore (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row _ -> row_scope:=Some row.ui_scope;
      Signal.on_dispose row.ui_scope (fun () -> failwith "cleanup failed");
      Lui_ui.text row "old"));
  flush app; Signal.set source [];
  let failure=attempt (fun () -> flush app) in
  let segment=List.hd (Hashtbl.find app.dynamic_segments parent) in
  Printf.printf "keyed_teardown_failure: children=%d segment_size=%d row_disposed=%b failure=%s\n"
    (List.length (Lui_runtime.children app parent)) !(segment.dynamic_segment_size)
    !((Option.get !row_scope).disposed_scope) failure;
  Signal.set source [];
  Printf.printf "keyed_teardown_retry: %s\n" (attempt (fun () -> flush app))
let sibling_state_collision () =
  let app=runtime () in
  let context=Lui_ui.context app (Signal.scope "owner") in
  let parent=Lui_ui.column context in
  let slot=Signal.state_slot "draft" in
  let row_state initial row _ =
    let state=Signal.state_at row.Lui_ui.ui_scheduler row.ui_state_scope slot initial in
    Lui_ui.text row (string_of_int (Signal.get_state state)) in
  let source=Signal.state context.ui_scheduler 0 in
  let first=Lui_dynamic.switch context parent (Signal.value source) Int.equal (row_state 10) in
  let second=Lui_dynamic.switch context parent (Signal.value source) Int.equal (row_state 20) in
  flush app;
  let text sw=Property_map.find TextValue (Hashtbl.find app.runtime_properties (Lui_dynamic.switch_node sw)) in
  let value=function StringValue s -> s | _ -> "?" in
  Printf.printf "sibling_state_collision: first=%s second=%s expected=10,20\n" (value(text first)) (value(text second))
let removed_handler_event () =
  let app=runtime () in let scope=Signal.scope "owner" in
  let node=Lui_runtime.create_node app Button in
  let called=ref 0 in
  Lui_runtime.on_event scope app node (fun _ -> incr called);
  ignore (Lui_runtime.dispatch app (Press node));
  Signal.dispose_scope scope; Lui_runtime.drop_subtree app node;
  flush app;
  Printf.printf "removed_handler_event: callbacks_after_drop=%d\n" !called
let subscription_dispose_failure () =
  let c=Lui_subscriptions.create () in
  let started=ref 0 and cancelled=ref 0 in
  let spec version fail = {Lui_subscriptions.subscription_key="one";
    subscription_fingerprint=version; start_subscription=(fun () -> incr started;
      {Signal.disposed=ref false; cancel=(fun () -> incr cancelled; if fail then failwith "cancel failed")})} in
  ignore (Lui_subscriptions.reconcile c 1 [spec "old" true]);
  let failure=attempt (fun () -> ignore(Lui_subscriptions.reconcile c 2 [spec "new" false])) in
  Printf.printf "subscription_dispose_failure: started=%d cancelled=%d tracked=%d failure=%s\n" !started !cancelled
    (Lui_subscriptions.count c) failure
let checkpoint_perf n =
  let app=runtime () in let context=Lui_ui.context app (Signal.scope "owner") in
  for _=1 to n do ignore(Lui_ui.text context "unrelated") done;
  let parent=Lui_ui.column context in let source=Signal.state context.ui_scheduler [1] in
  ignore(Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
    (fun row item -> Lui_ui.text row (string_of_int(Signal.sample item))));
  flush app; Gc.full_major ();
  let bytes=Gc.allocated_bytes () and time=Sys.time () in
  for _=1 to 20 do Signal.set source [1]; flush app done;
  Printf.printf "keyed_no_change n=%d ms=%.3f allocated_mb=%.3f\n" n ((Sys.time()-.time)*.1000.)
    ((Gc.allocated_bytes()-.bytes)/.1000000.)
let () = keyed_partial_failure (); keyed_mount_hook_failure (); keyed_teardown_failure ();
  sibling_state_collision (); removed_handler_event (); subscription_dispose_failure ();
  List.iter checkpoint_perf [1000;10000;50000]

let derived_signal_leak () =
  let app=runtime () in let context=Lui_ui.context app (Signal.scope "owner") in
  let parent=Lui_ui.column context in let model=Signal.state context.ui_scheduler "value" in
  let branch=Signal.state context.ui_scheduler 0 in
  ignore(Lui_dynamic.switch context parent (Signal.value branch) Int.equal (fun row _ ->
    let derived=Signal.map String.uppercase_ascii (Signal.value model) in
    Lui_ui.text_signal row derived));
  flush app;
  let before=List.length !((Signal.value model).subscribers) in
  for i=1 to 20 do Signal.set branch i; flush app done;
  Printf.printf "derived_signal_leak: initial_upstream=%d after_20_remounts=%d\n" before
    (List.length !((Signal.value model).subscribers))
let () = derived_signal_leak ()
