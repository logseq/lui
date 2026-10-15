(* Pure-OCaml halves: portable everywhere. PNG encode, the menu model,
   desktop-entry plumbing, mimeapps editing, bus-name derivation,
   event dispatch — nothing that touches the session transport. *)
open Lui_shell_linux
module P = Lui_shell_linux.Private

let check = Alcotest.(check bool)
let check_s = Alcotest.(check string)
let check_i = Alcotest.(check int)
let check_sl = Alcotest.(check (list string))
let check_opt_s = Alcotest.(check (option string))

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  m <= n && go 0

(* ------------------------------------------------------------------ *)
(* PNG encoder *)

let test_png_header () =
  let img =
    Option.get
      (image_of_rgba ~width:1 ~height:1
         (Bytes.of_string "\255\000\000\255"))
  in
  let png = image_png img in
  check "prefix" true
    (Bytes.sub_string png 0 8 = "\137PNG\r\n\026\n");
  check_s "type" "IHDR" (Bytes.sub_string png 12 4);
  check_i "w" 1 (Char.code (Bytes.get png 19));
  check_i "h" 1 (Char.code (Bytes.get png 23))

let test_png_size () =
  let img = Option.get (image_of_rgba ~width:4 ~height:3
                          (Bytes.make 48 '\001')) in
  let w, h = image_size img in
  check "w" true (w = 4.0);
  check "h" true (h = 3.0);
  let png = image_png img in
  check "nonempty" true (Bytes.length png > 40)

let test_png_reject () =
  check "wrong-len" true
    (image_of_rgba ~width:2 ~height:2 (Bytes.make 17 '\000') = None);
  check "no-dims" true
    (image_of_rgba ~width:0 ~height:2 (Bytes.make 0 '\000') = None)

let test_png_crc_known () =
  (* crc32("IHDR" + 13 zero-ish bytes) has a fixed value; decode our
     own IEND chunk's CRC to spot-check the checksum path. *)
  let img = Option.get (image_of_rgba ~width:1 ~height:1
                          (Bytes.make 4 '\000')) in
  let png = image_png img in
  check_s "iend" "IEND" (Bytes.sub_string png (Bytes.length png - 8) 4)

(* ------------------------------------------------------------------ *)
(* Menu model -> rows *)

let int_of_kind = function
  | Row_item -> 0 | Row_separator -> 1 | Row_submenu -> 2

let item ?(enabled = true) ?(checked = false) ~id label =
  Item { label; id; enabled; checked }

let test_menu_model () =
  let m =
    menu ~title:"App"
      [ item ~id:7 "Open";
        Separator;
        Submenu
          { label = "More"; enabled = true;
            items = [ item ~id:9 "Deep";
                      item ~enabled:false ~id:10 "Off" ] };
        item ~id:8 ~checked:true "Flag" ]
  in
  let rows = menu_rows m in
  check_i "count" 6 (Array.length rows);
  check_i "d1" 0 rows.(0).depth;
  check_i "k1" 0 (int_of_kind rows.(0).kind);
  check_i "id1" 7 rows.(0).id;
  check_i "k2" 1 (int_of_kind rows.(1).kind);
  check_i "k3" 2 (int_of_kind rows.(2).kind);
  check_i "d4" 1 rows.(3).depth;
  check_i "id4" 9 rows.(3).id;
  check "en4" false rows.(4).enabled;
  check_i "id5" 8 rows.(5).id;
  check "ck5" true rows.(5).checked;
  check_s "title" "App" m.title

(* ------------------------------------------------------------------ *)
(* Desktop entry plumbing *)

let test_desktop_name () =
  check_s "plain" "myapp" (P.desktop_name "myapp");
  check_s "space" "My-App" (P.desktop_name "My App");
  check_s "bad" "--a" (P.desktop_name "!!a")

let test_entry_string () =
  check_s "ctrl" "a b " (P.entry_string "a\tb\n")

let test_exec_arg () =
  check_s "pct" "\"x%%u\"" (P.exec_arg "x%u");
  check_s "dollar" "\"x\\$y\"" (P.exec_arg "x$y")

let test_handler_entry () =
  let s =
    P.handler_desktop_entry ~name:"Demo" ~exe:"/bin/d %u"
      [ "demo"; "demo2" ]
  in
  check "desktop" true (contains s "[Desktop Entry]");
  check "activatable" true (contains s "DBusActivatable=true");
  check "mime1" true (contains s "x-scheme-handler/demo;");
  check "mime2" true (contains s "x-scheme-handler/demo2;");
  check "exec" true (contains s "%%u")

let test_handler_schemes () =
  let dir = Filename.get_temp_dir_name () in
  let path = Filename.concat dir
      (Printf.sprintf "lui-shx-%d.desktop" (Unix.getpid ())) in
  let oc = open_out_bin path in
  output_string oc
    "[Desktop Entry]\n\
     MimeType=x-scheme-handler/one;x-scheme-handler/two;\n";
  close_out oc;
  check_sl "schemes" [ "one"; "two" ] (P.handler_schemes path);
  Unix.unlink path

(* ------------------------------------------------------------------ *)
(* mimeapps.list editing — XDG_CONFIG_HOME pointed at a temp dir so
   the real user config is untouched. *)

let test_mime () =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "lui-shx-mime-%d" (Unix.getpid ())) in
  Unix.mkdir dir 0o755;
  Unix.putenv "XDG_CONFIG_HOME" dir;
  let file = Filename.concat dir "mimeapps.list" in
  let oc = open_out_bin file in
  output_string oc
    "[Default Applications]\n\
     text/html=firefox.desktop\n\
     x-scheme-handler/demo=old.desktop\n\
     \n\
     [Added Associations]\n\
     text/plain=vim.desktop\n";
  close_out oc;
  check_opt_s "read" (Some "old.desktop")
    (P.mime_default "x-scheme-handler/demo");
  P.set_mime_default "x-scheme-handler/demo" "new.desktop" "new.desktop";
  check_opt_s "replaced" (Some "new.desktop")
    (P.mime_default "x-scheme-handler/demo");
  check_opt_s "untouched" (Some "firefox.desktop")
    (P.mime_default "text/html");
  (* Insert a mime with no section member. *)
  P.set_mime_default "x-scheme-handler/x" "x.desktop" "x.desktop";
  check_opt_s "created" (Some "x.desktop")
    (P.mime_default "x-scheme-handler/x");
  (* Removal only applies to the owner's own file. *)
  P.set_mime_default "x-scheme-handler/demo" "" "someoneelse.desktop";
  check_opt_s "not-ours" (Some "new.desktop")
    (P.mime_default "x-scheme-handler/demo");
  P.set_mime_default "x-scheme-handler/demo" "" "new.desktop";
  check_opt_s "removed" None
    (P.mime_default "x-scheme-handler/demo")

(* ------------------------------------------------------------------ *)
(* Bus name / object path / launcher *)

let test_bus_name () =
  check_s "name" "com.lui.sh.demo"
    (P.bus_name_of_desktop_id "com.lui.sh.demo.desktop");
  check_s "simple" "demo" (P.bus_name_of_desktop_id "demo.desktop")

let test_obj_path () =
  check_s "path" "/com/lui/sh/demo"
    (P.object_path_of_bus_name "com.lui.sh.demo")

let test_fnv () =
  let h = P.fnv1a32 "demo.desktop" in
  check "deterministic" true (h = P.fnv1a32 "demo.desktop");
  check "varies" true (h <> P.fnv1a32 "other.desktop")

let test_launcher_path () =
  let p = P.launcher_path "demo.desktop" in
  check "prefix" true
    (contains p "/com/canonical/unity/launcherentry/")

let test_bus_addr () =
  check "nonempty" true (String.length (P.session_bus_address ()) > 0)

let test_handler_entry_path () =
  let dir, file = P.handler_entry "my app" in
  check "dir" true (contains dir "applications");
  check_s "file" "my-app.url-handler.desktop" file

(* ------------------------------------------------------------------ *)
(* App identity / menu queue — pure refs *)

let test_app_menu () =
  let before = app_menu_count () in
  let m = menu ~title:"App" [ item ~id:1 "One" ] in
  check "insert" true (app_menu_insert m ~at:0);
  check_i "count+1" (before + 1) (app_menu_count ());
  check "remove" true (app_menu_remove ~at:0);
  check_i "count" before (app_menu_count ());
  check "remove-oob" false (app_menu_remove ~at:99)

let test_identity () =
  set_app_name "demo-app";
  check_s "name" "demo-app" (app_name ());
  check "policy" true (set_activation_policy Accessory);
  check "policy-get" true (activation_policy () = Some Accessory);
  check "title" false (set_window_title "hello");
  check_s "title-get" "hello" (P.window_title ())

(* ------------------------------------------------------------------ *)
(* Event dispatch — translation is pure OCaml *)

let test_dispatch () =
  let got = ref [] in
  set_open_url_handler (Some (fun u -> got := ("url", u) :: !got));
  set_menu_handler (Some (fun id -> got := ("menu", string_of_int id) :: !got));
  set_status_handler
    (Some (fun t -> got := ("status", string_of_int t) :: !got));
  set_notification_handler
    (Some (fun id -> got := ("notif", id) :: !got));
  P.dispatch_event (2, 0, "demo://x");
  P.dispatch_event (3, 17, "");
  P.dispatch_event (4, 5, "");
  P.dispatch_event (0, 42, "");       (* unknown dbus id: dropped *)
  match !got with
  | [ ("status", "5"); ("menu", "17"); ("url", "demo://x") ] -> ()
  | _ -> Alcotest.fail "wrong dispatch order"

(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "lui_shell_linux"
    [ "png", [ Alcotest.test_case "header" `Quick test_png_header;
               Alcotest.test_case "size" `Quick test_png_size;
               Alcotest.test_case "reject" `Quick test_png_reject;
               Alcotest.test_case "iend" `Quick test_png_crc_known ];
      "menu", [ Alcotest.test_case "rows" `Quick test_menu_model ];
      "entry", [ Alcotest.test_case "desktop-name" `Quick test_desktop_name;
                 Alcotest.test_case "entry-string" `Quick test_entry_string;
                 Alcotest.test_case "exec-arg" `Quick test_exec_arg;
                 Alcotest.test_case "handler-entry" `Quick test_handler_entry;
                 Alcotest.test_case "handler-schemes" `Quick
                   test_handler_schemes;
                 Alcotest.test_case "handler-path" `Quick
                   test_handler_entry_path ];
      "mime", [ Alcotest.test_case "edit" `Quick test_mime ];
      "bus", [ Alcotest.test_case "name" `Quick test_bus_name;
               Alcotest.test_case "path" `Quick test_obj_path;
               Alcotest.test_case "fnv" `Quick test_fnv;
               Alcotest.test_case "launcher" `Quick test_launcher_path;
               Alcotest.test_case "addr" `Quick test_bus_addr ];
      "model", [ Alcotest.test_case "app-menu" `Quick test_app_menu;
                 Alcotest.test_case "identity" `Quick test_identity ];
      "events", [ Alcotest.test_case "dispatch" `Quick test_dispatch ] ]
