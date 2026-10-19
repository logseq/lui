(* Lifecycle tests for Lui_resource: generation supersede, stale
   completion discard, scope-dispose cancellation, foreground publish. *)

open Alcotest

module R = Lui_resource

let check' = check
let scope () = Signal.scope "test"
let ready e = match (R.state e) with R.Ready v -> Some v | _ -> None

let state_eq a b =
  match (a, b) with
  | R.Loading, R.Loading -> true
  | R.Ready x, R.Ready y -> x = y
  | R.Failed x, R.Failed y -> x = y
  | _ -> false

(* A string cache on the queued executor; [pump] runs the load jobs,
   [drain] publishes — the two-step async the rules describe. *)
let qcache ?(retire = fun _ -> ()) () =
  let exec, pump = R.executor_queued () in
  (R.create ~executor:exec ~retire (), pump)

(* ---------- basic load → publish ---------- *)

let test_load_ready () =
  let c, pump = qcache () in
  let sc = scope () in
  let seen = ref [] in
  let e =
    R.request c ~scope:sc "k"
      ~on_state:(fun e -> seen := (R.state e) :: !seen)
      ~load:(fun _ -> Ok "v")
  in
  check' int "gen 1" 1 (R.generation e);
  check' bool "loading" true (state_eq (R.state e) R.Loading);
  check' bool "task" true (Option.is_some (R.task e));
  check' int "runs" 1 (pump ());
  (* foreground publish: still Loading until drain *)
  check' bool "unpublished" true (state_eq (R.state e) R.Loading);
  check' int "pending" 1 (R.pending c);
  check' int "drained" 1 (R.drain c);
  check' bool "ready" true (state_eq (R.state e) (R.Ready "v"));
  check' (option string) "get" (Some "v") (R.get c "k");
  check' bool "watched" true (List.length !seen = 1);
  check' bool "task done" true (Option.is_none (R.task e));
  Signal.dispose_scope sc

let test_immediate_executor () =
  let c = R.create ~executor:R.executor_immediate () in
  let sc = scope () in
  let e = R.request c ~scope:sc "k" ~load:(fun _ -> Ok 42) in
  check' int "pending" 1 (R.pending c);
  ignore (R.drain c);
  check' (option int) "get" (Some 42) (R.get c "k");
  ignore e;
  Signal.dispose_scope sc

(* ---------- sharing ---------- *)

let test_shared_pending () =
  let c, pump = qcache () in
  let sc1, sc2 = (scope (), scope ()) in
  let loads = ref 0 in
  let load _ = incr loads; Ok "v" in
  let e1 = R.request c ~scope:sc1 "k" ~load in
  let e2 = R.request c ~scope:sc2 "k" ~load:(fun _ -> assert false) in
  check' bool "same entry" true (e1 == e2);
  check' int "runs once" 1 (pump ());
  check' int "loads once" 1 !loads;
  ignore (R.drain c);
  check' (option string) "shared" (Some "v") (R.get c "k");
  Signal.dispose_scope sc1;
  Signal.dispose_scope sc2

(* ---------- generation supersede ---------- *)

let test_reload_supersedes () =
  let c, pump = qcache () in
  let retired = ref [] in
  let c' = c in
  ignore c';
  let sc = scope () in
  let e = R.request c ~scope:sc "k" ~load:(fun _ -> Ok "old") in
  let gen1 = (R.generation e) in
  let task1 = Option.get (R.task e) in
  let e2 = R.reload c ~scope:sc "k" ~load:(fun _ -> Ok "new") in
  check' bool "same entry" true (e == e2);
  check' int "gen +1" (gen1 + 1) (R.generation e2);
  check' bool "old cancelled" true (R.task_cancelled task1);
  (* run the stale job first, then the new one *)
  check' int "runs" 2 (pump ());
  check' int "drained" 2 (R.drain c);
  check' bool "new wins" true (state_eq (R.state e2) (R.Ready "new"));
  check' (option string) "get" (Some "new") (R.get c "k");
  check' bool "retired nothing extra" true (!retired = []);
  Signal.dispose_scope sc

let test_stale_never_overwrites_ready () =
  let retired = ref [] in
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec ~retire:(fun v -> retired := v :: !retired) () in
  let sc = scope () in
  let _ = R.request c ~scope:sc "k" ~load:(fun _ -> Ok "gen1") in
  let e = R.reload c ~scope:sc "k" ~load:(fun _ -> Ok "gen2") in
  ignore (pump ());
  ignore (R.drain c);
  check' (option string) "gen2" (Some "gen2") (R.get c "k");
  check' bool "stale retired" true (!retired = [ "gen1" ]);
  ignore e;
  Signal.dispose_scope sc

let test_ready_value_retired_on_reload () =
  let retired = ref [] in
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec ~retire:(fun v -> retired := v :: !retired) () in
  let sc = scope () in
  ignore (R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v1"));
  ignore (pump ());
  ignore (R.drain c);
  let e = R.reload c ~scope:sc "k" ~load:(fun _ -> Ok "v2") in
  check' bool "v1 retired at reload" true (!retired = [ "v1" ]);
  check' (option string) "hidden while loading" None (R.get c "k");
  ignore (pump ());
  ignore (R.drain c);
  check' (option string) "v2" (Some "v2") (R.get c "k");
  ignore e;
  Signal.dispose_scope sc

(* ---------- scope dispose ---------- *)

let test_scope_dispose_cancels () =
  let retired = ref [] in
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec ~retire:(fun v -> retired := v :: !retired) () in
  let sc = scope () in
  let e = R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v") in
  let task = Option.get (R.task e) in
  Signal.dispose_scope sc;
  check' bool "task cancelled" true (R.task_cancelled task);
  check' bool "entry gone" false (R.mem c "k");
  (* the in-flight job still completes; its value is retired, not
     published *)
  check' int "runs" 1 (pump ());
  check' int "drained" 1 (R.drain c);
  check' bool "retired" true (!retired = [ "v" ]);
  check' (option string) "nothing" None (R.get c "k")

let test_shared_scope_survives () =
  let c, pump = qcache () in
  let sc1, sc2 = (scope (), scope ()) in
  ignore (R.request c ~scope:sc1 "k" ~load:(fun _ -> Ok "v"));
  ignore (R.request c ~scope:sc2 "k" ~load:(fun _ -> Ok "v"));
  Signal.dispose_scope sc1;
  check' bool "still there" true (R.mem c "k");
  Signal.dispose_scope sc2;
  check' bool "gone" false (R.mem c "k");
  ignore (pump ());
  ignore (R.drain c)

let test_scope_dispose_ready_retires () =
  let retired = ref [] in
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec ~retire:(fun v -> retired := v :: !retired) () in
  let sc = scope () in
  ignore (R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v"));
  ignore (pump ());
  ignore (R.drain c);
  Signal.dispose_scope sc;
  check' bool "ready retired" true (!retired = [ "v" ])

let test_disposed_scope_rejected () =
  let c, _ = qcache () in
  let sc = scope () in
  Signal.dispose_scope sc;
  check' bool "raises" true
    (try
       ignore (R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v"));
       false
     with Invalid_argument _ -> true)

(* ---------- invalidate / clear ---------- *)

let test_invalidate () =
  let retired = ref [] in
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec ~retire:(fun v -> retired := v :: !retired) () in
  let sc = scope () in
  ignore (R.request c ~scope:sc "a" ~load:(fun _ -> Ok "va"));
  ignore (R.request c ~scope:sc "b" ~load:(fun _ -> Ok "vb"));
  ignore (pump ());
  ignore (R.drain c);
  R.invalidate c "a";
  check' int "one left" 1 (R.length c);
  check' bool "va retired" true (!retired = [ "va" ]);
  R.clear c;
  check' int "empty" 0 (R.length c);
  check' bool "vb retired" true (!retired = [ "vb"; "va" ]);
  Signal.dispose_scope sc

(* ---------- failure ---------- *)

let test_failure () =
  let c, pump = qcache () in
  let sc = scope () in
  let seen = ref [] in
  let e =
    R.request c ~scope:sc "k"
      ~on_state:(fun e -> seen := (R.state e) :: !seen)
      ~load:(fun _ -> Error "boom")
  in
  ignore (pump ());
  ignore (R.drain c);
  check' bool "failed" true (state_eq (R.state e) (R.Failed "boom"));
  check' (option string) "no value" None (R.get c "k");
  check' bool "watcher ran" true (List.length !seen = 1);
  Signal.dispose_scope sc

let test_load_exception () =
  let c, pump = qcache () in
  let sc = scope () in
  let e =
    R.request c ~scope:sc "k" ~load:(fun _ -> failwith "crash")
  in
  ignore (pump ());
  ignore (R.drain c);
  check' bool "failed" true
    (match (R.state e) with R.Failed _ -> true | _ -> false);
  Signal.dispose_scope sc

(* ---------- watchers ---------- *)

let test_watcher_dead_scope_pruned () =
  let c, pump = qcache () in
  let sc1, sc2 = (scope (), scope ()) in
  let alive = ref 0 in
  let dead = ref 0 in
  (* sc2 must own the entry too — a watcher alone does not keep the
     entry alive *)
  let e = R.request c ~scope:sc1 "k" ~load:(fun _ -> Ok "v") in
  ignore (R.request c ~scope:sc2 "k" ~load:(fun _ -> Ok "v"));
  R.watch ~scope:sc1 e (fun _ -> incr dead);
  R.watch ~scope:sc2 e (fun _ -> incr alive);
  Signal.dispose_scope sc1;
  ignore (pump ());
  ignore (R.drain c);
  check' int "dead not called" 0 !dead;
  check' int "alive called" 1 !alive;
  Signal.dispose_scope sc2

let test_late_watcher_fires_immediately () =
  let c, pump = qcache () in
  let sc = scope () in
  let e = R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v") in
  ignore (pump ());
  ignore (R.drain c);
  let called = ref 0 in
  R.watch ~scope:sc e (fun e ->
      incr called;
      check' (option string) "value" (Some "v") (ready e));
  check' int "immediate" 1 !called;
  Signal.dispose_scope sc

let test_cooperative_cancel () =
  let exec, pump = R.executor_queued () in
  let c = R.create ~executor:exec () in
  let sc = scope () in
  let e =
    R.request c ~scope:sc "k" ~load:(fun task ->
        if R.task_cancelled task then Error "cancelled" else Ok "v")
  in
  let task = Option.get (R.task e) in
  Signal.dispose_scope sc;
  ignore (pump ());
  ignore (R.drain c);
  check' bool "cancelled flag" true (R.task_cancelled task);
  check' (option string) "dropped" None (R.get c "k")

(* ---------- real domain executor ---------- *)

let test_domain_executor () =
  let c = R.create ~executor:R.executor_domain () in
  let sc = scope () in
  let e = R.request c ~scope:sc "k" ~load:(fun _ -> Ok "v") in
  let deadline = Unix.gettimeofday () +. 5. in
  while R.pending c = 0 && Unix.gettimeofday () < deadline do
    Unix.sleepf 0.001
  done;
  check' bool "completed" true (R.pending c = 1);
  ignore (R.drain c);
  check' (option string) "ready" (Some "v") (R.get c "k");
  ignore e;
  Signal.dispose_scope sc

(* ---------- drain_all ---------- *)

let test_drain_all () =
  let exec1, pump1 = R.executor_queued () in
  let exec2, pump2 = R.executor_queued () in
  let c1 = R.create ~executor:exec1 () in
  let c2 = R.create ~executor:exec2 () in
  let sc = scope () in
  ignore (R.request c1 ~scope:sc "a" ~load:(fun _ -> Ok 1));
  ignore (R.request c2 ~scope:sc "b" ~load:(fun _ -> Ok "x"));
  ignore (pump1 ());
  ignore (pump2 ());
  check' bool "some drained" true (R.drain_all () >= 2);
  check' (option int) "a" (Some 1) (R.get c1 "a");
  check' (option string) "b" (Some "x") (R.get c2 "b");
  R.unregister c1;
  R.unregister c2;
  Signal.dispose_scope sc

let test_recreated_key_rejects_old_completion () =
  List.iter (fun clear ->
    let retired=ref [] in
    let cache,pump=qcache ~retire:(fun value -> retired:=value::!retired) () in
    let first=scope () and second=scope () in
    ignore (R.request cache ~scope:first "same" ~load:(fun _ -> Ok "old"));
    if clear then R.clear cache else Signal.dispose_scope first;
    let current=R.request cache ~scope:second "same" ~load:(fun _ -> Ok "new") in
    ignore (pump ());ignore (R.drain cache);
    check' (option string) "recreated entry accepts only its own completion" (Some "new") (ready current);
    check' bool "stale decoded value retires" true (List.mem "old" !retired);
    Signal.dispose_scope first;Signal.dispose_scope second;R.unregister cache) [false;true]

let test_disposed_watcher_releases_capture () =
  List.iter (fun owning ->
    let cache,pump=qcache () in
    let owner=scope () in
    let entry=R.request cache ~scope:owner "ready" ~load:(fun _ -> Ok 1) in
    ignore (pump ());ignore (R.drain cache);
    let weak=Weak.create 1 in
    let bind () =
      let payload=Bytes.make 8192 'x' in
      Weak.set weak 0 (Some payload);
      let observer=scope () in
      let callback _ = ignore (Sys.opaque_identity payload) in
      if owning then ignore (R.request cache ~scope:observer ~on_state:callback "ready" ~load:(fun _ -> Ok 2))
      else R.watch ~scope:observer entry callback;
      Signal.dispose_scope observer in
    bind ();Gc.full_major ();
    check' bool "disposed watcher releases its captured data without another publish" true (Weak.get weak 0=None);
    Signal.dispose_scope owner;R.unregister cache) [false;true]

let test_bulk_watcher_disposal_allocation () =
  let cache,pump=qcache () and owner=scope () in
  let entry=R.request cache ~scope:owner "shared" ~load:(fun _ -> Ok 1) in
  ignore (pump ());ignore (R.drain cache);
  let observers=Array.init 2000 (fun _ -> let scope=scope () in R.watch ~scope entry (fun _ -> ());scope) in
  let before=Gc.allocated_bytes () in
  Array.iter Signal.dispose_scope observers;
  let allocated=Gc.allocated_bytes () -. before in
  Printf.printf "resource watcher disposal: %.0f bytes/%d scopes\n%!" allocated (Array.length observers);
  check' bool "shared resource cleanup avoids quadratic temporary lists" true
    (allocated<float_of_int (Array.length observers*4096));
  Signal.dispose_scope owner;R.unregister cache

let () =
  run "lui_resource"
    [
      ( "lifecycle",
        [
          test_case "recreated key" `Quick test_recreated_key_rejects_old_completion;
          test_case "load ready" `Quick test_load_ready;
          test_case "immediate executor" `Quick test_immediate_executor;
          test_case "shared pending" `Quick test_shared_pending;
          test_case "reload supersedes" `Quick test_reload_supersedes;
          test_case "stale never overwrites" `Quick
            test_stale_never_overwrites_ready;
          test_case "ready retired on reload" `Quick
            test_ready_value_retired_on_reload;
        ] );
      ( "scopes",
        [
          test_case "dispose cancels" `Quick test_scope_dispose_cancels;
          test_case "shared survives" `Quick test_shared_scope_survives;
          test_case "dispose retires ready" `Quick
            test_scope_dispose_ready_retires;
          test_case "disposed rejected" `Quick test_disposed_scope_rejected;
        ] );
      ( "cache",
        [
          test_case "invalidate + clear" `Quick test_invalidate;
          test_case "drain all" `Quick test_drain_all;
        ] );
      ( "result",
        [
          test_case "failure" `Quick test_failure;
          test_case "exception" `Quick test_load_exception;
          test_case "cooperative cancel" `Quick test_cooperative_cancel;
        ] );
      ( "watchers",
        [
          test_case "bulk disposal allocation" `Quick test_bulk_watcher_disposal_allocation;
          test_case "disposed capture released" `Quick test_disposed_watcher_releases_capture;
          test_case "dead scope pruned" `Quick test_watcher_dead_scope_pruned;
          test_case "late fires immediately" `Quick
            test_late_watcher_fires_immediately;
        ] );
      ( "executors",
        [ test_case "domain" `Quick test_domain_executor ] );
    ]
