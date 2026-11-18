module Host = Lui_sdl3
module Raw = Sdl3.Sdl
module Types = Sdl3.T

let require = function Ok value -> value | Error (`Msg message) -> Alcotest.fail message

let with_windows f =
  require (Host.init Host.Init.video);
  Fun.protect ~finally:Host.quit (fun () ->
    let first = Host.create_window "first" ~w:100 ~h:80 Host.Window.hidden |> require in
    Fun.protect ~finally:(fun () -> Host.destroy_window first) (fun () ->
      let second = Host.create_window "second" ~w:100 ~h:80 Host.Window.hidden |> require in
      Fun.protect ~finally:(fun () -> Host.destroy_window second) (fun () -> f first second)))

let text_input_is_window_scoped () = with_windows (fun first second ->
  Host.start_text_input first;
  Host.start_text_input second;
  Host.stop_text_input first;
  Alcotest.(check bool) "first stopped" false (Host.is_text_input_active first);
  Alcotest.(check bool) "second remains active" true (Host.is_text_input_active second);
  Host.stop_text_input second)

let window_events_keep_logical_and_pixel_sizes_distinct () = with_windows (fun first _ ->
  let raw = Raw.Event.create () in
  let payload = Raw.Event.(get raw window) in
  Types.WindowEvent.set payload Types.WindowEvent.typ Raw.event_window_pixel_size_changed;
  Types.WindowEvent.set payload Types.WindowEvent.window_id (Host.get_window_id first);
  Types.WindowEvent.set payload Types.WindowEvent.data1 200;
  Types.WindowEvent.set payload Types.WindowEvent.data2 160;
  Types.WindowEvent.set payload Types.WindowEvent.timestamp 0x100000001L;
  Raw.Event.flushs 0 65535;
  Raw.Event.push raw |> require;
  let event = Host.Event.create () in
  Alcotest.(check bool) "event dequeued" true (Host.wait_event_timeout (Some event) 100);
  let snapshot = Host.Event.value event in
  Alcotest.(check bool) "pixel resize remains distinct" true
    (snapshot.kind = Host.Event.Window (Pixel_size_changed, 200, 160));
  Alcotest.(check (pair int int)) "logical size stays unchanged" (100, 80) (Host.get_window_size first);
  Alcotest.(check bool) "timestamp retains all bits" true (snapshot.timestamp_ns > 0xffffffffL);
  Host.push_key_event first ~down:true ~scancode:14 ~keymod:Host.Kmod.lgui ~repeat:false;
  Alcotest.(check bool) "key dequeued" true (Host.wait_event_timeout (Some event) 100);
  Alcotest.(check bool) "previous snapshot remains owned" true
    (snapshot.kind = Host.Event.Window (Pixel_size_changed, 200, 160));
  Alcotest.(check bool) "key fields decoded" true
    (match (Host.Event.value event).kind with
     | Key_down key -> key.scancode = 14 && key.keymod = Host.Kmod.lgui && not key.repeat
     | _ -> false))

let cross_domain_work_wakes_ui () = with_windows (fun _ _ ->
  Raw.Event.flushs 0 65535;
  let ui = Domain.self () in
  let ran_on = ref None in
  let producer = Domain.spawn (fun () ->
    Host.run_on_main_thread (fun () -> ran_on := Some (Domain.self ()))) in
  Domain.join producer;
  let event = Host.Event.create () in
  Alcotest.(check bool) "work wakes event wait" true
    (Host.wait_event_timeout (Some event) 500);
  Alcotest.(check bool) "callback ran on waiting UI domain" true
    (!ran_on = Some ui))

let () = Alcotest.run "lui_sdl3" [
  "SDL3", [
    Alcotest.test_case "window-scoped IME" `Quick text_input_is_window_scoped;
    Alcotest.test_case "owned event snapshots and pixel sizes" `Quick window_events_keep_logical_and_pixel_sizes_distinct;
    Alcotest.test_case "cross-domain work wakes UI" `Quick cross_domain_work_wakes_ui;
  ]
]
