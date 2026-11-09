(* Lui_clock semantics, view-owned timers through Drive, and the native
   bridge clock entry points. *)

let check_floats = Alcotest.(check (list (float 0.)))

let test_deadline_order () =
  let clock = Lui_clock.create () in
  let fired = ref [] in
  let note name () = fired := (name, Lui_clock.now clock) :: !fired in
  ignore (Lui_clock.after clock 30. (note "late"));
  ignore (Lui_clock.after clock 10. (note "first"));
  ignore (Lui_clock.after clock 10. (note "tie"));
  let repeating = Lui_clock.every clock 15. (note "every") in
  Alcotest.(check int) "advance fires every due timer" 5
    (Lui_clock.advance clock 31.);
  Alcotest.(check (list (pair string (float 0.))))
    "deadline order, ties in scheduling order, now at each deadline"
    [ ("first", 10.); ("tie", 10.); ("every", 15.); ("late", 30.);
      ("every", 30.) ]
    (List.rev !fired);
  Alcotest.(check (float 0.)) "clock ends at the target" 31. (Lui_clock.now clock);
  Alcotest.(check int) "only the repeating timer is pending" 1
    (Lui_clock.pending clock);
  Lui_clock.cancel repeating;
  Lui_clock.cancel repeating;
  Alcotest.(check int) "cancel is idempotent" 0 (Lui_clock.pending clock);
  Alcotest.(check bool) "cancelled timer is inactive" false
    (Lui_clock.active repeating)

let test_nested_scheduling () =
  let clock = Lui_clock.create () in
  let times = ref [] in
  let victim = ref None in
  ignore
    (Lui_clock.after clock 5. (fun () ->
       times := Lui_clock.now clock :: !times;
       ignore
         (Lui_clock.after clock 5. (fun () ->
            times := Lui_clock.now clock :: !times));
       Option.iter Lui_clock.cancel !victim));
  victim :=
    Some (Lui_clock.after clock 8. (fun () -> Alcotest.fail "cancelled timer ran"));
  ignore (Lui_clock.advance clock 20.);
  check_floats "a timer scheduled by a timer fires in the same advance"
    [ 5.; 10. ] (List.rev !times);
  ignore (Lui_clock.after clock 1. (fun () -> ignore (Lui_clock.advance clock 1.)));
  Alcotest.check_raises "time cannot move inside a timer"
    (Invalid_argument "Lui_clock: time cannot move inside a timer") (fun () ->
      ignore (Lui_clock.advance clock 1.));
  Alcotest.(check int) "the clock recovers after a raising timer" 0
    (Lui_clock.advance clock 1.)

let test_host_ticks () =
  let clock = Lui_clock.create () in
  let fired = ref [] in
  ignore (Lui_clock.after clock 0. (fun () -> fired := "now" :: !fired));
  ignore (Lui_clock.after clock 100. (fun () -> fired := "later" :: !fired));
  Alcotest.(check (option (float 0.))) "a due timer asks for an immediate tick"
    (Some 0.) (Lui_clock.next_delay clock);
  Alcotest.(check int) "the anchoring tick fires only due timers" 1
    (Lui_clock.tick clock ~now:5_000.);
  Alcotest.(check (option (float 0.))) "next wakeup" (Some 100.)
    (Lui_clock.next_delay clock);
  Alcotest.(check int) "host time maps onto clock time" 0
    (Lui_clock.tick clock ~now:5_099.);
  Alcotest.(check int) "the deadline fires once host time reaches it" 1
    (Lui_clock.tick clock ~now:5_100.);
  Alcotest.(check (float 0.)) "clock time" 100. (Lui_clock.now clock);
  Alcotest.(check int) "a backwards host clock never moves time back" 0
    (Lui_clock.tick clock ~now:1_000.);
  Alcotest.(check (float 0.)) "clock time kept" 100. (Lui_clock.now clock);
  ignore (Lui_clock.after clock 50. (fun () -> fired := "advanced" :: !fired));
  ignore (Lui_clock.advance clock 50.);
  Alcotest.(check int) "advancing a running clock shifts the host mapping" 0
    (Lui_clock.tick clock ~now:5_110.);
  Alcotest.(check (float 0.)) "host ticks continue from the advanced time" 160.
    (Lui_clock.now clock);
  Lui_clock.pause clock;
  ignore (Lui_clock.after clock 10. (fun () -> fired := "paused" :: !fired));
  Alcotest.(check (option (float 0.))) "a paused clock needs no wakeup" None
    (Lui_clock.next_delay clock);
  Alcotest.(check int) "host ticks are ignored while paused" 0
    (Lui_clock.tick clock ~now:99_999.);
  Alcotest.(check int) "advance still steps a paused clock" 1
    (Lui_clock.advance clock 10.);
  Lui_clock.resume clock;
  ignore (Lui_clock.after clock 10. (fun () -> fired := "resumed" :: !fired));
  Alcotest.(check int) "resume re-anchors instead of jumping to host time" 0
    (Lui_clock.tick clock ~now:200_000.);
  Alcotest.(check int) "then follows the host again" 1
    (Lui_clock.tick clock ~now:200_010.);
  Alcotest.(check (list string)) "fired"
    [ "now"; "later"; "advanced"; "paused"; "resumed" ] (List.rev !fired)

let test_wakeup () =
  let clock = Lui_clock.create () in
  let wakes = ref [] in
  Lui_clock.set_wakeup clock (Some (fun delay -> wakes := delay :: !wakes));
  ignore (Lui_clock.after clock 100. ignore);
  ignore (Lui_clock.after clock 300. ignore);
  ignore (Lui_clock.after clock 50. ignore);
  ignore (Lui_clock.advance clock 60.);
  ignore
    (Lui_clock.after clock 10. (fun () -> ignore (Lui_clock.after clock 1. ignore)));
  ignore (Lui_clock.advance clock 10.);
  Lui_clock.pause clock;
  ignore (Lui_clock.after clock 0. ignore);
  Lui_clock.resume clock;
  check_floats
    "earliest timers, time moves and resume wake the host; later timers, \
     timer actions and a paused clock do not"
    [ 100.; 50.; 40.; 10.; 1.; 0. ] (List.rev !wakes)

let test_settle_and_arguments () =
  let clock = Lui_clock.create ~start:1_000. () in
  let count = ref 0 in
  ignore
    (Lui_clock.after clock 400. (fun () ->
       incr count;
       ignore (Lui_clock.after clock 600. (fun () -> incr count))));
  Alcotest.(check int) "settle runs chained one-shot timers" 2
    (Lui_clock.settle clock);
  Alcotest.(check (float 0.)) "settle stops at the last deadline" 2_000.
    (Lui_clock.now clock);
  ignore (Lui_clock.every clock 1. ignore);
  Alcotest.check_raises "a repeating timer never settles"
    (Failure "Lui_clock.settle: more than 10 timers fired") (fun () ->
      ignore (Lui_clock.settle ~limit:10 clock));
  Alcotest.check_raises "negative delay"
    (Invalid_argument "Lui_clock.after: delay must be finite and >= 0")
    (fun () -> ignore (Lui_clock.after clock (-1.) ignore));
  Alcotest.check_raises "zero interval"
    (Invalid_argument "Lui_clock.every: interval must be finite and > 0")
    (fun () -> ignore (Lui_clock.every clock 0. ignore));
  Alcotest.check_raises "non-finite advance"
    (Invalid_argument "Lui_clock.advance: ms must be finite and >= 0")
    (fun () -> ignore (Lui_clock.advance clock Float.nan))

(* A toast that dismisses itself four seconds after it mounts. The timer
   belongs to the toast's scope, so closing it early cancels the timer. *)
let toast_view _context model send =
  Lui_elements.column
    [ Lui_elements.button ~text:"Show" ~on_press:(Lui_elements.press send `Show) [];
      Lui_elements.dyn ~equal:( = )
        (fun shown ->
           if shown then fun context parent ->
             ignore (Lui_ui.after context 4_000. (fun () -> ignore (send `Hide)));
             Lui_elements.row
               [ Lui_elements.text ~value:"Saved" [];
                 Lui_elements.button ~text:"Close"
                   ~on_press:(Lui_elements.press send `Hide) [] ]
               context parent
           else Lui_elements.column [])
        model ]

let toast_reducer _ = function `Show -> true | `Hide -> false

let run_scenario session source =
  match Drive.Scenario.run ~emit:ignore (Drive.Session.driver session) source with
  | [] -> ()
  | failures ->
    Alcotest.failf "%s"
      (String.concat "\n"
         (List.map
            (fun (f : Drive.Scenario.failure) ->
               Printf.sprintf "line %d: %s" f.line f.message)
            failures))

let test_drive_toast () =
  let session =
    Drive.Session.mount ~profile:(Lui_protocol.generic_profile ())
      ~initial:false ~reducer:toast_reducer ~view:toast_view ()
  in
  let clock = Lui_app.clock session.Drive.Session.app in
  Fun.protect ~finally:(fun () -> Drive.Session.dispose session) (fun () ->
    run_scenario session
      {|press "Show"
expect text:Saved
clock advance 3999ms
expect text:Saved
clock advance 1
expect-absent text:Saved
press "Show"
clock advance 1.5s
press "Close"
expect-absent text:Saved|};
    Alcotest.(check int) "closing the toast cancelled its timer" 0
      (Lui_clock.pending clock);
    run_scenario session {|press "Show"
clock settle
expect-absent text:Saved|};
    Alcotest.(check (float 0.)) "scenario time" 9_500. (Lui_clock.now clock);
    match
      Drive.Scenario.run ~emit:ignore (Drive.Session.driver session)
        "clock advance soon\nclock rewind"
    with
    | [ bad_duration; bad_command ] ->
      Alcotest.(check string) "bad duration" "bad duration: soon"
        bad_duration.message;
      Alcotest.(check string) "usage"
        "usage: clock pause|resume|settle|advance <duration>"
        bad_command.message
    | failures ->
      Alcotest.failf "expected two failures, got %d" (List.length failures))

let test_native_bridge_clock () =
  let bridge = Lui_native_bridge.create "Toast" in
  let backend =
    Lui_native_bridge.backend bridge (Lui_protocol.generic_profile ())
  in
  let app = Lui_app.create backend false toast_reducer toast_view in
  Alcotest.(check (float 0.)) "no wakeup before boot" (-1.)
    (Lui_native_bridge.clock_next_delay bridge);
  ignore (Lui_native_bridge.boot bridge app);
  let runtime = Lui_app.runtime app in
  let show =
    let rec find node =
      let text =
        Option.bind
          (Hashtbl.find_opt runtime.Lui_runtime.runtime_properties node)
          (Lui_protocol.Property_map.find_opt Lui_protocol.TextValue)
      in
      if text = Some (Lui_protocol.StringValue "Show") then Some node
      else List.find_map find (Lui_runtime.children runtime node)
    in
    Option.get (find (Lui_app.root_node app))
  in
  ignore (Lui_native_bridge.dispatch_event bridge (Lui_protocol.Press show));
  Alcotest.(check (float 0.)) "the toast asks for a wakeup" 4_000.
    (Lui_native_bridge.clock_next_delay bridge);
  Alcotest.(check string) "the anchoring tick changes nothing" ""
    (Lui_native_bridge.clock_tick bridge 10_000.);
  let dismissal = Lui_native_bridge.clock_tick bridge 14_000. in
  Alcotest.(check bool) "the due tick delivers the dismissal patch" true
    (String.length dismissal > 0);
  Alcotest.(check (float 0.)) "nothing pending" (-1.)
    (Lui_native_bridge.clock_next_delay bridge);
  ignore (Lui_native_bridge.dispatch_event bridge (Lui_protocol.Press show));
  ignore (Lui_native_bridge.clock_set_paused bridge true);
  Alcotest.(check (float 0.)) "paused" (-1.)
    (Lui_native_bridge.clock_next_delay bridge);
  Alcotest.(check string) "host ticks are ignored while paused" ""
    (Lui_native_bridge.clock_tick bridge 99_000.);
  Alcotest.(check bool) "advance delivers the dismissal" true
    (String.length (Lui_native_bridge.clock_advance bridge 4_000.) > 0);
  ignore (Lui_native_bridge.dispose bridge);
  Alcotest.(check (float 0.)) "no wakeup after dispose" (-1.)
    (Lui_native_bridge.clock_next_delay bridge)

let tests =
  [ ("deadline order", test_deadline_order);
    ("nested scheduling and reentrancy", test_nested_scheduling);
    ("host ticks, pause and resume", test_host_ticks);
    ("wakeup hook", test_wakeup);
    ("settle and argument validation", test_settle_and_arguments);
    ("view timers through Drive", test_drive_toast);
    ("native bridge clock", test_native_bridge_clock) ]
