(* Tests for Lui_updater. Two layers:

   - pure: version compare, manifest parsing, plan, the state machine,
     URL policy, check cadence — these run everywhere;
   - e2e: real staged-apply + swap + rollback + relaunch round-trips on
     fabricated app bundles, fed by file:// URLs through the real curl
     fetcher and by an injected fetcher. No test touches the network:
     http URLs stay on the loopback python server. *)

module U = Lui_updater
module L = Lui_pkg
module P = Lui_pkg.Private

let check = Alcotest.check
let string = Alcotest.string
let int = Alcotest.int
let bool = Alcotest.bool

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui_upd_test-" ()

let write ?(perm = 0o644) path data =
  P.Fs.mkdir_p (Filename.dirname path);
  P.Fs.write_file ~perm path data

(* A fabricated .app: the minimum structure a bundle needs for the
   updater — an Info.plist and an executable that records its own
   invocation into a marker file. *)
let make_app dir name ~version ~exe_body =
  let app = Filename.concat dir (name ^ ".app") in
  write
    (Filename.concat app "Contents/Info.plist")
    (Printf.sprintf
       "<?xml version=\"1.0\"?>\n\
        <plist version=\"1.0\"><dict>\n\
        <key>CFBundleIdentifier</key><string>com.devin.%s</string>\n\
        <key>CFBundleShortVersionString</key><string>%s</string>\n\
        </dict></plist>\n"
       (String.lowercase_ascii name) version);
  write ~perm:0o755
    (Filename.concat app "Contents/MacOS/" ^ String.lowercase_ascii name)
    exe_body;
  write (Filename.concat app "Contents/Resources/data.txt")
    (Printf.sprintf "resources of %s %s\n" name version);
  app

let marker_script version =
  Printf.sprintf
    "#!/bin/sh\nprintf '%s:%%s\\n' \"$0\" >> \"${LUI_UPD_MARKER}\"\n" version

(* A fetcher that serves file:// URLs from disk — the injected seam
   any headless caller uses. *)
let file_fetcher =
  {
    U.get =
      (fun ~url ~dest ->
        match String.length url >= 7 && String.sub url 0 7 = "file://" with
        | false -> Error "file_fetcher: not a file URL"
        | true ->
          let src = String.sub url 7 (String.length url - 7) in
          if P.Fs.exists src then begin
            P.Fs.copy_file ~src ~dst:dest;
            Stdlib.Ok ()
          end
          else Error ("no such file: " ^ src));
  }

let sha256_file = P.Sha256.file
let file_url path = "file://" ^ path

let manifest ~version ~archive ~deltas =
  let art a =
    Printf.sprintf
      "\"url\": %S, \"size\": %d, \"sha256\": %S%s" a.U.url a.U.size
      a.U.sha256
      (match a.U.signature with
       | None -> ""
       | Some s -> Printf.sprintf ", \"signature\": %S" s)
  in
  let djs =
    match deltas with
    | [] -> ""
    | ds ->
      Printf.sprintf ", \"deltas\": [%s]"
        (String.concat ", "
           (List.map
              (fun (from, a) ->
                 Printf.sprintf "{ \"from\": %S, %s }" from (art a))
              ds))
  in
  Printf.sprintf "{ \"version\": %S, \"notes\": \"n\", %s%s }" version
    (art archive) djs

let artifact_of_file path url =
  {
    U.url;
    size = (Unix.stat path).Unix.st_size;
    sha256 = sha256_file path;
    signature = None;
  }

(* Builds old/new app trees, a delta and a full package, and a feed
   dir holding stable.json. Returns (feed_dir, old_app_src, new_app,
   delta, full_pkg). *)
let fixture ~with_delta =
  let base = tmp_dir () in
  let old_src = Filename.concat base "old" in
  let new_src = Filename.concat base "new" in
  P.Fs.mkdir_p old_src;
  P.Fs.mkdir_p new_src;
  let old_app =
    make_app old_src "MyApp" ~version:"1.0" ~exe_body:(marker_script "v1")
  in
  let new_app =
    make_app new_src "MyApp" ~version:"2.0" ~exe_body:(marker_script "v2")
  in
  (* a changed data file so the delta has real work *)
  write (Filename.concat new_app "Contents/Resources/data.txt")
    "resources of MyApp 2.0 — bigger payload\n";
  let feed = Filename.concat base "feed" in
  P.Fs.mkdir_p feed;
  let pkg = Filename.concat base "pkg.tar.gz" in
  let r =
    P.Proc.run "tar" [ "-czf"; pkg; "-C"; new_src; "MyApp.app" ]
  in
  Alcotest.(check int) "tar full pkg" 0 r.status;
  let full = artifact_of_file pkg (file_url pkg) in
  let deltas =
    if with_delta then begin
      let delta = Filename.concat base "u.delta" in
      (match
         L.update_pkg ~from:"1.0" ~to_:"2.0" ~old_dir:old_app
           ~new_dir:new_app delta
       with
       | L.Ok () -> ()
       | o ->
         Alcotest.failf "update_pkg: %s"
           (L.string_of_outcome (fun () -> "ok") o));
      [ ("1.0", artifact_of_file delta (file_url delta)) ]
    end
    else []
  in
  write (Filename.concat feed "stable.json")
    (manifest ~version:"2.0" ~archive:full ~deltas);
  (base, old_app, new_app, feed)

let feed_of feed_dir ~version =
  {
    U.base_url = file_url feed_dir;
    channel = U.Stable;
    app_id = "com.devin.myapp";
    app_name = "MyApp";
    version;
  }

let installed_copy dir old_app =
  (* The "installed" bundle: a copy of the old app, so applying an
     update never touches the fixture. *)
  let target = Filename.concat dir "MyApp.app" in
  P.Fs.mkdir_p (Filename.dirname target);
  P.Fs.install ~src:old_app ~dst:target;
  target

let read_plist_version app =
  let s = P.Fs.read_file (Filename.concat app "Contents/Info.plist") in
  let key = "CFBundleShortVersionString</key><string>" in
  let kl = String.length key in
  let rec find i =
    if i + kl > String.length s then None
    else if String.sub s i kl = key then Some i
    else find (i + 1)
  in
  match find 0 with
  | Some i -> (
    let start = i + kl in
    match String.index_from_opt s start '<' with
    | Some e -> String.sub s start (e - start)
    | None -> "?")
  | None -> "?"

(* ------------------------------------------------------------ pure *)

let test_compare_version () =
  let cmp a b = U.compare_version a b in
  check bool "1.2.3 < 1.2.10" true (cmp "1.2.3" "1.2.10" < 0);
  check int "equal" 0 (cmp "1.2.0" "1.2.0");
  check int "v prefix" 0 (cmp "v1.2.0" "1.2.0");
  check int "build ignored" 0 (cmp "1.2.0+99" "1.2.0+1");
  check bool "pre < release" true (cmp "1.0.0-beta.1" "1.0.0" < 0);
  check bool "beta < beta.2" true (cmp "1.0.0-beta" "1.0.0-beta.2" < 0);
  check bool "numbers < words" true (cmp "1.0.0-2" "1.0.0-rc" < 0);
  check bool "1.9 < 1.10" true (cmp "1.9" "1.10" < 0);
  check bool "2.0 > 1.99" true (cmp "2.0" "1.99" > 0)

let test_feed_url () =
  let f = { (feed_of "/srv/u" ~version:"1.0") with U.base_url = "/srv/u" } in
  check string "stable" "/srv/u/stable.json" (U.feed_url f);
  check string "beta" "/srv/u/beta.json"
    (U.feed_url { f with U.channel = U.Beta });
  check string "named" "/srv/u/nightly.json"
    (U.feed_url { f with U.channel = U.Named "nightly" })

let test_manifest_parse () =
  let a =
    {
      U.url = "https://x/a.tgz";
      size = 5;
      sha256 = String.make 64 'a';
      signature = None;
    }
  in
  (match
     U.manifest_of_string
       (manifest ~version:"2.0" ~archive:a ~deltas:[ ("1.0", a) ])
   with
   | Stdlib.Ok i ->
     check string "version" "2.0" i.U.version;
     check int "deltas" 1 (List.length i.U.deltas)
   | Error m -> Alcotest.failf "manifest: %s" m);
  (match U.manifest_of_string "{ \"url\": \"x\" }" with
   | Error _ -> ()
   | Stdlib.Ok _ -> Alcotest.fail "no-version manifest accepted");
  (match U.manifest_of_string "not json {" with
   | Error _ -> ()
   | Stdlib.Ok _ -> Alcotest.fail "bad json accepted");
  (match
     U.manifest_of_string
       "{ \"version\": \"2.0\", \"url\": \"x\", \"size\": 1,\
        \ \"sha256\": \"abc\" }"
   with
   | Error _ -> ()
   | Stdlib.Ok _ -> Alcotest.fail "short sha256 accepted");
  (* a malformed delta entry is skipped, not fatal *)
  (match
     U.manifest_of_string
       "{ \"version\": \"2.0\", \"url\": \"u\", \"size\": 1,\
        \ \"sha256\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\
        \ \"deltas\": [ {\"from\": \"1.0\"} ] }"
   with
   | Stdlib.Ok i -> check int "bad delta skipped" 0 (List.length i.U.deltas)
   | Error m -> Alcotest.failf "manifest: %s" m)

let test_plan () =
  let a =
    {
      U.url = "u";
      size = 1;
      sha256 = String.make 64 'b';
      signature = None;
    }
  in
  let d = { U.from = "1.0"; artifact = a } in
  let i =
    { U.version = "2.0"; notes = ""; date = ""; archive = a;
      deltas = [ d ] }
  in
  (match U.plan i ~current:"1.0" with
   | U.Delta dd -> check string "delta from" "1.0" dd.U.from
   | U.Full _ -> Alcotest.fail "delta not chosen");
  (match U.plan i ~current:"0.9" with
   | U.Full _ -> ()
   | U.Delta _ -> Alcotest.fail "delta chosen for wrong base")

let test_state_machine () =
  let info =
    {
      U.version = "2.0";
      notes = "";
      date = "";
      archive =
        { U.url = "u"; size = 7; sha256 = String.make 64 'c';
          signature = None };
      deltas = [];
    }
  in
  let st = U.step U.Idle U.Begin_check in
  (match st with
   | U.Checking -> ()
   | _ -> Alcotest.fail "idle->checking");
  let st = U.step st (U.Checked (Some info)) in
  (match st with
   | U.Available i -> check string "info" "2.0" i.U.version
   | _ -> Alcotest.fail "checking->available");
  let st = U.step st (U.Begin_download info) in
  (match st with
   | U.Downloading { U.total; _ } -> check int "total" 7 total
   | _ -> Alcotest.fail "available->downloading");
  let st =
    U.step st (U.Progress { U.received = 3; U.total = 7 })
  in
  let st = U.step st (U.Staged "/tmp/x") in
  (match st with
   | U.Ready "/tmp/x" -> ()
   | _ -> Alcotest.fail "downloading->ready");
  let st = U.step st (U.Applied_to "/apps/x") in
  (match st with
   | U.Applied -> ()
   | _ -> Alcotest.fail "ready->applied");
  (* error path and retry *)
  let st = U.step U.Checking (U.Failed "boom") in
  (match st with
   | U.Error "boom" -> ()
   | _ -> Alcotest.fail "failed->error");
  (match U.step st U.Begin_check with
   | U.Checking -> ()
   | _ -> Alcotest.fail "error retry");
  (* up-to-date check returns to idle; nonsense transitions no-op *)
  (match U.step U.Checking (U.Checked None) with
   | U.Idle -> ()
   | _ -> Alcotest.fail "no update -> idle");
  (match U.step U.Idle (U.Progress { U.received = 1; U.total = 2 }) with
   | U.Idle -> ()
   | _ -> Alcotest.fail "invalid transition changed state")

let test_url_policy () =
  check bool "https" true (U.url_allowed "https://a.com/u.json");
  check bool "file" true (U.url_allowed "file:///tmp/u.json");
  check bool "http loopback" true
    (U.url_allowed "http://127.0.0.1:8000/u.json");
  check bool "http localhost" true
    (U.url_allowed "http://localhost:9/u.json");
  check bool "http remote" false (U.url_allowed "http://a.com/u.json");
  check bool "ftp" false (U.url_allowed "ftp://a.com/x");
  check bool "no scheme" false (U.url_allowed "a.com/x")

let test_next_check () =
  let day = 86400. in
  check bool "due = last + interval" true
    (U.next_check ~last:1000. ~failed:0. ~interval:day ~now:5000.
     = 1000. +. day);
  check bool "failure retries sooner" true
    (U.next_check ~last:1000. ~failed:4000. ~interval:day ~now:5000.
     = 4000. +. 3600.);
  check bool "clock skew clamps last" true
    (U.next_check ~last:9000. ~failed:0. ~interval:day ~now:5000.
     = 5000. +. day)

let test_check_injected () =
  let dir = tmp_dir () in
  let a =
    {
      U.url = "file:///x/pkg.tgz";
      size = 9;
      sha256 = String.make 64 'd';
      signature = None;
    }
  in
  write (Filename.concat dir "stable.json")
    (manifest ~version:"2.0" ~archive:a ~deltas:[]);
  let f = feed_of dir ~version:"1.0" in
  (match U.check ~fetch:file_fetcher f with
   | Stdlib.Ok (Some i) -> check string "newer" "2.0" i.U.version
   | _ -> Alcotest.fail "check should find 2.0");
  (match U.check ~fetch:file_fetcher { f with U.version = "2.0" } with
   | Stdlib.Ok None -> ()
   | _ -> Alcotest.fail "same version should be up to date");
  (match U.check ~fetch:file_fetcher { f with U.version = "3.0" } with
   | Stdlib.Ok None -> ()
   | _ -> Alcotest.fail "older feed should be up to date")

let test_install_target () =
  if L.host_platform () = L.Macos then begin
    let dir = tmp_dir () in
    let app =
      make_app dir "Tgt" ~version:"1.0" ~exe_body:(marker_script "v1")
    in
    let exe =
      Filename.concat app "Contents/MacOS/" ^ "tgt"
    in
    match U.install_target_of ~exe with
    | Stdlib.Ok b -> check string "bundle" app b
    | Error m -> Alcotest.failf "install_target: %s" m
  end

(* ------------------------------------------------------------- e2e *)

(* install from a file:// feed through the real curl subprocess:
   delta-first plan → Lui_pkg.apply_delta into <bundle>.update →
   rename-dance swap → backup reported → rollback restores. *)
let test_delta_install () =
  let base, old_app, _new_app, feed_dir = fixture ~with_delta:true in
  let target = installed_copy (Filename.concat base "live") old_app in
  let states = ref [] in
  let f = feed_of feed_dir ~version:"1.0" in
  let report =
    U.install ~fetch:file_fetcher
      ~on_state:(fun s -> states := s :: !states)
      f ~bundle:target ~exe:"Contents/MacOS/myapp"
  in
  let backup =
    match report with
    | U.Installed { version; backup; _ } ->
      check string "version" "2.0" version;
      check bool "backup exists" true (P.Fs.exists backup);
      backup
    | U.Up_to_date -> Alcotest.fail "expected install, got up-to-date"
    | U.Install_failed m -> Alcotest.failf "install failed: %s" m
  in
  check string "now runs 2.0" "2.0" (read_plist_version target);
  check string "new payload" "resources of MyApp 2.0 — bigger payload\n"
    (P.Fs.read_file (Filename.concat target "Contents/Resources/data.txt"));
  check bool "stage cleaned" false (P.Fs.exists (target ^ ".update"));
  check bool "exe bit" true
    (((Unix.stat (Filename.concat target "Contents/MacOS/myapp")).Unix
      .st_perm
      land 0o111)
     <> 0);
  (* the state walk observed the full pipeline *)
  check bool "saw checking" true
    (List.exists (fun s -> s = U.Checking) !states);
  check bool "saw applied" true
    (List.exists (fun s -> s = U.Applied) !states);
  (* rollback puts 1.0 back *)
  (match U.rollback ~backup ~target with
   | Error m -> Alcotest.failf "rollback: %s" m
   | Stdlib.Ok () ->
     check string "rolled back" "1.0" (read_plist_version target));
  U.cleanup_backup backup

(* full package path: feed without deltas → untar into stage → swap *)
let test_full_install () =
  let base, old_app, _new_app, feed_dir = fixture ~with_delta:false in
  let target = installed_copy (Filename.concat base "live") old_app in
  let f = feed_of feed_dir ~version:"1.0" in
  match U.install ~fetch:file_fetcher f ~bundle:target
          ~exe:"Contents/MacOS/myapp" with
  | U.Installed { version; _ } ->
    check string "version" "2.0" version;
    check string "now runs 2.0" "2.0" (read_plist_version target)
  | U.Up_to_date -> Alcotest.fail "expected install"
  | U.Install_failed m -> Alcotest.failf "install failed: %s" m

(* a delta that can't rebuild the app (wrong base content) falls back
   to the full archive once — progress restarts. *)
let test_delta_fallback () =
  let base, old_app, new_app, feed_dir = fixture ~with_delta:true in
  let target = installed_copy (Filename.concat base "live") old_app in
  (* corrupt the installed copy so the delta's sha checks fail *)
  write
    (Filename.concat target "Contents/Resources/data.txt")
    "tampered\n";
  let f = feed_of feed_dir ~version:"1.0" in
  let progress_seen = ref 0 in
  (match
     U.install ~fetch:file_fetcher
       ~progress:(fun ~received:_ ~total:_ -> incr progress_seen)
       f ~bundle:target ~exe:"Contents/MacOS/myapp"
   with
   | U.Installed { version; _ } -> check string "version" "2.0" version
   | U.Up_to_date -> Alcotest.fail "expected install"
   | U.Install_failed m -> Alcotest.failf "install failed: %s" m);
  check string "now runs 2.0" "2.0" (read_plist_version target);
  check string "payload" (P.Fs.read_file (Filename.concat new_app "Contents/Resources/data.txt"))
    (P.Fs.read_file (Filename.concat target "Contents/Resources/data.txt"));
  check bool "progress fired" true (!progress_seen >= 2)

(* curl's file:// path is real too — same pipeline, default fetcher. *)
let test_curl_file_fetch () =
  let base, old_app, _new_app, feed_dir = fixture ~with_delta:true in
  let target = installed_copy (Filename.concat base "live") old_app in
  let f = feed_of feed_dir ~version:"1.0" in
  match U.install f ~bundle:target ~exe:"Contents/MacOS/myapp" with
  | U.Installed { version; _ } ->
    check string "version" "2.0" version;
    check string "now runs 2.0" "2.0" (read_plist_version target)
  | U.Up_to_date -> Alcotest.fail "expected install"
  | U.Install_failed m -> Alcotest.failf "install failed: %s" m

(* http:// over loopback: a python file server + default curl. *)
let test_http_loopback () =
  let base, old_app, _new_app, feed_dir = fixture ~with_delta:true in
  let target = installed_copy (Filename.concat base "live") old_app in
  (* pick a free port, then hand it to the server *)
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port =
    match Unix.getsockname sock with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> 18765
  in
  Unix.close sock;
  let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
  let pid =
    Unix.create_process "python3"
      [| "python3"; "-m"; "http.server"; string_of_int port;
         "--bind"; "127.0.0.1"; "-d"; feed_dir |]
      devnull devnull devnull
  in
  (* wait for the server to answer *)
  let rec wait n =
    let r =
      P.Proc.run "curl"
        [ "-fsS"; "-o"; "/dev/null";
          Printf.sprintf "http://127.0.0.1:%d/stable.json" port ]
    in
    if r.status = 0 then true
    else if n = 0 then false
    else begin
      Unix.sleepf 0.1;
      wait (n - 1)
    end
  in
  let up = wait 50 in
  check bool "server up" true up;
  let f = { (feed_of feed_dir ~version:"1.0") with
            U.base_url = Printf.sprintf "http://127.0.0.1:%d" port } in
  (match U.install f ~bundle:target ~exe:"Contents/MacOS/myapp" with
   | U.Installed { version; _ } -> check string "version" "2.0" version
   | U.Up_to_date -> Alcotest.fail "expected install"
   | U.Install_failed m -> Alcotest.failf "install failed: %s" m);
  check string "now runs 2.0" "2.0" (read_plist_version target);
  Unix.kill pid Sys.sigterm;
  ignore (Unix.waitpid [] pid)

(* the relaunch half: install_and_relaunch in a forked child exits 0
   and the NEW bundle's executable runs (it records its own path). *)
let test_install_and_relaunch () =
  if L.host_platform () = L.Macos then begin
    let base, old_app, _new_app, feed_dir = fixture ~with_delta:true in
    let target = installed_copy (Filename.concat base "live") old_app in
    let marker = Filename.concat base "marker" in
    Unix.putenv "LUI_UPD_MARKER" marker;
    let f = feed_of feed_dir ~version:"1.0" in
    let exe = "Contents/MacOS/myapp" in
    let pid = Unix.fork () in
    if pid = 0 then begin
      (* child: install_and_relaunch exits 0 on success *)
      (match
         U.install_and_relaunch ~fetch:file_fetcher f ~bundle:target
           ~exe ~args:[]
       with
       | U.Installed _ -> exit 1 (* unreachable: it exits itself *)
       | _ -> exit 2)
    end;
    let _, st = Unix.waitpid [] pid in
    check bool "child exited 0" true (st = Unix.WEXITED 0);
    (* the detached child writes the marker asynchronously *)
    let rec wait_marker n =
      if P.Fs.exists marker then true
      else if n = 0 then false
      else begin
        Unix.sleepf 0.1;
        wait_marker (n - 1)
      end
    in
    check bool "marker written" true (wait_marker 50);
    let content = P.Fs.read_file marker in
    let want = Printf.sprintf "v2:%s\n" (Filename.concat target exe) in
    check string "new exe ran" want content;
    check string "swapped to 2.0" "2.0" (read_plist_version target)
  end

let () =
  Alcotest.run "lui_updater"
    [
      ( "unit",
        [
          Alcotest.test_case "compare_version" `Quick test_compare_version;
          Alcotest.test_case "feed_url" `Quick test_feed_url;
          Alcotest.test_case "manifest" `Quick test_manifest_parse;
          Alcotest.test_case "plan delta-first" `Quick test_plan;
          Alcotest.test_case "state machine" `Quick test_state_machine;
          Alcotest.test_case "url policy" `Quick test_url_policy;
          Alcotest.test_case "next_check" `Quick test_next_check;
          Alcotest.test_case "check (injected)" `Quick test_check_injected;
          Alcotest.test_case "install_target" `Quick test_install_target;
        ] );
      ( "e2e",
        [
          Alcotest.test_case "delta install+rollback" `Quick
            test_delta_install;
          Alcotest.test_case "full install" `Quick test_full_install;
          Alcotest.test_case "delta->full fallback" `Quick
            test_delta_fallback;
          Alcotest.test_case "curl file://" `Quick test_curl_file_fetch;
          Alcotest.test_case "http loopback" `Quick test_http_loopback;
          Alcotest.test_case "install+relaunch" `Quick
            test_install_and_relaunch;
        ] );
    ]
