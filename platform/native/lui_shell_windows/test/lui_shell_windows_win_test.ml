(* Real-call tests for the Windows implementation: clipboard
   round-trips, tray icon lifecycle, notification posting, scheme
   registration and the headless guards around the modal dialogs.
   Runs only on mingw64 (see dune) — every call must either work or
   fail cleanly; nothing may crash. *)

open Lui_shell_windows

let uniq = Printf.sprintf "luitest%d" (Unix.getpid ())

(* ---------- clipboard ---------- *)

let test_clipboard_text () =
  let before = clipboard_change_count () in
  Alcotest.(check bool) "write" true (clipboard_write "hello LUI 世界");
  Alcotest.(check (option string)) "read back"
    (Some "hello LUI 世界") (clipboard_read ());
  Alcotest.(check bool) "count bumped" true
    (clipboard_change_count () > before);
  Alcotest.(check bool) "clear ok" true (clipboard_clear () >= 0);
  Alcotest.(check (option string)) "empty after clear"
    None (clipboard_read ())

let test_clipboard_format () =
  let fmt = Printf.sprintf "lui-test-%s" uniq in
  let read () = Option.map Bytes.to_string (clipboard_read_format fmt) in
  Alcotest.(check bool) "write format" true
    (clipboard_write_format fmt (Bytes.of_string "payload-42"));
  Alcotest.(check (option string)) "read format"
    (Some "payload-42") (read ());
  ignore (clipboard_clear ());
  Alcotest.(check (option string)) "gone after clear" None (read ())

let test_change_count_monotonic () =
  let a = clipboard_change_count () in
  ignore (clipboard_write "x");
  let b = clipboard_change_count () in
  ignore (clipboard_write "y");
  let c = clipboard_change_count () in
  Alcotest.(check bool) "monotonic" true (b > a && c > b)

(* ---------- images ---------- *)

let test_image () =
  (* 2x2 opaque-white RGBA image. *)
  let px = Bytes.make 16 '\xff' in
  match image_of_rgba ~width:2 ~height:2 px with
  | None -> Alcotest.fail "image_of_rgba rejected a valid image"
  | Some img ->
    Alcotest.(check bool) "size" true
      (image_size img = (2.0, 2.0));
    ignore (Gc.full_major ())

(* ---------- status item ---------- *)

let test_status_item () =
  let clicks = ref 0 in
  let picks = ref [] in
  set_status_handler (Some (fun _tag -> incr clicks));
  set_menu_handler (Some (fun id -> picks := id :: !picks));
  let si = status_item_create ~tag:77 () in
  Alcotest.(check int) "tag" 77 si.tag;
  (* Title is the tray tooltip on Windows; icon is a 2x2 white dot. *)
  status_item_set_title si "LUI test";
  status_item_set_image si
    (image_of_rgba ~width:2 ~height:2 (Bytes.make 16 '\xff'));
  status_item_set_on_click si true;
  status_item_set_menu si
    (Some
       (menu
       [ Item { label = "One"; id = 1; enabled = true; checked = false };
         Separator;
         Submenu
           { label = "Sub";
             enabled = true;
             items =
               [ Item
                   { label = "Two"; id = 2; enabled = true;
                     checked = true } ] } ]));
  (* The tray was added lazily inside the calls above; remove must
     never raise, even if the icon was never admitted. *)
  status_item_remove si;
  status_item_remove si; (* idempotent *)
  set_status_handler None;
  set_menu_handler None;
  (* Handlers only fire on real user input; nothing is queued here. *)
  Alcotest.(check int) "no fake clicks" 0 !clicks;
  Alcotest.(check (list int)) "no fake picks" [] !picks

(* ---------- notifications ---------- *)

let test_notify () =
  let posted, detail =
    notify ~id:"lui-test-1" ~title:"LUI test" ~subtitle:"sub"
      ~body:"body text" ()
  in
  if not posted then
    Alcotest.(check bool) "failure explained" true
      (String.length detail > 0);
  set_notification_handler (Some (fun _id -> ()));
  set_notification_handler None

(* ---------- dialogs: never block headless ---------- *)

let test_dialog_guards () =
  if can_present_dialogs () then
    (* An interactive session would show a real dialog and block, so
       the tests do not open one; the guard is what is under test. *)
    Alcotest.(check bool) "presentable" true true
  else (
    Alcotest.(check (option (list string))) "open headless" None
      (open_dialog ());
    Alcotest.(check (option string)) "save headless" None
      (save_dialog ()))

(* ---------- open-url ---------- *)

let test_scheme_lifecycle () =
  let scheme = Printf.sprintf "%s-scheme" uniq in
  let url = scheme ^ "://do/thing" in
  let fired = ref [] in
  set_open_url_handler (Some (fun u -> fired := u :: !fired));
  Alcotest.(check bool) "not yet" false (dispatch_open_url url);
  Alcotest.(check bool) "register" true
    (register_url_scheme ~scheme ~name:"LUI test scheme" ());
  Alcotest.(check bool) "dispatch" true (dispatch_open_url url);
  Alcotest.(check (list string)) "handler got url" [ url ] !fired;
  (* Case-insensitive scheme match, like Win32. *)
  Alcotest.(check bool) "dispatch upper" true
    (dispatch_open_url (String.uppercase_ascii url));
  Alcotest.(check bool) "unregister" true
    (unregister_url_scheme ~scheme ());
  Alcotest.(check bool) "gone" false (dispatch_open_url url);
  set_open_url_handler None

let test_open_url_failures () =
  (* Empty and NUL-carrying URLs are rejected before the shell call;
     a nonexistent path makes ShellExecute report SE_ERR_FNF. An
     unregistered scheme is not tested: the shell may still launch a
     store-lookup UI and report success. *)
  Alcotest.(check bool) "empty" false (open_url "");
  Alcotest.(check bool) "nul" false (open_url "x\000y");
  Alcotest.(check bool) "missing file" false
    (open_url "C:\\lui-nonexistent-dir\\missing.luixyz")

(* ---------- message pump ---------- *)

let test_pump () =
  Alcotest.(check bool) "non-negative" true (pump_pending () >= 0)

let () =
  let open Alcotest in
  run "lui_shell_windows_win"
    [ ( "clipboard",
        [ test_case "text round-trip" `Quick test_clipboard_text;
          test_case "named format" `Quick test_clipboard_format;
          test_case "change count" `Quick test_change_count_monotonic
        ] );
      ("images", [ test_case "rgba -> icon" `Quick test_image ]);
      ( "status item",
        [ test_case "lifecycle" `Quick test_status_item ] );
      ("notify", [ test_case "post or explain" `Quick test_notify ]);
      ( "dialogs",
        [ test_case "headless guard" `Quick test_dialog_guards ] );
      ( "open-url",
        [ test_case "scheme lifecycle" `Quick test_scheme_lifecycle;
          test_case "failures" `Quick test_open_url_failures ] );
      ("pump", [ test_case "pump_pending" `Quick test_pump ]) ]
