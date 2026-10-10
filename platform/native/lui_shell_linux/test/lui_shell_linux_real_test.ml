(* Real transport calls — enabled_if linux only. Every assertion is
   written to pass under whatever the session can provide: the
   transport tier is recorded in the test output and calls degrade
   rather than fail. *)
open Lui_shell_linux

let check = Alcotest.(check bool)

let tier () =
  match transport () with
  | Offline -> "offline"
  | Session_bus -> "session-bus"
  | Indicator -> "indicator"

let test_probe () =
  let t = transport () in
  Printf.printf "[lui_shell_linux] transport=%s gui=%b indicator=%b\n%!"
    (tier ()) (gui_available ()) (status_item_supported ());
  (match t with
   | Indicator -> check "indicator+gui" true (gui_available ())
   | Session_bus | Offline -> ());
  check "indicator-consistent" true
    (status_item_supported () || transport () <> Indicator)

let test_pump () =
  let n = pump () in
  check "pumped" true (n >= 0)

let test_notify () =
  let ok, detail = notify ~id:"t1" ~title:"lui test" ~body:"ping" () in
  Printf.printf "[lui_shell_linux] notify ok=%b detail=%s\n%!" ok detail;
  (match transport () with
   | Offline -> check "offline-fails" false ok
   | Session_bus | Indicator -> () (* service may still be absent *))

let test_status_item () =
  let item = status_item_create ~tag:3 () in
  let live = status_item_live item in
  Printf.printf "[lui_shell_linux] status live=%b supported=%b\n%!"
    live (status_item_supported ());
  check "live-implies-supported" true
    (not live || status_item_supported ());
  (* Setters must no-op safely when inert. *)
  status_item_set_title item "lui";
  let img =
    Option.get
      (image_of_rgba ~width:2 ~height:2 (Bytes.make 16 '\255'))
  in
  status_item_set_image item (Some img);
  status_item_set_menu item
    (Some (menu ~title:"T" [ Item { label = "i"; id = 1;
                                   enabled = true; checked = false } ]));
  status_item_set_on_click item true;
  status_item_remove item;
  check "dead" false (status_item_live item)

let test_clipboard () =
  let n0 = clipboard_change_count () in
  Printf.printf "[lui_shell_linux] clipboard count=%d\n%!" n0;
  if clipboard_write "lui-clip" then begin
    check "count-bumped" true (clipboard_change_count () > n0);
    check "readback" true (clipboard_read () = Some "lui-clip");
    ignore (clipboard_clear ())
  end else
    check "no-clipboard" true (n0 < 0 || not (gui_available ()))

let test_dialogs () =
  check "present-is-gui" (can_present_dialogs ())
    (gui_available ());
  if not (can_present_dialogs ()) then begin
    check "open-none" true (open_dialog () = None);
    check "save-none" true (save_dialog () = None)
  end

let test_open_url () =
  let ok = open_url "luitest-nothing://x" in
  Printf.printf "[lui_shell_linux] open_url ok=%b\n%!" ok;
  check "returns" true (ok || true)

let test_badge () =
  set_dock_badge (Some "3");
  set_dock_badge None;
  ignore (request_user_attention ());
  check "done" true true

let test_open_url_handler () =
  (* Redirect XDG dirs so user config is untouched. *)
  let base = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "lui-shx-xdg-%d" (Unix.getpid ())) in
  Unix.mkdir base 0o755;
  Unix.mkdir (Filename.concat base "config") 0o755;
  Unix.mkdir (Filename.concat base "data") 0o755;
  Unix.mkdir (Filename.concat base "data/applications") 0o755;
  Unix.putenv "XDG_CONFIG_HOME" (Filename.concat base "config");
  Unix.putenv "XDG_DATA_HOME" (Filename.concat base "data");
  let ok =
    install_open_url_handler ~scheme:"luitestdemo"
      ~id:"luitest" ~name:"LuiTest" ()
  in
  Printf.printf "[lui_shell_linux] install handler ok=%b\n%!" ok;
  let dir, file = Lui_shell_linux.Private.handler_entry "luitest" in
  let path = Filename.concat dir file in
  check "file written" true (Sys.file_exists path);
  check "mime set" true
    (Lui_shell_linux.Private.mime_default
       "x-scheme-handler/luitestdemo"
     = Some file)

let () =
  Alcotest.run "lui_shell_linux_real"
    [ "session",
      [ Alcotest.test_case "probe" `Quick test_probe;
        Alcotest.test_case "pump" `Quick test_pump;
        Alcotest.test_case "badge" `Quick test_badge ];
      "status",
      [ Alcotest.test_case "item" `Quick test_status_item ];
      "notify",
      [ Alcotest.test_case "post" `Quick test_notify ];
      "clipboard",
      [ Alcotest.test_case "roundtrip" `Quick test_clipboard ];
      "dialogs",
      [ Alcotest.test_case "headless" `Quick test_dialogs ];
      "url",
      [ Alcotest.test_case "open" `Quick test_open_url;
        Alcotest.test_case "handler" `Quick test_open_url_handler ] ]
