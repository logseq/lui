(* Alcotest suite: VT corpus, grid ops, scrollback, selection, PTY
   round-trip (unix), renderer smoke (stub engine). *)

module G = Lui_plugin_terminal.G
module A = Lui_plugin_terminal.A
module Vt = Lui_plugin_terminal.Vt
module P = Lui_plugin_terminal.P
module K = Lui_plugin_terminal.K
module L = Lui_plugin_terminal.L
module R = Lui_plugin_terminal.R

let mkvt ?(cols = 8) ?(rows = 4) ?(sb = 16) () =
  Vt.create ~cols ~rows ~max_scrollback:sb ()

let cell g ~doc ~col =
  (G.doc_row g doc).G.cells.(col)

let row_txt g ~doc =
  String.trim (G.row_text g doc)

(* ------------------------------------------------------------ VT *)

let test_print_wrap () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "hello world foo bar");
  let g = Vt.grid vt in
  (* 17 chars at 8 cols: "hello wo"/"rld foo "/" bar" wrapped *)
  Alcotest.(check string) "row0" "hello wo" (row_txt g ~doc:0);
  Alcotest.(check bool) "wrap" true (G.doc_row g 0).G.wrapped

let test_sgr () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "\x1b[1;31mx\x1b[0my");
  let g = Vt.grid vt in
  let c = cell g ~doc:0 ~col:0 in
  Alcotest.(check bool) "bold" true c.G.attrs.A.bold;
  Alcotest.(check bool) "fg31" true (c.G.attrs.A.fg = A.Palette 1);
  Alcotest.(check bool) "reset" true (A.equal (cell g ~doc:0 ~col:1).G.attrs A.default)

let test_sgr_256_tc () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "\x1b[38;5;196mA\x1b[48;2;10;20;30mB");
  let g = Vt.grid vt in
  Alcotest.(check bool) "pal196" true
    ((cell g ~doc:0 ~col:0).G.attrs.A.fg = A.Palette 196);
  Alcotest.(check bool) "rgb bg" true
    ((cell g ~doc:0 ~col:1).G.attrs.A.bg = A.Rgb (10, 20, 30))

let test_cursor_moves () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "\x1b[2;3H\x1b[C\x1b[A\x1b[2D");
  let cx, cy = G.cursor (Vt.grid vt) in
  Alcotest.(check (pair int int)) "cup" (1, 0) (cx, cy)

let test_erase () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "abcd\x1b[2K");
  Alcotest.(check string) "el2" "" (row_txt (Vt.grid vt) ~doc:0);
  ignore (Vt.feed_string vt "\x1b[1;1Hab\x1b[2G\x1b[K");
  Alcotest.(check string) "el0" "a" (row_txt (Vt.grid vt) ~doc:0)

let test_scroll_region () =
  let vt = mkvt ~rows:4 () in
  ignore (Vt.feed_string vt "L1\nL2\nL3\nL4");
  ignore (Vt.feed_string vt "\x1b[2;3r\x1b[2;1H\x1bM"); (* RI at row2 scrolls region down *)
  let g = Vt.grid vt in
  Alcotest.(check string) "keep l1" "L1" (row_txt g ~doc:0);
  Alcotest.(check string) "region" "L2" (row_txt g ~doc:2);
  ignore (Vt.feed_string vt "\x1b[r")

let test_alt_screen () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "main");
  ignore (Vt.feed_string vt "\x1b[?1049halt");
  let g = Vt.grid vt in
  Alcotest.(check bool) "alt" true (G.is_alt g);
  Alcotest.(check string) "alt txt" "alt" (row_txt g ~doc:0);
  ignore (Vt.feed_string vt "\x1b[?1049l");
  Alcotest.(check string) "main back" "main" (row_txt g ~doc:0);
  Alcotest.(check bool) "main scr" false (G.is_alt g)

let test_scrollback () =
  let vt = mkvt ~rows:2 ~sb:8 () in
  ignore (Vt.feed_string vt "r1\nr2\nr3\nr4\n");
  let g = Vt.grid vt in
  (* each \n at the bottom scrolls one row into history *)
  Alcotest.(check int) "sb" 3 (G.sb_len g);
  Alcotest.(check string) "sb0" "r1" (row_txt g ~doc:0);
  Alcotest.(check string) "live" "r4" (row_txt g ~doc:3)

let test_modes () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "\x1b[?25l\x1b[?2004h\x1b[?1h");
  let g = Vt.grid vt in
  Alcotest.(check bool) "invis" false (G.mode_cursor_visible g);
  Alcotest.(check bool) "bpaste" true (G.mode_bracketed g);
  Alcotest.(check bool) "appcur" true (G.mode_appcursor g)

let test_osc () =
  let vt = mkvt () in
  let acts = Vt.feed_string vt "\x1b]2;my title\x07\x1b]8;;https://x.y\x07Z\x1b]8;;\x07" in
  Alcotest.(check bool) "title" true
    (List.exists (function Vt.Title (2, "my title") -> true | _ -> false) acts);
  let g = Vt.grid vt in
  let c = cell g ~doc:0 ~col:0 in
  Alcotest.(check string) "link" "https://x.y" (Vt.link_uri vt c.G.link)

let test_utf8 () =
  let vt = mkvt () in
  ignore (Vt.feed_string vt "a\xE4\xB8\xAD\xE6\x96\x87z");
  let g = Vt.grid vt in
  (* a + wide CJK + wide CJK + z: cursor at col 5 *)
  let cx, _ = G.cursor g in
  (* a + 2 wide CJK + z = 6 cells *)
  Alcotest.(check int) "wide" 6 cx;
  (* malformed byte -> U+FFFD *)
  ignore (Vt.feed_string vt "\x1b[1;1H\xC3\x28");
  Alcotest.(check string) "fffd" "\xEF\xBF\xBD"
    (cell g ~doc:0 ~col:0).G.text

let test_resize_rewrap () =
  let vt = mkvt ~cols:6 ~rows:3 ~sb:8 () in
  ignore (Vt.feed_string vt "aaabbb ccc");
  let g = Vt.grid vt in
  G.resize g ~cols:3 ~rows:3;
  Alcotest.(check string) "r0" "aaa" (row_txt g ~doc:0);
  Alcotest.(check string) "r1" "bbb" (row_txt g ~doc:1)

(* ------------------------------------------------------------ selection *)

let test_selection () =
  let vt = mkvt ~cols:10 ~rows:3 () in
  (* \r\n: LF alone keeps the column *)
  ignore (Vt.feed_string vt "hello\r\nworld\n");
  let g = Vt.grid vt in
  let id0 = (G.doc_row g 0).G.id and id1 = (G.doc_row g 1).G.id in
  G.sel_start g ~id:id0 ~col:1 G.Sel_char;
  G.sel_extend g ~id:id1 ~col:3;
  Alcotest.(check string) "char sel" "ello\nworl" (G.sel_text g);
  G.sel_clear g;
  G.sel_start g ~id:id0 ~col:2 G.Sel_line;
  Alcotest.(check string) "line sel" "hello" (G.sel_text g)

let test_word_sel () =
  let vt = mkvt ~cols:20 ~rows:2 () in
  ignore (Vt.feed_string vt "foo bar-baz quux");
  let g = Vt.grid vt in
  let id = (G.doc_row g 0).G.id in
  G.sel_start g ~id ~col:6 G.Sel_word;
  Alcotest.(check string) "word" "bar-baz" (G.sel_text g)

(* ------------------------------------------------------------ keys *)

let test_keys () =
  let m = Lui_window.Input.mods_none in
  let open Lui_window.Input in
  Alcotest.(check (option string)) "up" (Some "\x1b[A")
    (K.key_bytes ~appcursor:false Arrow_up m);
  Alcotest.(check (option string)) "app up" (Some "\x1bOA")
    (K.key_bytes ~appcursor:true Arrow_up m);
  Alcotest.(check (option string)) "shift up" (Some "\x1b[1;2A")
    (K.key_bytes ~appcursor:true Arrow_up { m with shift = true });
  Alcotest.(check (option string)) "ctrl c" (Some "\x03")
    (K.key_bytes ~appcursor:false (Other 6) { m with ctrl = true });
  Alcotest.(check string) "bpaste" "\x1b[200~x\x1b[201~"
    (K.paste_bytes ~bracketed:true "x")

(* ------------------------------------------------------------ links *)

let test_links () =
  let hits = L.find_in_row "go https://a.b/c, and d.png:12:3 x" in
  Alcotest.(check bool) "url" true
    (List.exists (fun h -> h.L.text = "https://a.b/c" && h.L.kind = L.Url) hits);
  Alcotest.(check bool) "file:line" true
    (List.exists (fun h -> h.L.kind = L.File_line (12, 3)) hits)

(* ------------------------------------------------------------ PTY *)

let test_pty_cat () =
  let cat = if Sys.file_exists "/bin/cat" then "/bin/cat" else "cat" in
  let p = P.spawn ~argv:[| cat |] ~env:[| "TERM=xterm" |] ~cwd:"/"
      ~cols:80 ~rows:24 in
  ignore (P.write_string p "echo-pty-test\n");
  let b = Bytes.create 4096 in
  let got = ref 0 in
  let tries = ref 0 in
  while !got < 14 && !tries < 200 do
    incr tries;
    let n = P.read p b !got (Bytes.length b - !got) in
    if n > 0 then got := !got + n else Unix.sleepf 0.005
  done;
  let s = Bytes.sub_string b 0 !got in
  Alcotest.(check bool) "echo" true
    (try ignore (Str.search_forward (Str.regexp "echo-pty-test") s 0); true
     with Not_found -> false);
  P.close p;
  Alcotest.(check bool) "poll" true (P.poll p <> None)

(* ------------------------------------------------------------ render *)

(* Stub engine: fixed metrics, trivial bitmap — lets the smoke test run
   headless without a real font stack. *)
let stub_engine : Obj.t R.engine =
  { create = (fun ?families:_ ?weight:_ ?italic:_ ~size:_ () -> Obj.repr 0);
    metrics = (fun _ -> (8., 2., 1., 11.));
    shape =
      (fun _ s ->
         if s = "" then [||]
         else [| { R.sfont = Obj.repr 0;
                  R.sgs = Array.init (String.length s)
                      (fun i -> { R.sid = i; R.sx = float i;
                                  R.sy = 0.; R.sadv = 1. }) } |]);
    rasterize =
      (fun ?scale:_ ?dx:_ ?shade:_ _ _ ->
         Some { R.bleft = 0; R.btop = 0; R.bw = 2; R.bh = 2;
                R.bcolor = false; R.bpixels = Bytes.make 4 '\xFF' });
    subpixel = (fun ?scale:_ _ -> 1);
    baseline = (fun y -> Float.floor y);
    is_color = (fun _ -> false);
  }

let test_render_smoke () =
  let vt = mkvt ~cols:10 ~rows:3 () in
  ignore (Vt.feed_string vt "\x1b[41mred bg\x1b[0m plain\n\x1b[4mu");
  let g = Vt.grid vt in
  let r = R.create stub_engine ~size:12. ~scale:1.
      ~theme:(A.dark_theme ()) () in
  let mask = Lui_scene.Atlas.create ~bpp:1 ~w:256 ~h:256 in
  let color = Lui_scene.Atlas.create ~bpp:4 ~w:256 ~h:256 in
  let scene = Lui_scene.create ~mask_atlas:mask ~color_atlas:color in
  R.render r g scene ~w:80 ~h:36;
  let ops = scene.Lui_scene.ops in
  let nfills = List.length (List.filter (function Lui_scene.Fill _ -> true
                                     | _ -> false) ops) in
  let nglyphs = List.length (List.filter (function Lui_scene.Glyphs _ -> true
                                       | _ -> false) ops) in
  Alcotest.(check bool) "has fills" true (nfills >= 2);
  Alcotest.(check bool) "has glyph op" true (nglyphs >= 1)

(* ---- plugin service ----------------------------------------------- *)

(* plugin:terminal's spawn builds a Terminal.t, whose renderer adapts
   the CoreText Lui_text backend — its stubs raise on other platforms. *)
let text_backend_ok () =
  match (try Some (Lui_text.create ~size:12. ()) with _ -> None) with
  | Some _ -> true
  | None -> false

let test_service () =
  if text_backend_ok () then begin
  (match Lui_plugin.use [ Lui_plugin_terminal.plugin ] with
   | Ok () -> ()
   | Error e -> Alcotest.fail e);
  Fun.protect ~finally:Lui_plugin.reset @@ fun () ->
  let call m p =
    match Lui_plugin.call ~service:"plugin:terminal" ~method_:m p with
    | Ok s -> Yojson.Safe.from_string s
    | Error e -> Alcotest.fail e
  in
  let open Yojson.Safe.Util in
  let json l = Yojson.Safe.to_string (`Assoc l) in
  let cat = if Sys.file_exists "/bin/cat" then "/bin/cat" else "cat" in
  let id =
    call "spawn"
      (json [ ("argv", `List [ `String cat ]);
              ("cols", `Int 10); ("rows", `Int 5) ])
    |> member "id" |> to_int
  in
  Alcotest.(check bool) "id nonneg" true (id >= 0);
  ignore
    (call "write"
       (json [ ("id", `Int id); ("data", `String "hi\n") ]));
  let rec wait n =
    if n <= 0 then Alcotest.fail "service: no echo";
    let j =
      call "read_events" (json [ ("id", `Int id) ])
    in
    if j |> member "cursor" |> member "y" |> to_int >= 1 then j
    else (Unix.sleepf 0.02; wait (n - 1))
  in
  let j = wait 200 in
  Alcotest.(check bool) "alive" true (j |> member "alive" |> to_bool);
  Alcotest.(check bool) "not exited" true (j |> member "exit" |> to_option to_int = None);
  ignore
    (call "resize" (json [ ("id", `Int id);
                           ("cols", `Int 40); ("rows", `Int 8) ]));
  let j = call "read_events" (json [ ("id", `Int id) ]) in
  Alcotest.(check int) "cols" 40 (j |> member "cols" |> to_int);
  Alcotest.(check int) "rows" 8 (j |> member "rows" |> to_int);
  ignore (call "close" (json [ ("id", `Int id) ]));
  match Lui_plugin.call ~service:"plugin:terminal" ~method_:"read_events"
          (json [ ("id", `Int id) ]) with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "close did not remove terminal"
  end

(* ------------------------------------------------------------ *)

let () =
  Alcotest.run "lui_plugin_terminal" [
    "vt", [
      Alcotest.test_case "print+wrap" `Quick test_print_wrap;
      Alcotest.test_case "sgr" `Quick test_sgr;
      Alcotest.test_case "sgr 256/truecolor" `Quick test_sgr_256_tc;
      Alcotest.test_case "cursor moves" `Quick test_cursor_moves;
      Alcotest.test_case "erase" `Quick test_erase;
      Alcotest.test_case "scroll region" `Quick test_scroll_region;
      Alcotest.test_case "alt screen" `Quick test_alt_screen;
      Alcotest.test_case "scrollback" `Quick test_scrollback;
      Alcotest.test_case "modes" `Quick test_modes;
      Alcotest.test_case "osc+osc8" `Quick test_osc;
      Alcotest.test_case "utf8+wide" `Quick test_utf8;
      Alcotest.test_case "resize rewrap" `Quick test_resize_rewrap;
    ];
    "selection", [
      Alcotest.test_case "char+line" `Quick test_selection;
      Alcotest.test_case "word" `Quick test_word_sel;
    ];
    "keys", [ Alcotest.test_case "encodings" `Quick test_keys ];
    "links", [ Alcotest.test_case "detect" `Quick test_links ];
    "pty", [
      Alcotest.test_case "cat round-trip" `Slow test_pty_cat;
    ];
    "render", [
      Alcotest.test_case "smoke ops" `Quick test_render_smoke;
    ];
    "service", [
      Alcotest.test_case "spawn/write/events" `Slow test_service;
    ];
  ]

