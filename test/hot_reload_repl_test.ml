module Session = Lg_repl.Session
module Watch_session = Lg_repl.Watch_session

let fail message = raise (Failure message)

let expect_ok = function
  | Ok value -> value
  | Error (error : Lg.Compiler.compile_error) ->
      fail
        (Printf.sprintf "%s: %s" error.code error.message)

let eval session source = Session.eval session source |> expect_ok

let rendered session source =
  match (eval session source).outcome with
  | Session.Value value -> value.rendered
  | _ -> fail ("expected a value from " ^ source)

let assert_equal expected actual message =
  if not (String.equal expected actual) then
    fail (Printf.sprintf "%s: expected %S, got %S" message expected actual)

let nearest_rank values percent =
  let sorted = List.sort Int.compare values |> Array.of_list in
  let rank = ((Array.length sorted * percent) + 99) / 100 in
  sorted.(max 0 (rank - 1))

let write_file path content =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel content)

let read_file path = In_channel.with_open_bin path In_channel.input_all

let watched_view_source label =
  Printf.sprintf
    {|
(defn counter-view [context model-source _send]
  (let [^:int _current (sig/sample model-source)
        root (ui/column! context)
        label (ui/text! context "%s")
        button (ui/button! context)]
    (ui/text-property! context button "Increment")
    (ui/on-event! context button (fn [_event] (_send 10)))
    (ui/append! context root label)
    (ui/append! context root button)
    root))
|}
    label

let () =
  if Array.length Sys.argv <> 5 then
    fail "expected state, subscription interface, and two fixture paths";
  let _runtime_anchor = Hot_reload_repl_base.lui_hot_reload_generation in
  let executable_directory = Filename.dirname Sys.executable_name in
  let bootstrap_interfaces =
    Filename.concat executable_directory ".hot_reload_repl_test.eobjs/byte"
  in
  let session =
    Session.create_from_state ~include_directories:[ bootstrap_interfaces ]
      ~state_path:Sys.argv.(1)
      ~bootstrap_module:"Dune__exe__Hot_reload_repl_base"
    |> expect_ok
  in
  eval session
    {|
(ns hot-reload.e2e
  (:require [signal.core :as sig]
            [lui.app :as app]
            [lui.hot-reload :as hot]
            [lui.protocol :as proto]
            [lui.subscriptions :as subscriptions]
            [lui.ui :as ui]
            [lui.backend.apple :as apple]))
|}
  |> ignore;
  eval session
    {|
(defn counter-view [context model-source _send]
  (let [^:int _current (sig/sample model-source)
        root (ui/column! context)
        label (ui/text! context "Before")
        button (ui/button! context)]
    (ui/text-property! context button "Increment")
    (ui/on-event! context button (fn [_event] (_send 1)))
    (ui/append! context root label)
    (ui/append! context root button)
    root))
|}
  |> ignore;
  Session.eval_files session [ Sys.argv.(2) ] |> expect_ok |> ignore;
  eval session "(defn add-action [^:int model ^:int action] (+ model action))"
  |> ignore;
  eval session "(def logic-reloads (atom 0))" |> ignore;
  eval session
    "(def cancel-logic-watch (watch-redef! add-action (fn [] (do (swap! logic-reloads inc) true))))"
  |> ignore;
  eval session "(def subscription-starts (atom 0))" |> ignore;
  eval session "(def subscription-stops (atom 0))" |> ignore;
  eval session (read_file Sys.argv.(3)) |> ignore;
  eval session "(def renderer (apple/create))" |> ignore;
  eval session
    {|
(def application
  (app/create-reloadable-with-subscriptions
   (apple/backend renderer) "source-a" "contract-a"
   2 add-action counter-view app-subscriptions))
|}
  |> ignore;
  assert_equal "1" (rendered session "(deref subscription-starts)")
    "the initial typed subscription set starts once";
  eval session "(app/start! application)" |> ignore;
  eval session "(app/flush! application)" |> ignore;
  eval session
    {|
(defn visible-text []
  (let [stable-root (app/root-node application)
        view (nth (apple/children renderer stable-root) 0)
        label (nth (apple/children renderer view) 0)]
    (match (apple/property renderer label proto/TextValue)
      (Some (proto/StringValue text)) text
      _ "missing")))
|}
  |> ignore;
  assert_equal "\"Before\"" (rendered session "(visible-text)")
    "the initial attached view is visible";
  eval session
    {|
(defn counter-view [context model-source _send]
  (let [^:int _current (sig/sample model-source)
        root (ui/column! context)
        label (ui/text! context "After")
        button (ui/button! context)]
    (ui/text-property! context button "Increment")
    (ui/on-event! context button (fn [_event] (_send 10)))
    (ui/append! context root label)
    (ui/append! context root button)
    root))
|}
  |> ignore;
  assert_equal "1"
    (rendered session
       {|
(match (:app-reload-state application)
  (Some state) (hot/generation (:reload-session state))
  None -1)
|})
    "the typed root observer commits one reload generation";
  assert_equal "\"After\"" (rendered session "(visible-text)")
    "an existing LUI application observes the replacement view";
  assert_equal "2" (rendered session "(app/model application)")
    "the live model survives attached view replacement";
  eval session (read_file Sys.argv.(4)) |> ignore;
  assert_equal "2" (rendered session "(deref subscription-starts)")
    "same-signature subscription logic starts its changed resource";
  assert_equal "1" (rendered session "(deref subscription-stops)")
    "the previous subscription is cancelled after replacement";
  eval session
    "(defn add-action [^:int model ^:int action] (+ model (* action 10)))"
  |> ignore;
  assert_equal "1" (rendered session "(deref logic-reloads)")
    "the typed update root publishes its replacement notification";
  eval session "(app/send! application 1)" |> ignore;
  eval session "(app/flush! application)" |> ignore;
  assert_equal "12" (rendered session "(app/model application)")
    "same-signature update logic is used by the existing dispatch closure";
  let watched_file = Filename.temp_file "lui-hot-reload-" ".cljc" in
  let now = ref 0. in
  Fun.protect
    ~finally:(fun () -> Sys.remove watched_file)
    (fun () ->
      write_file watched_file (watched_view_source "After");
      let watcher =
        Watch_session.create ~session ~paths:[ watched_file ]
          ~settle_seconds:0.05 ~now:(fun () -> !now)
        |> expect_ok
      in
      write_file watched_file (watched_view_source "Automatic");
      let detection_started = Unix.gettimeofday () in
      let detection = Watch_session.poll watcher in
      let detection_ms =
        Float.to_int ((Unix.gettimeofday () -. detection_started) *. 1000.)
      in
      Printf.printf "LUI_HOT_RELOAD_PERF change_detection_ms=%d\n%!"
        detection_ms;
      if detection_ms > 100 then
        fail
          (Printf.sprintf
             "file change acknowledgement exceeds the 100 ms target: %d ms"
             detection_ms);
      (match detection with
      | Some (Watch_session.Change_detected event) ->
          assert_equal "1" (string_of_int event.generation)
            "the watcher assigns a monotonic generation"
      | _ -> fail "expected the watcher to detect the saved view");
      now := 0.1;
      (match Watch_session.poll watcher with
      | Some (Watch_session.Reload_committed event) ->
          assert_equal "1" (string_of_int event.generation)
            "the settled save commits its generation"
      | _ -> fail "expected the watcher to commit the settled view");
      assert_equal "\"Automatic\"" (rendered session "(visible-text)")
        "saving a watched LG view updates the running LUI tree";
      write_file watched_file "(defn counter-view [";
      (match Watch_session.poll watcher with
      | Some (Watch_session.Change_detected event) ->
          assert_equal "2" (string_of_int event.generation)
            "an invalid save still receives a generation"
      | _ -> fail "expected the invalid save to be detected");
      now := 0.2;
      (match Watch_session.poll watcher with
      | Some (Watch_session.Reload_rejected event) ->
          assert_equal "2" (string_of_int event.generation)
            "the invalid generation is rejected"
      | _ -> fail "expected the invalid save to be rejected");
      assert_equal "\"Automatic\"" (rendered session "(visible-text)")
        "a compile failure keeps the last known-good LUI tree";
      write_file watched_file (watched_view_source "Burst one");
      (match Watch_session.poll watcher with
      | Some (Watch_session.Change_detected event) ->
          assert_equal "3" (string_of_int event.generation)
            "the first burst write is detected"
      | _ -> fail "expected the first burst write");
      now := 0.21;
      write_file watched_file (watched_view_source "Burst final");
      (match Watch_session.poll watcher with
      | Some (Watch_session.Change_detected event) ->
          assert_equal "4" (string_of_int event.generation)
            "a newer burst write supersedes the pending generation"
      | _ -> fail "expected the final burst write");
      now := 0.3;
      (match Watch_session.poll watcher with
      | Some (Watch_session.Reload_committed event) ->
          assert_equal "4" (string_of_int event.generation)
            "only the newest settled burst generation commits"
      | _ -> fail "expected the final burst generation to commit");
      assert_equal "\"Burst final\"" (rendered session "(visible-text)")
        "write coalescing publishes only the newest view");
  let watched_resource = Filename.temp_file "lui-hot-resource-" ".txt" in
  let resource_now = ref 0. in
  Fun.protect
    ~finally:(fun () -> Sys.remove watched_resource)
    (fun () ->
      write_file watched_resource "image-a";
      let invalidations = ref 0 in
      let retired = ref [] in
      let resources =
        Hot_reload_repl_base.lui_resources_create
          (fun nodes ->
            if Rrbvec.length nodes > 0 then incr invalidations;
            true)
          (fun resource ->
            retired := resource :: !retired;
            true)
      in
      (match
         Hot_reload_repl_base.lui_resources_reload_bang resources 1 "hero"
           (Digest.to_hex (Digest.string "image-a")) "image-a" Fun.id
       with
      | Hot_reload_repl_base.ResourceApplied 1 -> ()
      | _ -> fail "expected the initial resource to be applied");
      Hot_reload_repl_base.lui_resources_register_dependency_bang resources
        "hero" 99
      |> ignore;
      let watcher =
        Watch_session.create_with_reload ~paths:[ watched_resource ]
          ~settle_seconds:0.05 ~now:(fun () -> !resource_now)
          ~reload:(fun ~generation paths ->
            let payload = read_file (List.hd paths) in
            let source_hash = Digest.to_hex (Digest.string payload) in
            match
              Hot_reload_repl_base.lui_resources_reload_bang resources
                (generation + 1) "hero" source_hash payload Fun.id
            with
            | Hot_reload_repl_base.ResourceApplied _
            | Hot_reload_repl_base.ResourceUnchanged _ -> Ok ()
            | Hot_reload_repl_base.ResourceRejected (_, message) ->
                Error
                  {
                    Lg.Compiler.code = "LG9000";
                    phase = `Infrastructure;
                    title = "Resource reload rejected";
                    message;
                    location = None;
                    related = [];
                    hints = [];
                    fixes = [];
                    type_mismatch = None;
                  }
            | Hot_reload_repl_base.ResourceStale stale_generation ->
                Error
                  {
                    Lg.Compiler.code = "LG9001";
                    phase = `Infrastructure;
                    title = "Stale resource generation";
                    message =
                      Printf.sprintf "stale resource generation %d"
                        stale_generation;
                    location = None;
                    related = [];
                    hints = [];
                    fixes = [];
                    type_mismatch = None;
                  })
        |> expect_ok
      in
      write_file watched_resource "image-b";
      (match Watch_session.poll watcher with
      | Some (Watch_session.Change_detected _) -> ()
      | _ -> fail "expected the resource watcher to detect the save");
      resource_now := 0.1;
      (match Watch_session.poll watcher with
      | Some (Watch_session.Reload_committed _) -> ()
      | _ -> fail "expected the resource watcher to commit the save");
      (match Hot_reload_repl_base.lui_resources_current resources "hero" with
      | Some resource ->
          assert_equal "image-b" resource
            "saving a resource replaces the live resource"
      | None -> fail "expected a committed resource");
      assert_equal "1" (string_of_int !invalidations)
        "resource reload invalidates registered dependent nodes";
      match !retired with
      | [ resource ] ->
          assert_equal "image-a" resource
            "resource reload retires the replaced resource"
      | _ -> fail "expected exactly one retired resource");
  let reload_samples =
    List.init 20 (fun index ->
        let started = Unix.gettimeofday () in
        eval session
          (watched_view_source (Printf.sprintf "Parity benchmark %02d" index))
        |> ignore;
        Float.to_int ((Unix.gettimeofday () -. started) *. 1000.))
  in
  let p50 = nearest_rank reload_samples 50 in
  let p95 = nearest_rank reload_samples 95 in
  Printf.printf "LUI_HOT_RELOAD_PERF samples=20 p50_ms=%d p95_ms=%d\n%!" p50
    p95;
  if p95 > 500 then
    fail
      (Printf.sprintf
         "warm single-file UI reload p95 exceeds the 500 ms target: %d ms" p95);
  assert_equal "\"Parity benchmark 19\"" (rendered session "(visible-text)")
    "the latency fixture measures committed visible generations"
