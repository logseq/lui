open Lui_protocol

let runtime () =
  Lui_runtime.create (Signal.scheduler ())
    { backend_profile = generic_profile (); apply_batch = (fun _ -> true) }

let flush runtime = ignore (Lui_runtime.flush runtime)

let measure name work =
  Gc.full_major ();
  let started = Unix.gettimeofday () in
  work ();
  Printf.printf "LUI_PERF %s %.3f\n%!" name
    ((Unix.gettimeofday () -. started) *. 1000.)

let seed count kind =
  let app = runtime () in
  let parent = Lui_runtime.create_node app kind in
  let children =
    Array.init count (fun index ->
        let child =
          Lui_runtime.create_node app
            (if kind = ListContainer then ListItem else Text)
        in
        Lui_runtime.set_prop app child TextValue (StringValue "initial");
        Lui_runtime.insert_child app parent child index;
        child)
  in
  flush app;
  (app, parent, children)

let text_updates () =
  let small, _, small_nodes = seed 1000 Column in
  measure "local_text_1k_ms" (fun () ->
      Lui_runtime.set_prop small small_nodes.(500) TextValue
        (StringValue "changed");
      flush small);
  let app, _, nodes = seed 10000 Column in
  let update index =
    Lui_runtime.set_prop app
      nodes.(index mod Array.length nodes)
      TextValue
      (StringValue (string_of_int index));
    flush app
  in
  measure "typing_10k_nodes_60_updates_ms" (fun () ->
      for index = 0 to 59 do
        update index
      done);
  measure "sustained_local_mutations_10k_ms" (fun () ->
      for index = 60 to 1059 do
        update index
      done)

let keyed_updates () =
  let app = runtime () in
  let scope = Signal.scope "benchmark" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let items = List.init 1000 Fun.id in
  let source = Signal.state app.runtime_scheduler items in
  ignore
    (Lui_dynamic.keyed context parent (Signal.value source) Fun.id Int.compare
       (fun row item -> Lui_ui.text row (string_of_int (Signal.sample item))));
  flush app;
  measure "keyed_reorder_1k_ms" (fun () ->
      Signal.set source (List.rev items);
      flush app);
  measure "keyed_middle_edit_1k_ms" (fun () ->
      Signal.set source
        (List.map (fun id -> if id = 500 then 1000 else id) (List.rev items));
      flush app);
  Signal.dispose_scope scope

let scroll_updates () =
  let app, list, nodes = seed 10000 ListContainer in
  let scope = Signal.scope "scroll" in
  Lui_runtime.on_event scope app list (function
    | VisibleRange (_, first, _) ->
        Lui_runtime.set_prop app nodes.(0) TextValue
          (StringValue (string_of_int first))
    | _ -> ());
  measure "scroll_background_ms" (fun () ->
      for first = 0 to 99 do
        ignore
          (Lui_runtime.dispatch app (VisibleRange (list, first, first + 20)));
        flush app
      done);
  Signal.dispose_scope scope

let wide_updates () =
  let seeded = ref None in
  measure "flat_mount_10k_ms" (fun () -> seeded := Some (seed 10000 Column));
  let app, parent, nodes = Option.get !seeded in
  measure "wide_reorder_10k_ms" (fun () ->
      Lui_runtime.emit_child_diff app (Hashtbl.create 0) parent
        (Array.to_list nodes)
        (List.rev (Array.to_list nodes));
      flush app)

let branch_lifecycle () =
  let app = runtime () in
  let scope = Signal.scope "branch-benchmark" in
  let context = Lui_ui.context app scope in
  let parent = Lui_ui.column context in
  let source = Signal.state app.runtime_scheduler 0 in
  ignore
    (Lui_dynamic.switch context parent (Signal.value source) Int.equal
       (fun row index -> Lui_ui.text row (string_of_int index)));
  flush app;
  measure "branch_mount_dispose_1k_ms" (fun () ->
      for index = 1 to 1000 do
        Signal.set source index;
        flush app
      done);
  Signal.dispose_scope scope

let () =
  text_updates ();
  keyed_updates ();
  scroll_updates ();
  wide_updates ();
  branch_lifecycle ()
