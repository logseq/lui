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

let write_file path content =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel content)

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
  eval session "(defn add-action [model action] (+ model action))" |> ignore;
  eval session "(def renderer (apple/create))" |> ignore;
  eval session
    {|
(def application
  (app/create-reloadable
   (apple/backend renderer) "source-a" "contract-a"
   2 add-action counter-view))
|}
  |> ignore;
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
      (match Watch_session.poll watcher with
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
        "write coalescing publishes only the newest view")
