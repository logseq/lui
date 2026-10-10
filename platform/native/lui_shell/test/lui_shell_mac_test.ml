(* Real-call tests on macOS: the parts that are safe without a run
   loop or an .app bundle — clipboard roundtrip, activation policy,
   image construction, menu/status-item objects, and the graceful
   degradation paths for notifications and dialogs. The interactive
   paths (menu clicks, panel presentation, delivered notifications)
   need a running app and are covered manually. *)

open Lui_shell

let item ?(id = 1) ?(enabled = true) ?(checked = false) label =
  Item { label; id; enabled; checked }

(* ---------- clipboard ---------- *)

let test_clipboard_roundtrip () =
  let stamp = Printf.sprintf "lui-shell-test-%d" (Unix.getpid ()) in
  Alcotest.(check bool) "write ok" true (clipboard_write stamp);
  Alcotest.(check (option string)) "read back" (Some stamp)
    (clipboard_read ())

let test_change_count () =
  let before = clipboard_change_count () in
  Alcotest.(check bool) "has pasteboard" true (before >= 0);
  ignore (clipboard_write "lui-shell-count-1");
  let mid = clipboard_change_count () in
  Alcotest.(check bool) "write bumps count" true (mid > before);
  let after = clipboard_clear () in
  Alcotest.(check bool) "clear bumps count" true (after >= mid)

(* ---------- app identity ---------- *)

let test_activation_policy () =
  Alcotest.(check bool) "set accessory" true
    (set_activation_policy Accessory);
  Alcotest.(check bool) "get accessory" true
    (activation_policy () = Some Accessory);
  Alcotest.(check bool) "set regular" true
    (set_activation_policy Regular);
  Alcotest.(check bool) "get regular" true
    (activation_policy () = Some Regular)

let test_misc_identity () =
  (* None of these needs a run loop; success depends on the session. *)
  set_app_name "lui-test";
  set_dock_badge (Some "3");
  set_dock_badge None;
  let _ = request_user_attention () in
  let _ = request_user_attention ~critical:true () in
  (* No windows exist in a test binary. *)
  Alcotest.(check bool) "no window headless" false
    (set_window_title "x")

(* ---------- image ---------- *)

let red_square w h =
  let px = Bytes.create (w * h * 4) in
  for i = 0 to w * h - 1 do
    Bytes.set px (i * 4) '\255';
    Bytes.set px (i * 4 + 3) '\255'
  done;
  px

let test_image () =
  match image_of_rgba ~width:4 ~height:3 (red_square 4 3) with
  | None -> Alcotest.fail "image_of_rgba returned None"
  | Some img ->
    let w, h = image_size img in
    Alcotest.(check (float 0.01)) "w" 4.0 w;
    Alcotest.(check (float 0.01)) "h" 3.0 h

(* ---------- menus + status item ---------- *)

let test_menu_bar () =
  let base = app_menu_count () in
  let m =
    menu ~title:"lui-test"
      [ item ~id:42 "Do it";
        Separator;
        Submenu { label = "More"; enabled = true;
                  items = [ item ~id:43 "Deep" ] } ]
  in
  Alcotest.(check bool) "insert" true (app_menu_insert m ~at:0);
  Alcotest.(check int) "count" (base + 1) (app_menu_count ());
  Alcotest.(check bool) "remove" true (app_menu_remove ~at:0);
  Alcotest.(check int) "count back" base (app_menu_count ());
  (* Out-of-range removal is a clean false, not a crash. *)
  Alcotest.(check bool) "remove oob" false (app_menu_remove ~at:99)

let test_status_item () =
  let si = status_item_create ~tag:7 () in
  Alcotest.(check int) "tag" 7 si.tag;
  status_item_set_title si "L";
  (match image_of_rgba ~width:8 ~height:8 (red_square 8 8) with
   | Some img -> status_item_set_image si (Some img)
   | None -> Alcotest.fail "icon image failed");
  status_item_set_image si None;
  status_item_set_menu si
    (Some (menu [ item ~id:9 "Entry"; Separator ]));
  status_item_set_menu si None;
  status_item_set_on_click si true;
  status_item_set_on_click si false;
  status_item_remove si

(* ---------- notifications ---------- *)

let test_notify_unbundled () =
  (* A test executable has no bundle id: the call must degrade, not
     crash. Inside a real .app it posts instead. *)
  let posted, detail =
    notify ~id:"lui-test-1" ~title:"Hello" ~body:"world" ()
  in
  if posted then
    Alcotest.(check bool) "detail names path" true (String.length detail > 0)
  else
    Alcotest.(check bool) "explains why" true (String.length detail > 0)

(* ---------- dialogs ---------- *)

let test_dialogs_headless () =
  Alcotest.(check bool) "cannot present" false (can_present_dialogs ());
  Alcotest.(check bool) "open dialog none" true
    (open_dialog () = None);
  Alcotest.(check bool) "open dialog args none" true
    (open_dialog ~dirs:true ~files:false ~multi:true
       ~filters:[ ".md"; "txt" ] ()
     = None);
  Alcotest.(check bool) "save dialog none" true
    (save_dialog ~default_name:"a.txt" () = None)

(* ---------- open-url ---------- *)

let test_install_open_url () =
  Alcotest.(check bool) "registers" true (install_open_url_handler ())

(* ---------- handler registration ---------- *)

let test_handler_registration () =
  (* Registration itself never reaches the OS; the handlers fire only
     when a real event arrives on the main thread. *)
  set_menu_handler (Some (fun _ -> ()));
  set_status_handler (Some (fun _ -> ()));
  set_notification_handler (Some (fun _ -> ()));
  set_open_url_handler (Some (fun _ -> ()));
  set_menu_handler None;
  set_status_handler None;
  set_notification_handler None;
  set_open_url_handler None

let () =
  let open Alcotest in
  run "lui_shell_mac"
    [ ( "clipboard",
        [ test_case "roundtrip" `Quick test_clipboard_roundtrip;
          test_case "change count" `Quick test_change_count ] );
      ( "app identity",
        [ test_case "activation policy" `Quick test_activation_policy;
          test_case "misc" `Quick test_misc_identity ] );
      ( "image", [ test_case "rgba" `Quick test_image ] );
      ( "menus",
        [ test_case "menu bar" `Quick test_menu_bar;
          test_case "status item" `Quick test_status_item ] );
      ( "notifications",
        [ test_case "unbundled" `Quick test_notify_unbundled ] );
      ( "dialogs",
        [ test_case "headless none" `Quick test_dialogs_headless ] );
      ( "open-url",
        [ test_case "install" `Quick test_install_open_url;
          test_case "handlers" `Quick test_handler_registration ] ) ]
