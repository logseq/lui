(* GC stress for the pointer-detail bridge. The callback allocates on every
   call so a minor collection runs while the six callback arguments are live.
   Run with OCAMLRUNPARAM=s=4k. *)

external stress_press_detail : int -> unit = "stress_press_detail"
external stress_virtual_window : int -> unit = "stress_virtual_window"
external stress_virtual_retention : int -> unit = "stress_virtual_retention"

let window_callbacks = ref 0
let retention_callbacks = ref 0

let () =
  Callback.register "lui_ocaml_press_detail"
    (fun node x y modifiers button target_class ->
      let buffer = Bytes.create 4096 in
      Bytes.fill buffer 0 4096 'x';
      ignore (Sys.opaque_identity (Bytes.to_string buffer));
      ignore
        (Sys.opaque_identity (node, x, y, modifiers, button, target_class));
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
  stress_virtual_window 1000;
  assert (!window_callbacks = 1000);
  stress_virtual_retention 0;
  Callback.register "lui_ocaml_virtual_retention_utf8"
    (fun owner ticket receipt ->
      incr retention_callbacks;
      let buffer = Bytes.make 4096 'r' in
      ignore (Sys.opaque_identity buffer);
      Gc.minor ();
      assert (owner = 9_007_199_254_740_993 && ticket = max_int);
      if receipt = "!" then failwith "expected retention refusal";
      assert (receipt = "r\230\150\135\000x" || receipt = "");
      "");
  stress_virtual_retention 1000;
  assert (!retention_callbacks = 1002);
  print_endline "native bridge GC stress ok"
