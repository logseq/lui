(* GC stress for the pointer-detail bridge. The callback allocates on every
   call so a minor collection runs while the six callback arguments are live.
   Run with OCAMLRUNPARAM=s=4k. *)

external stress_press_detail : int -> unit = "stress_press_detail"
external stress_press_detail_clicks : int -> unit = "stress_press_detail_clicks"
external stress_virtual_window : int -> unit = "stress_virtual_window"

let window_callbacks = ref 0
let counted_callbacks = ref 0

let () =
  Callback.register "lui_ocaml_press_detail"
    (fun node x y modifiers button target_class ->
      let buffer = Bytes.create 4096 in
      Bytes.fill buffer 0 4096 'x';
      ignore (Sys.opaque_identity (Bytes.to_string buffer));
      ignore
        (Sys.opaque_identity (node, x, y, modifiers, button, target_class));
      "");
  Callback.register "lui_ocaml_press_detail_clicks"
    (fun node x y modifiers button target_class clicks ->
      incr counted_callbacks;
      let buffer = Bytes.make 4096 'c' in
      ignore (Sys.opaque_identity buffer);
      assert (node = 1 && x = 1.25 && y = 2.5 && modifiers = 3 && button = 0);
      assert (target_class = "a\000b" && clicks = 2);
      "");
  Callback.register "lui_ocaml_virtual_window"
    (fun node generation first last pins ->
      incr window_callbacks;
      assert (node = 9_007_199_254_740_993);
      assert (generation = 7 && first = 99_990 && last = 100_000);
      let buffer = Bytes.make 4096 'w' in
      ignore (Sys.opaque_identity buffer);
      assert (List.length pins = 2048);
      List.iteri (fun index pin -> assert (pin = node + index + 1)) pins;
      "");
  stress_press_detail 4000;
  stress_press_detail_clicks 4000;
  assert (!counted_callbacks = 4000);
  stress_virtual_window 1000;
  assert (!window_callbacks = 1000);
  print_endline "native bridge GC stress ok"
