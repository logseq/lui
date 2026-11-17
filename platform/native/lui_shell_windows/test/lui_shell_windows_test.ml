(* Pure-model tests: the menu tree flattening, argument validation,
   handler registration and the open-url dispatch that happen before
   any platform call. Runs on every OS — nothing here reaches the
   C stubs. *)

open Lui_shell_windows

let item ?(id = 1) ?(enabled = true) ?(checked = false) label =
  Item { label; id; enabled; checked }

let sub ?(enabled = true) label items =
  Submenu { label; enabled; items }

let kind_of (r : menu_row) = r.kind
let depth_of (r : menu_row) = r.depth

(* ---------- menu flattening ---------- *)

let test_empty_menu () =
  let m = menu [] in
  Alcotest.(check int) "no rows" 0 (Array.length m.rows);
  Alcotest.(check string) "default title" "" m.title

let test_flat_items () =
  let m =
    menu
      [ item ~id:10 "Open";
        Separator;
        item ~id:11 ~enabled:false ~checked:true "Quit" ]
  in
  Alcotest.(check int) "rows" 3 (Array.length m.rows);
  let r0, r1, r2 = m.rows.(0), m.rows.(1), m.rows.(2) in
  Alcotest.(check bool) "item kind" true (kind_of r0 = Row_item);
  Alcotest.(check string) "item label" "Open" r0.label;
  Alcotest.(check int) "item id" 10 r0.id;
  Alcotest.(check bool) "sep kind" true (kind_of r1 = Row_separator);
  Alcotest.(check int) "sep id" (-1) r1.id;
  Alcotest.(check int) "sep depth" 0 (depth_of r1);
  Alcotest.(check bool) "flags" true (r2.enabled = false && r2.checked);
  Alcotest.(check int) "depth" 0 (depth_of r2)

let test_submenu_depth () =
  let m =
    menu ~title:"File"
      [ item ~id:1 "Top";
        sub "Sub"
          [ item ~id:2 "Inner";
            sub "Deep" [ item ~id:3 "Deepest" ] ];
        item ~id:4 "Bottom" ]
  in
  let rows = m.rows in
  Alcotest.(check int) "rows" 6 (Array.length rows);
  let depths = Array.map depth_of rows |> Array.to_list in
  Alcotest.(check (list int)) "depth order" [ 0; 0; 1; 1; 2; 0 ] depths;
  let kind_int (r : menu_row) =
    match r.kind with
    | Row_item -> 0
    | Row_separator -> 1
    | Row_submenu -> 2
  in
  Alcotest.(check (list int)) "kinds" [ 0; 2; 0; 2; 0; 0 ]
    (Array.map kind_int rows |> Array.to_list);
  Alcotest.(check string) "title" "File" m.title;
  Alcotest.(check int) "submenu id" (-1) rows.(1).id;
  Alcotest.(check string) "submenu label" "Sub" rows.(1).label;
  Alcotest.(check int) "leaf id" 3 rows.(4).id;
  Alcotest.(check (list int)) "ids"
    [ 1; -1; 2; -1; 3; 4 ]
    (Array.map (fun (r : menu_row) -> r.id) rows |> Array.to_list)

let test_menu_rows_accessor () =
  let m = menu [ item "A" ] in
  Alcotest.(check int) "rows accessor" 1 (Array.length (menu_rows m))

(* ---------- argument validation ---------- *)

let test_image_args () =
  Alcotest.(check bool) "zero w" true
    (image_of_rgba ~width:0 ~height:4 (Bytes.create 64) = None);
  Alcotest.(check bool) "neg h" true
    (image_of_rgba ~width:2 ~height:(-1) (Bytes.create 8) = None);
  Alcotest.(check bool) "short buffer" true
    (image_of_rgba ~width:2 ~height:2 (Bytes.create 15) = None);
  Alcotest.(check bool) "long buffer" true
    (image_of_rgba ~width:2 ~height:2 (Bytes.create 17) = None)

let test_scheme_args () =
  (* Invalid schemes are rejected before any registry access. *)
  Alcotest.(check bool) "empty" false
    (register_url_scheme ~scheme:"" ());
  Alcotest.(check bool) "digit first" false
    (register_url_scheme ~scheme:"9lui" ());
  Alcotest.(check bool) "bad char" false
    (register_url_scheme ~scheme:"lui scheme" ());
  Alcotest.(check bool) "slash" false
    (register_url_scheme ~scheme:"lui/x" ());
  Alcotest.(check bool) "colon" false
    (register_url_scheme ~scheme:"lui:x" ());
  Alcotest.(check bool) "bad char unregister" false
    (unregister_url_scheme ~scheme:"lui x" ())

(* ---------- open-url dispatch (pure) ---------- *)

let test_dispatch_unregistered () =
  (* Nothing was registered in this process, so no URL dispatches. *)
  let fired = ref None in
  set_open_url_handler (Some (fun url -> fired := Some url));
  Alcotest.(check bool) "unregistered scheme" false
    (dispatch_open_url "lui-unregistered-zzz://x");
  Alcotest.(check bool) "no scheme" false
    (dispatch_open_url "not a url");
  Alcotest.(check bool) "leading colon" false
    (dispatch_open_url ":x");
  Alcotest.(check bool) "handler untouched" true (!fired = None);
  set_open_url_handler None

let test_install () =
  (* The scan is the install on Windows; argv has no registered
     scheme, so it dispatches nothing and never fails. *)
  Alcotest.(check bool) "installs" true (install_open_url_handler ())

(* ---------- handler registration ---------- *)

let test_handler_registration () =
  (* Registration itself never reaches the OS; the handlers fire only
     when a real event arrives on the shell window's thread. *)
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
  run "lui_shell_windows"
    [ ( "menu",
        [ test_case "empty" `Quick test_empty_menu;
          test_case "flat" `Quick test_flat_items;
          test_case "submenu depth" `Quick test_submenu_depth;
          test_case "rows accessor" `Quick test_menu_rows_accessor ] );
      ( "args",
        [ test_case "image validation" `Quick test_image_args;
          test_case "scheme validation" `Quick test_scheme_args ] );
      ( "open-url",
        [ test_case "unregistered" `Quick test_dispatch_unregistered;
          test_case "install" `Quick test_install;
          test_case "handlers" `Quick test_handler_registration ] ) ]
