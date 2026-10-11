(* Tests for the updater UI layer: the pure phase machine, the string
   tables, the drawn view tree, and the session driver over a fake
   core — never the network. *)

module S = Lui_plugin_updater_ui.Session
module T = Lui_plugin_updater_ui.Strings
module TR = Lui_plugin_updater_ui.Translations
module V = Lui_plugin_updater_ui.View
module U = Lui_updater
module P = Lui_pkg.Private

let phase_testable =
  Alcotest.testable
    (fun fmt p -> Format.pp_print_string fmt (S.phase_name p))
    (fun a b -> S.phase_name a = S.phase_name b)

let check_phase msg expected (m : S.model) =
  Alcotest.check phase_testable msg expected m.S.phase

(* ------------------------------------------------------------------ *)
(* Fixtures *)

let info ?(version = "2.0.0") ?(notes = "- fixes\n- features") () :
    U.update_info =
  {
    version;
    notes;
    date = "2026-10-10";
    archive =
      {
        url = "https://example.test/app-2.0.0.tar.gz";
        size = 4_200_000;
        sha256 = String.make 64 'a';
        signature = None;
      };
    deltas = [];
  }

let has_sub hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i =
    i + m <= n
    && (String.sub hay i m = needle || go (i + 1))
  in
  go 0

let en = TR.for_locale "en"

let model ?(text = en) () =
  S.initial_model ~app_name:"TestApp" ~current_version:"1.0.0" ~text

(* ------------------------------------------------------------------ *)
(* The pure machine *)

let test_idle_to_available () =
  let m = model () in
  let m = S.update m (S.Check { user = true }) in
  check_phase "checking" S.Checking m;
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  check_phase "offer shown" (S.Available (S.offer_of (info ()))) m;
  match m.S.phase with
  | S.Available o ->
    Alcotest.(check string) "version" "2.0.0" o.S.version;
    Alcotest.(check int) "size" 4_200_000 o.S.size
  | _ -> Alcotest.fail "expected Available"

let test_up_to_date_foreground_vs_background () =
  let m =
    S.update (model ()) (S.Check { user = true })
    |> fun m -> S.update m (S.Checked (Stdlib.Ok None))
  in
  check_phase "user sees up-to-date" S.Up_to_date m;
  let m =
    S.update (model ()) (S.Check { user = false })
    |> fun m -> S.update m (S.Checked (Stdlib.Ok None))
  in
  check_phase "background check stays silent" S.Idle m

let test_check_error_retryable () =
  let m =
    S.update (model ()) (S.Check { user = true })
    |> fun m -> S.update m (S.Checked (Stdlib.Error "offline"))
  in
  match m.S.phase with
  | S.Error e ->
    Alcotest.(check bool) "retryable" true e.S.retryable;
    Alcotest.(check bool) "foreground" true e.S.foreground
  | _ -> Alcotest.fail "expected Error"

let test_install_flow () =
  let m = S.update (model ()) (S.Check { user = true }) in
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  let m = S.update m S.Install_now in
  check_phase "downloading" (S.Downloading (S.dl_start (S.offer_of (info ())))) m;
  let m =
    S.update m
      (S.Progress { received = 2_100_000; total = 4_200_000; at = 1. })
  in
  (match m.S.phase with
   | S.Downloading d ->
     Alcotest.(check int) "bytes" 2_100_000 d.S.bytes_done
   | _ -> Alcotest.fail "expected Downloading");
  let m =
    S.update m
      (S.Progress { received = 4_200_000; total = 4_200_000; at = 2. })
  in
  check_phase "complete → verifying" (S.Verifying (S.offer_of (info ()))) m;
  let st =
    { U.stage_dir = "/tmp/st"; new_root = "/tmp/st/app"; layout = U.Dir }
  in
  let m =
    S.update m (S.Staged_ok (st, S.offer_of (info ())))
  in
  check_phase "staged" (S.Staged { S.st; offer = S.offer_of (info ()) }) m;
  let m =
    S.update m
      (S.Swapped { S.version = "2.0.0"; exe = "/app/exe"; backup = "/b" })
  in
  check_phase "ready"
    (S.Ready_to_restart { S.version = "2.0.0"; exe = "/app/exe"; backup = "/b" })
    m

let test_cancel_returns_to_offer () =
  let m = S.update (model ()) (S.Check { user = true }) in
  let m =
    S.update
      (S.update (S.update m (S.Checked (Stdlib.Ok (Some (info ())))))
         S.Install_now)
      S.Cancel_download
  in
  check_phase "cancel → offer kept"
    (S.Available (S.offer_of (info ())))
    m

let test_error_offer_retained_for_retry () =
  let m = model () in
  let m = S.update m (S.Check { user = true }) in
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  let m = S.update m S.Install_now in
  let m = S.update m (S.Failed (S.Download_failed, "reset by peer")) in
  match m.S.phase with
  | S.Error e ->
    Alcotest.(check bool) "download retryable" true e.S.retryable;
    (match e.S.offer with
     | Some o -> Alcotest.(check string) "offer kept" "2.0.0" o.S.version
     | None -> Alcotest.fail "expected offer retained")
  | _ -> Alcotest.fail "expected Error"

let test_verify_error_not_retryable () =
  let m = model () in
  let m = S.update m (S.Check { user = true }) in
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  let m = S.update m S.Install_now in
  let m = S.update m (S.Failed (S.Verify_failed, "bad sha256")) in
  match m.S.phase with
  | S.Error e ->
    Alcotest.(check bool) "verify not retryable" false e.S.retryable
  | _ -> Alcotest.fail "expected Error"

let test_skip_then_background_check_stays_idle () =
  let m = model () in
  let m = S.update m (S.Check { user = true }) in
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  let m = S.update m S.Skip_version in
  check_phase "skip closes" S.Closed m;
  (* a later background check of the same version must not re-offer *)
  let m2 = { m with S.phase = S.Idle } in
  let m2 = S.update m2 (S.Check { user = false }) in
  let m2 = S.update m2 (S.Checked (Stdlib.Ok (Some (info ())))) in
  check_phase "skipped stays idle" S.Idle m2

let test_check_ignored_mid_download () =
  let m = model () in
  let m = S.update m (S.Check { user = true }) in
  let m = S.update m (S.Checked (Stdlib.Ok (Some (info ())))) in
  let m = S.update m S.Install_now in
  let before = m.S.phase in
  let m = S.update m (S.Check { user = true }) in
  Alcotest.(check bool) "still downloading"
    true
    (match (before, m.S.phase) with
     | S.Downloading _, S.Downloading _ -> true
     | _ -> false)

let test_dismiss_closes () =
  let m =
    S.update (model ()) (S.Check { user = true })
    |> fun m -> S.update m (S.Checked (Stdlib.Ok (Some (info ()))))
  in
  let m = S.update m S.Dismiss in
  check_phase "closed" S.Closed m

(* ------------------------------------------------------------------ *)
(* The driver over a fake core — same transitions, no network. *)

let fake_feed =
  {
    U.base_url = "https://example.test/updates";
    channel = U.Stable;
    app_id = "com.example.test";
    app_name = "TestApp";
    version = "1.0.0";
  }

(* A scriptable core: each hook replays what the test installed. *)
let scripted_core ?(check_result = Stdlib.Ok (Some (info ()))) () =
  let checks = ref 0
  and downloads = ref 0
  and applys = ref 0
  and swaps = ref 0
  and relaunches = ref 0
  and download_hook = ref (fun _progress ~dest:_ -> Stdlib.Ok ())
  and apply_hook =
    ref
      (fun ~package:_ ~stage_dir ->
        Stdlib.Ok
          { U.stage_dir;
            new_root = Filename.concat stage_dir "app";
            layout = U.Dir })
  and swap_hook = ref (fun _st ~target:_ -> Stdlib.Ok "/backup")
  in
  let core : S.core =
    {
      check =
        (fun ~fetch:_ _f ->
          incr checks;
          check_result);
      plan = (fun i ~current:_ -> U.Full i.U.archive);
      download =
        (fun ~fetch:_ ~verify_sig:_ ~progress _a ~dest ->
          incr downloads;
          !download_hook progress ~dest);
      apply =
        (fun ~verify:_ ~info:_ ~plan:_ ~package ~bundle:_ ~stage_dir () ->
          incr applys;
          !apply_hook ~package ~stage_dir);
      swap = (fun st ~target -> incr swaps; !swap_hook st ~target);
      relaunch = (fun ~exe:_ ~args:_ -> incr relaunches);
    }
  in
  (core, checks, downloads, applys, swaps, relaunches, download_hook,
   apply_hook, swap_hook)

let session_dir () = P.Fs.temp_dir ~prefix:"lui_upd_ui_test-" ()

let session_with core =
  let base = session_dir () in
  S.create ~core ~feed:fake_feed
    ~bundle:(Filename.concat base "app")
    ~exe:"testapp"
    ~stage_dir:(Filename.concat base "app.update")
    ~work_dir:(Filename.concat base "dl")
    ()

let test_driver_install_ready () =
  let core, _, downloads, applys, swaps, _, _, _, _ =
    scripted_core ()
  in
  let s = session_with core in
  S.check ~user:true s;
  check_phase "offer" (S.Available (S.offer_of (info ()))) (S.model s);
  S.install s;
  (match S.status s with
   | S.Ready_to_restart r ->
     Alcotest.(check string) "version" "2.0.0" r.S.version
   | p -> Alcotest.failf "expected ready, got %s" (S.phase_name p));
  Alcotest.(check int) "one download" 1 !downloads;
  Alcotest.(check int) "one apply" 1 !applys;
  Alcotest.(check int) "one swap" 1 !swaps

let test_driver_download_stages_then_install () =
  let core, _, _, _, swaps, relaunches, _, _, _ = scripted_core () in
  let s = session_with core in
  S.check ~user:true s;
  S.download s;
  (match S.status s with
   | S.Staged _ -> ()
   | p -> Alcotest.failf "expected staged, got %s" (S.phase_name p));
  Alcotest.(check int) "no swap yet" 0 !swaps;
  S.install s;
  (match S.status s with
   | S.Ready_to_restart _ -> ()
   | p -> Alcotest.failf "expected ready, got %s" (S.phase_name p));
  S.relaunch s;
  Alcotest.(check int) "relaunched" 1 !relaunches

let test_driver_cancel_mid_download () =
  let core, _, _, _, _, _, download_hook, _, _ = scripted_core () in
  let s_ref = ref None in
  download_hook :=
    (fun progress ~dest:_ ->
      (* report half, cancel from inside the transfer, report again:
         the second report must observe the flag and abort *)
      progress ~received:100 ~total:200;
      (match !s_ref with Some s -> S.cancel s | None -> ());
      (match
         (try progress ~received:200 ~total:200; `live
          with S.Cancelled -> `aborted)
       with
       | `live -> Alcotest.fail "progress ignored cancellation"
       | `aborted -> raise S.Cancelled));
  let s = session_with core in
  s_ref := Some s;
  S.check ~user:true s;
  S.install s;
  check_phase "cancel returns to the offer"
    (S.Available (S.offer_of (info ())))
    (S.model s)

let test_driver_download_failure_and_retry () =
  let core, checks, downloads, _, _, _, download_hook, _, _ =
    scripted_core ()
  in
  download_hook := (fun _progress ~dest:_ -> Stdlib.Error "conn reset");
  let s = session_with core in
  S.check ~user:true s;
  Alcotest.(check int) "checked once" 1 !checks;
  S.install s;
  Alcotest.(check int) "one attempt" 1 !downloads;
  (match S.status s with
   | S.Error e ->
     Alcotest.(check bool) "retryable" true e.S.retryable
   | p -> Alcotest.failf "expected error, got %s" (S.phase_name p));
  (* a fixed network lets retry complete the install *)
  download_hook := (fun _progress ~dest:_ -> Stdlib.Ok ());
  S.retry s;
  (match S.status s with
   | S.Ready_to_restart _ -> ()
   | p -> Alcotest.failf "expected ready after retry, got %s"
            (S.phase_name p));
  Alcotest.(check int) "two attempts" 2 !downloads

let test_driver_check_failure () =
  let core, _, _, _, _, _, _, _, _ =
    scripted_core ~check_result:(Stdlib.Error "dns") ()
  in
  let s = session_with core in
  S.check ~user:true s;
  match S.status s with
  | S.Error e ->
    Alcotest.(check bool) "check error retryable" true e.S.retryable
  | p -> Alcotest.failf "expected error, got %s" (S.phase_name p)

(* ------------------------------------------------------------------ *)
(* Staged apply, for real: a fake fetch serves a tar the test builds,
   while [apply]/[swap] stay the production code paths. *)

let test_real_apply_and_swap () =
  let base = session_dir () in
  (* the installed app: a plain directory of files *)
  let bundle = Filename.concat base "app" in
  P.Fs.mkdir_p bundle;
  P.Fs.write_file (Filename.concat bundle "bin") "#!/bin/sh\nold\n";
  P.Fs.write_file (Filename.concat bundle "data.txt") "old-data\n";
  (* the new tree the package untars to *)
  let new_tree = Filename.concat base "new" in
  P.Fs.mkdir_p new_tree;
  P.Fs.write_file (Filename.concat new_tree "bin") "#!/bin/sh\nnew\n";
  P.Fs.write_file (Filename.concat new_tree "data.txt") "new-data\n";
  P.Fs.write_file (Filename.concat new_tree "added.txt") "added\n";
  let pkg = Filename.concat base "pkg.tar.gz" in
  (match
     P.Proc.run "tar" [ "-czf"; pkg; "-C"; new_tree; "." ]
   with
   | { P.Proc.status = 0; _ } -> ()
   | r -> Alcotest.failf "tar failed: %s" r.P.Proc.stderr);
  let core, _, _, _, _, _, download_hook, _, _ = scripted_core () in
  (* the fake network hands over the local package; apply+swap are
     the real [Lui_updater] pipeline *)
  download_hook :=
    (fun _progress ~dest -> P.Fs.copy_file ~src:pkg ~dst:dest; Stdlib.Ok ());
  let core =
    {
      core with
      S.apply =
        (fun ~verify ~info ~plan ~package ~bundle ~stage_dir () ->
          U.apply ?verify ~info ~plan ~package ~bundle ~stage_dir ());
      S.swap = (fun st ~target -> U.swap st ~target);
    }
  in
  let s =
    S.create ~core ~feed:fake_feed ~bundle ~exe:"bin"
      ~stage_dir:(Filename.concat base "app.update")
      ~work_dir:(Filename.concat base "dl") ()
  in
  S.check ~user:true s;
  S.install s;
  (match S.status s with
   | S.Ready_to_restart _ -> ()
   | p -> Alcotest.failf "expected ready, got %s" (S.phase_name p));
  Alcotest.(check string) "bin swapped" "#!/bin/sh\nnew\n"
    (P.Fs.read_file (Filename.concat bundle "bin"));
  Alcotest.(check string) "data swapped" "new-data\n"
    (P.Fs.read_file (Filename.concat bundle "data.txt"));
  Alcotest.(check string) "file added" "added\n"
    (P.Fs.read_file (Filename.concat bundle "added.txt"))

(* ------------------------------------------------------------------ *)
(* Strings *)

let test_every_locale_complete () =
  List.iter
    (fun (locale, (s : T.t)) ->
      List.iter
        (fun k ->
          Alcotest.(check bool)
            (Printf.sprintf "%s:%s" locale (T.key_name k))
            true (T.get s k <> ""))
        T.all_keys;
      match T.check s with
      | Stdlib.Ok () -> ()
      | Stdlib.Error m ->
        Alcotest.failf "format arity %s: %s" locale m)
    TR.locales

let test_locale_fallback_to_en () =
  let x = TR.for_locale "xx-NOPE" in
  Alcotest.(check string) "falls back" "en" x.T.lang;
  Alcotest.(check string) "english title"
    (T.get_text en T.Title) (T.get_text x T.Title)

let test_match_language () =
  let avail = List.map fst TR.locales in
  let cases =
    [ ("zh-CN", "zh-CN"); ("zh-Hans-CN", "zh-CN");
      ("zh-TW", "zh-TW"); ("zh-Hant-HK", "zh-TW");
      ("fr-FR", "fr"); ("de-AT", "de"); ("pt-BR", "pt-BR");
      ("pt-PT", "pt-BR");  (* base-language fallback *)
      ("JA_jp", "ja"); ("xx", "en") ]
  in
  List.iter
    (fun (input, expected) ->
      Alcotest.(check string) input expected
        (TR.match_language input avail))
    cases

let test_formats () =
  let x = en in
  Alcotest.(check string) "arity fills"
    "TestApp 2.0.0 is now available—you have 1.0.0. Would you like to install it now?"
    (T.format x T.Available_message [| "TestApp"; "2.0.0"; "1.0.0" |]);
  (* wrong arity falls back to the template instead of crashing *)
  Alcotest.(check bool) "bad arity tolerated" true
    (T.format x T.Available_message [| "only" |] <> "");
  let de = TR.for_locale "de" in
  Alcotest.(check bool) "decimal comma" true
    (String.contains (T.megabytes de 4_200_000) ',')

let test_check_extra_catches_bad_format () =
  let bad = { T.empty with T.available = "broken %[9]s" } in
  Alcotest.(check int) "one bad table" 1
    (List.length (TR.check_extra [ ("xx", bad) ]))

(* ------------------------------------------------------------------ *)
(* View tree shape — mounted against a store-mirroring backend. *)

let demo_backend store =
  {
    Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch =
      (fun batch -> Lui_store.apply_batch store batch; true);
  }

let find_prop_id store kind prop value =
  List.find_map
    (fun n ->
      if Lui_store.node_kind n = kind
         && Lui_store.node_prop n prop = Some (Lui_protocol.StringValue value)
      then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let find_kind_id store kind =
  List.find_map
    (fun n ->
      if Lui_store.node_kind n = kind then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let start_view m =
  let store = Lui_store.create () in
  let app = V.create (demo_backend store) m in
  Alcotest.(check bool) "start" true (Lui_app.start app);
  Alcotest.(check bool) "flush" true (Lui_app.flush app);
  (app, store)

let drive app a =
  ignore (Lui_app.send app a);
  Alcotest.(check bool) "flush" true (Lui_app.flush app)

let test_view_checking () =
  let app, store = start_view (model ()) in
  drive app (S.Check { user = true });
  Alcotest.(check bool) "spinner" true
    (find_kind_id store "spinner" <> None);
  Alcotest.(check bool) "cancel button" true
    (find_prop_id store "button" "text" (T.get_text en T.Cancel) <> None);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app)

let test_view_available () =
  let app, store = start_view (model ()) in
  drive app (S.Check { user = true });
  drive app (S.Checked (Stdlib.Ok (Some (info ()))));
  Alcotest.(check bool) "install button" true
    (find_prop_id store "button" "text" (T.get_text en T.Install) <> None);
  Alcotest.(check bool) "skip button" true
    (find_prop_id store "button" "text" (T.get_text en T.Skip) <> None);
  Alcotest.(check bool) "later button" true
    (find_prop_id store "button" "text" (T.get_text en T.Remind_later) <> None);
  Alcotest.(check bool) "notes scroll" true
    (find_kind_id store "scroll" <> None);
  Alcotest.(check bool) "checkbox" true
    (find_kind_id store "checkbox" <> None);
  Alcotest.(check bool) "version text" true
    (find_prop_id store "text" "text" "2.0.0" <> None);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app)

let test_view_downloading () =
  let app, store = start_view (model ()) in
  drive app (S.Check { user = true });
  drive app (S.Checked (Stdlib.Ok (Some (info ()))));
  drive app S.Install_now;
  drive app
    (S.Progress { received = 2_100_000; total = 4_200_000; at = 1. });
  Alcotest.(check bool) "progress node" true
    (find_kind_id store "progress" <> None);
  Alcotest.(check bool) "percent text" true
    (find_prop_id store "text" "text" "50%" <> None);
  Alcotest.(check bool) "cancel button" true
    (find_prop_id store "button" "text" (T.get_text en T.Cancel) <> None);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app)

let test_view_ready () =
  let app, store = start_view (model ()) in
  drive app (S.Check { user = true });
  drive app (S.Checked (Stdlib.Ok (Some (info ()))));
  drive app S.Install_now;
  let st =
    { U.stage_dir = "/tmp/st"; new_root = "/tmp/st/app"; layout = U.Dir }
  in
  drive app (S.Staged_ok (st, S.offer_of (info ())));
  drive app
    (S.Swapped { S.version = "2.0.0"; exe = "/app/x"; backup = "/b" });
  Alcotest.(check bool) "relaunch button" true
    (find_prop_id store "button" "text" (T.get_text en T.Relaunch) <> None);
  Alcotest.(check bool) "later button" true
    (find_prop_id store "button" "text" (T.get_text en T.Later) <> None);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app)

let test_view_error_retryable () =
  let app, store = start_view (model ()) in
  drive app (S.Check { user = true });
  drive app (S.Checked (Stdlib.Error "offline"));
  Alcotest.(check bool) "retry button" true
    (find_prop_id store "button" "text" (T.get_text en T.Retry) <> None);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app)

(* ------------------------------------------------------------------ *)
(* Window spec *)

let test_window_spec () =
  let m = model () in
  let spec_of phase = V.window_spec { m with S.phase = phase } in
  let st = spec_of (S.Available (S.offer_of (info ()))) in
  Alcotest.(check int) "release window" 620 st.V.width;
  Alcotest.(check bool) "closable" true st.V.closable;
  let st = spec_of S.Checking in
  Alcotest.(check int) "status window" 480 st.V.width;
  Alcotest.(check bool) "checking close is safe" false st.V.aborts_on_close;
  let st =
    spec_of (S.Downloading (S.dl_start (S.offer_of (info ()))))
  in
  Alcotest.(check bool) "download close aborts" true st.V.aborts_on_close

(* ------------------------------------------------------------------ *)
(* Plugin descriptor *)

let test_plugin_services () =
  let module Pl = Lui_plugin_updater_ui.Plugin in
  Alcotest.(check string) "name" "updater" Pl.plugin.Pl.name;
  let svc n = List.assoc n Pl.plugin.Pl.services in
  (* unconfigured: every method reports it *)
  (match svc "status" "" with
   | Stdlib.Error _ -> ()
   | Stdlib.Ok _ -> Alcotest.fail "status before configure");
  let core, _, _, _, _, _, _, _, _ = scripted_core () in
  let s = session_with core in
  Pl.configure_default s;
  (match svc "check" "" with
   | Stdlib.Ok _ -> ()
   | Stdlib.Error m -> Alcotest.fail m);
  (match svc "status" "" with
   | Stdlib.Ok body ->
     Alcotest.(check bool) "phase in json" true
       (has_sub body "\"phase\":\"available\"")
   | Stdlib.Error m -> Alcotest.fail m);
  (* transitions pushed to the poll queue *)
  (match svc "events" "" with
   | Stdlib.Ok body ->
     Alcotest.(check bool) "events json" true
       (String.sub body 0 1 = "[");
   | Stdlib.Error m -> Alcotest.fail m);
  (* drained: second poll is empty *)
  (match svc "events" "" with
   | Stdlib.Ok "[]" -> ()
   | _ -> Alcotest.fail "events not drained")

(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "lui_plugin_updater_ui"
    [
      ( "state machine",
        [
          Alcotest.test_case "idle → available" `Quick
            test_idle_to_available;
          Alcotest.test_case "up-to-date fg vs bg" `Quick
            test_up_to_date_foreground_vs_background;
          Alcotest.test_case "check error retryable" `Quick
            test_check_error_retryable;
          Alcotest.test_case "install flow" `Quick test_install_flow;
          Alcotest.test_case "cancel → offer" `Quick
            test_cancel_returns_to_offer;
          Alcotest.test_case "error keeps offer" `Quick
            test_error_offer_retained_for_retry;
          Alcotest.test_case "verify not retryable" `Quick
            test_verify_error_not_retryable;
          Alcotest.test_case "skip + bg check" `Quick
            test_skip_then_background_check_stays_idle;
          Alcotest.test_case "check mid-download" `Quick
            test_check_ignored_mid_download;
          Alcotest.test_case "dismiss closes" `Quick test_dismiss_closes;
        ] );
      ( "driver (fake core)",
        [
          Alcotest.test_case "install → ready" `Quick
            test_driver_install_ready;
          Alcotest.test_case "staged then install" `Quick
            test_driver_download_stages_then_install;
          Alcotest.test_case "cancel mid-download" `Quick
            test_driver_cancel_mid_download;
          Alcotest.test_case "fail + retry" `Quick
            test_driver_download_failure_and_retry;
          Alcotest.test_case "check failure" `Quick
            test_driver_check_failure;
          Alcotest.test_case "real apply+swap" `Quick
            test_real_apply_and_swap;
        ] );
      ( "strings",
        [
          Alcotest.test_case "locale completeness" `Quick
            test_every_locale_complete;
          Alcotest.test_case "en fallback" `Quick
            test_locale_fallback_to_en;
          Alcotest.test_case "match_language" `Quick test_match_language;
          Alcotest.test_case "formats" `Quick test_formats;
          Alcotest.test_case "check_extra" `Quick
            test_check_extra_catches_bad_format;
        ] );
      ( "view",
        [
          Alcotest.test_case "checking" `Quick test_view_checking;
          Alcotest.test_case "available" `Quick test_view_available;
          Alcotest.test_case "downloading" `Quick test_view_downloading;
          Alcotest.test_case "ready" `Quick test_view_ready;
          Alcotest.test_case "error" `Quick test_view_error_retryable;
          Alcotest.test_case "window spec" `Quick test_window_spec;
        ] );
      ( "plugin",
        [ Alcotest.test_case "services + events" `Quick
            test_plugin_services ] );
    ]
