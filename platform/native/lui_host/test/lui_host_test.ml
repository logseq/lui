(* Focused unit tests for Lui_host assembly: dirty flag, apply_batch,
   resize, and repaint clearing — the seams e2e covers only indirectly. *)

open Alcotest
open Lui_protocol

let noop_renderer : Lui_host.renderer =
  {
    name = "noop";
    render =
      (fun scene ->
        let n = scene.Lui_scene.width * scene.Lui_scene.height * 4 in
        Bytes.make (max n 0) '\000');
  }

let make ?(width = 80) ?(height = 60) ?(scale = 1.) () =
  Lui_host.create ~hooks:Lui_paint.default_hooks ~renderer:noop_renderer
    ~width ~height ~scale ()

let batch ops = { generation = 1; ops }

let test_create_clean () =
  let h = make () in
  check bool "starts clean" false (Lui_host.wants_repaint h);
  check int "empty store" 0 (Lui_store.node_count (Lui_host.store h))

let test_apply_marks_dirty () =
  let h = make () in
  let ok =
    Lui_host.apply_batch h
      (batch [ CreateNode (1, Column); CreateNode (2, Text); InsertChild (1, 2, 0) ])
  in
  check bool "apply ok" true ok;
  check bool "dirty after apply" true (Lui_host.wants_repaint h);
  check int "nodes" 2 (Lui_store.node_count (Lui_host.store h))

let test_repaint_clears_dirty () =
  let h = make () in
  ignore
    (Lui_host.apply_batch h
       (batch
          [ CreateNode (1, Column);
            SetProp (1, BackgroundValue, StringValue "#ff0000") ]));
  check bool "dirty before" true (Lui_host.wants_repaint h);
  let pixels = Lui_host.repaint h in
  check bool "clean after" false (Lui_host.wants_repaint h);
  check int "frame bytes" (80 * 60 * 4) (Bytes.length pixels)

let test_resize_marks_dirty () =
  let h = make () in
  ignore (Lui_host.repaint h);
  check bool "clean" false (Lui_host.wants_repaint h);
  Lui_host.resize h ~width:100 ~height:80 ~scale:2.;
  check bool "dirty after resize" true (Lui_host.wants_repaint h);
  let pixels = Lui_host.repaint h in
  check int "resized frame" (100 * 80 * 4) (Bytes.length pixels);
  check bool "clean again" false (Lui_host.wants_repaint h)

let test_set_hidden_marks_dirty () =
  let h = make () in
  ignore (Lui_host.repaint h);
  Lui_host.set_hidden h (Some (fun _ -> false));
  check bool "dirty after hidden" true (Lui_host.wants_repaint h)

let test_backend_profile () =
  let h = make () in
  let b = Lui_host.backend h (Lui_protocol.generic_profile ()) in
  check bool "apply through backend" true
    (b.apply_batch (batch [ CreateNode (9, Text) ]));
  check bool "host dirty" true (Lui_host.wants_repaint h)

let popup_host () =
  let hooks =
    { Lui_paint.default_hooks with
      layout = (fun _ ->
        Lui_paint.placement_of_rect (Lui_scene.rect 4. 4. 24. 20.)) }
  in
  let h = Lui_host.create ~hooks ~renderer:noop_renderer
    ~width:80 ~height:60 ~scale:1. () in
  ignore (Lui_host.apply_batch h (batch
    [ CreateNode (1, Column); CreateNode (2, Box);
      CreateNode (3, Popover); CreateNode (4, Box);
      CreateNode (5, Popover); CreateNode (6, Box);
      InsertChild (1, 2, 0); InsertChild (1, 3, 1);
      InsertChild (3, 4, 0); InsertChild (4, 5, 0);
      InsertChild (5, 6, 0);
      SetProp (2, BackgroundValue, StringValue "#00ff00");
      SetProp (4, BackgroundValue, StringValue "#ff0000");
      SetProp (6, BackgroundValue, StringValue "#0000ff") ]));
  h

let painted_color h r g b =
  List.exists (function
    | Lui_scene.Fill f -> f.fcolor = Lui_scene.color r g b 255
    | _ -> false) (Lui_host.scene h).Lui_scene.ops

let test_hidden_popup_first_frame () =
  let h = popup_host () in
  Lui_host.set_hidden h (Some (fun id -> id = 3));
  ignore (Lui_host.repaint h);
  check bool "unrelated content paints" true (painted_color h 0 255 0);
  check bool "closed menu content does not paint" false (painted_color h 255 0 0);
  check bool "nested promoted popup cannot escape hidden ancestor" false
    (painted_color h 0 0 255)

let test_hidden_popup_retained_toggle () =
  let h = popup_host () in
  ignore (Lui_host.repaint h);
  check bool "open content paints" true (painted_color h 255 0 0);
  for _ = 1 to 3 do
    Lui_host.set_hidden h (Some (fun id -> id = 3));
    ignore (Lui_host.repaint h);
    check bool "cached content is removed on close" false (painted_color h 255 0 0);
    check bool "cached nested popup is removed on close" false (painted_color h 0 0 255);
    Lui_host.set_hidden h None;
    ignore (Lui_host.repaint h);
    check bool "content returns on reopen" true (painted_color h 255 0 0);
    check bool "nested popup returns on reopen" true (painted_color h 0 0 255)
  done

let test_hidden_preserves_wire_visibility () =
  let h = popup_host () in
  ignore (Lui_host.apply_batch h (batch [SetProp (3, Visible, BoolValue false)]));
  Lui_host.set_hidden h None;
  ignore (Lui_host.repaint h);
  check bool "wire-hidden content stays hidden" false (painted_color h 255 0 0);
  check bool "wire-hidden nested popup stays hidden" false (painted_color h 0 0 255)

let split_value h =
  match Lui_store.prop (Lui_host.store h) 1 "value" with
  | Some (FloatValue value) -> value
  | _ -> fail "split value missing"

let animated_split () =
  let h = make () in
  Lui_host.tick h ~now:0.;
  ignore (Lui_host.apply_batch h (batch
    [CreateNode (1, Split); SetProp (1, ResizeDuration, IntValue 120);
     SetProp (1, ResizeEasing, StringValue "standard");
     SetProp (1, ProgressValue, FloatValue 0.2)]));
  ignore (Lui_host.repaint h);
  check (float 0.00001) "initial geometry is immediate" 0.2 (split_value h);
  h

let test_split_transition () =
  let h = animated_split () in
  Lui_host.tick h ~now:1.;
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.8)]));
  check (float 0.00001) "toggle starts at current geometry" 0.2 (split_value h);
  Lui_host.tick h ~now:1.06;
  let value = split_value h in
  check bool "halfway geometry is between the endpoints" true (value > 0.2 && value < 0.8);
  ignore (Lui_host.repaint h);
  check bool "animation requests another frame" true (Lui_host.wants_repaint h);
  Lui_host.tick h ~now:1.13;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "duration ends at the exact target" 0.8 (split_value h);
  check bool "completed motion leaves the host idle" false (Lui_host.wants_repaint h)

let test_split_reversal_and_removal () =
  let h = animated_split () in
  Lui_host.tick h ~now:1.;
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.8)]));
  Lui_host.tick h ~now:1.06;
  let previous = split_value h in
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.1)]));
  check (float 0.00001) "reverse starts from the current displayed value" previous (split_value h);
  Lui_host.tick h ~now:1.2;
  check (float 0.00001) "reverse reaches its new target" 0.1 (split_value h);
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.9); DropNode 1]));
  Lui_host.tick h ~now:1.4;
  ignore (Lui_host.repaint h);
  check bool "removed animation leaves no scheduled work" false (Lui_host.wants_repaint h);
  ignore (Lui_host.apply_batch h (batch [CreateNode (1, Split);
    SetProp (1, ProgressValue, FloatValue 0.5)]));
  Lui_host.tick h ~now:2.;
  check (float 0.00001) "reused id does not inherit a disposed transition" 0.5 (split_value h)

let test_split_reduced_motion_and_drag () =
  let h = animated_split () in
  Lui_host.tick h ~now:1.;
  Lui_host.set_reduced_motion h true;
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.8)]));
  check (float 0.00001) "reduced motion changes geometry immediately" 0.8 (split_value h);
  Lui_host.set_reduced_motion h false;
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.2)]));
  Lui_host.tick h ~now:1.06;
  Lui_host.set_reduced_motion h true;
  check (float 0.00001) "enabling reduced motion finishes active transitions" 0.2 (split_value h);
  Lui_host.set_reduced_motion h false;
  Lui_store.apply_op (Lui_host.store h) (SetProp (1, ProgressValue, FloatValue 0.6));
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ProgressValue, FloatValue 0.6)]));
  ignore (Lui_host.repaint h);
  check bool "pointer drag feedback does not create eased catch-up" false (Lui_host.wants_repaint h);
  ignore (Lui_host.apply_batch h (batch [SetProp (1, ResizeDuration, IntValue 0);
    SetProp (1, ProgressValue, FloatValue 0.4)]));
  check (float 0.00001) "zero duration updates immediately" 0.4 (split_value h)

let popup_fill h =
  List.find_map
    (function
      | Lui_scene.Fill fill when fill.fcolor = Lui_scene.color 255 0 0 255 ->
          Some fill
      | _ -> None)
    (Lui_host.scene h).Lui_scene.ops

let popup_alpha h =
  match popup_fill h with Some fill -> fill.fopacity | None -> 0.

let test_popup_motion () =
  List.iter
    (fun kind ->
      let h = popup_host () in
      ignore (Lui_host.apply_batch h (batch [ DropNode 5 ]));
      (* Recreate the surface to exercise each native presentation kind. *)
      ignore
        (Lui_host.apply_batch h
           (batch
              [
                CreateNode (3, kind);
                InsertChild (1, 3, 1);
                CreateNode (4, Box);
                InsertChild (3, 4, 0);
                SetProp (4, BackgroundValue, StringValue "#ff0000");
              ]));
      Lui_host.tick h ~now:10.;
      ignore (Lui_host.repaint h);
      check (float 0.00001) "surface starts transparent" 0. (popup_alpha h);
      check bool "entrance schedules frames" true (Lui_host.wants_repaint h);
      Lui_host.tick h ~now:10.075;
      ignore (Lui_host.repaint h);
      let alpha = popup_alpha h in
      check bool "surface fades during entrance" true (alpha > 0. && alpha < 1.);
      (match popup_fill h with
      | Some fill ->
          check bool "surface zoom stays near final geometry" true
            (fill.frect.w > 22.8 && fill.frect.w < 24.)
      | None -> fail "entering surface has no visual shell");
      Lui_host.tick h ~now:10.25;
      ignore (Lui_host.repaint h);
      check (float 0.00001) "entrance settles exactly" 1. (popup_alpha h);
      check bool "settled surface leaves host idle" false
        (Lui_host.wants_repaint h);
      ignore (Lui_host.apply_batch h (batch [ DetachSubtree 3 ]));
      ignore (Lui_host.repaint h);
      check bool "exit does not retain interactive store nodes" false
        (Lui_store.mem (Lui_host.store h) 3);
      check (float 0.00001) "exit keeps its initial visual shell" 1.
        (popup_alpha h);
      Lui_host.tick h ~now:10.325;
      ignore (Lui_host.repaint h);
      check bool "removed surface fades out" true
        (popup_alpha h > 0. && popup_alpha h < 1.);
      Lui_host.tick h ~now:10.5;
      ignore (Lui_host.repaint h);
      check bool "exit releases visual shell" true (popup_fill h = None);
      check bool "exit leaves no scheduled frames" false
        (Lui_host.wants_repaint h))
    [ Popover; DropdownMenu; ContextMenu; Dialog ]

let test_popup_motion_reversal () =
  let h = popup_host () in
  Lui_host.tick h ~now:0.;
  ignore (Lui_host.repaint h);
  Lui_host.tick h ~now:0.08;
  ignore (Lui_host.repaint h);
  let before = popup_alpha h in
  Lui_host.set_hidden h (Some (fun id -> id = 3));
  ignore (Lui_host.repaint h);
  check (float 0.00001) "closing starts from displayed opacity" before
    (popup_alpha h);
  Lui_host.tick h ~now:0.12;
  ignore (Lui_host.repaint h);
  let closing = popup_alpha h in
  check bool "interrupted entrance fades down" true
    (closing > 0. && closing < before);
  Lui_host.set_hidden h None;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reopen reverses without flashing" closing
    (popup_alpha h);
  Lui_host.resize h ~width:100 ~height:80 ~scale:1.;
  Lui_host.tick h ~now:0.16;
  ignore (Lui_host.repaint h);
  check bool "resizing preserves motion progress" true (popup_alpha h > closing);
  Lui_host.tick h ~now:1.;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reversal finishes opaque" 1. (popup_alpha h);
  check bool "reversal settles" false (Lui_host.wants_repaint h)

let test_popup_motion_reduced () =
  let h = popup_host () in
  Lui_host.tick h ~now:0.;
  ignore (Lui_host.repaint h);
  Lui_host.tick h ~now:0.05;
  ignore (Lui_host.repaint h);
  Lui_host.set_reduced_motion h true;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reduced motion completes entrance" 1. (popup_alpha h);
  check bool "reduced motion stops frames" false (Lui_host.wants_repaint h);
  Lui_host.set_hidden h (Some (fun id -> id = 3));
  ignore (Lui_host.repaint h);
  check bool "reduced motion removes shell immediately" true
    (popup_fill h = None);
  Lui_host.set_hidden h None;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reduced motion opens immediately" 1. (popup_alpha h)

let test_popup_reused_id () =
  let h = popup_host () in
  Lui_host.tick h ~now:0.;
  ignore (Lui_host.repaint h);
  Lui_host.tick h ~now:1.;
  ignore (Lui_host.repaint h);
  ignore (Lui_host.apply_batch h (batch [ DetachSubtree 3 ]));
  ignore (Lui_host.repaint h);
  ignore
    (Lui_host.apply_batch h
       (batch
          [
            CreateNode (3, Popover);
            InsertChild (1, 3, 1);
            CreateNode (4, Box);
            InsertChild (3, 4, 0);
            SetProp (4, BackgroundValue, StringValue "#ff0000");
          ]));
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reused id starts a fresh presentation" 0.
    (popup_alpha h)

let transition_host transition =
  let h = popup_host () in
  ignore
    (Lui_host.apply_batch h
       (batch [ DropNode 5; SetProp (3, Transition, StringValue transition) ]));
  h

let motion_frame h now =
  Lui_host.tick h ~now;
  ignore (Lui_host.repaint h)

let popup_width h =
  match popup_fill h with Some fill -> fill.frect.w | None -> 0.

let test_popup_declared_tracks () =
  let h = transition_host "opacity 250ms linear, transform 0.5s linear 100ms" in
  motion_frame h 0.;
  motion_frame h 0.05;
  check (float 0.00001) "declared opacity duration" 0.2 (popup_alpha h);
  check (float 0.00001) "transform waits for its own delay" 22.8 (popup_width h);
  motion_frame h 0.25;
  check (float 0.00001) "opacity finishes independently" 1. (popup_alpha h);
  check (float 0.00001) "zoom keeps its own progress" 23.16 (popup_width h);
  check bool "unfinished transform still schedules frames" true
    (Lui_host.wants_repaint h);
  motion_frame h 0.601;
  check (float 0.00001) "transform finishes at its declared deadline" 24.
    (popup_width h);
  check bool "finished tracks leave host idle" false (Lui_host.wants_repaint h);
  ignore (Lui_host.apply_batch h (batch [ DetachSubtree 3 ]));
  ignore (Lui_host.repaint h);
  motion_frame h 0.651;
  check (float 0.00001) "detached opacity uses declared exit timing" 0.8
    (popup_alpha h);
  check (float 0.00001) "exit transform observes its delay" 24. (popup_width h);
  check bool "detached shell has no interactive store node" false
    (Lui_store.mem (Lui_host.store h) 3);
  motion_frame h 1.202;
  check bool "last exit track releases the shell" true (popup_fill h = None);
  check bool "last exit track stops scheduled frames" false
    (Lui_host.wants_repaint h)

let test_popup_declared_easing () =
  List.iter
    (fun (easing, expected) ->
      let h = transition_host ("opacity 1s " ^ easing) in
      motion_frame h 0.;
      motion_frame h 0.5;
      check (float 0.00001)
        (easing ^ " opacity matches CSS")
        expected (popup_alpha h);
      check (float 0.00001) "undeclared transform snaps to final geometry" 24.
        (popup_width h))
    [
      ("linear", 0.5);
      ("ease", 0.8024033876);
      ("ease-in", 0.3153568125);
      ("ease-out", 0.6846431875);
      ("ease-in-out", 0.5);
      ("cubic-bezier(0.25, 0.1, 0.25, 1)", 0.8024033876);
      ("steps(4)", 0.5);
      ("steps(4, start)", 0.75);
      ("steps(4, jump-end)", 0.5);
      ("steps(4, jump-none)", 2. /. 3.);
      ("steps(4, jump-both)", 0.6);
      ("step-start", 1.);
      ("step-end", 0.);
    ];
  let h =
    transition_host
      "opacity 1s cubic-bezier(0.2, 2, 0.2, 2), transform 1s cubic-bezier(0.2, \
       2, 0.2, 2)"
  in
  motion_frame h 0.;
  motion_frame h 0.5;
  check (float 0.00001) "overshooting opacity is clamped" 1. (popup_alpha h);
  check bool "transform can overshoot independently" true (popup_width h > 24.);
  check bool "an early endpoint value does not finish the timeline" true
    (Lui_host.wants_repaint h)

let test_popup_transition_channels () =
  List.iter
    (fun declaration ->
      let h = transition_host declaration in
      motion_frame h 0.;
      check (float 0.00001) "disabled channels are opaque immediately" 1.
        (popup_alpha h);
      check (float 0.00001) "disabled channels do not zoom" 24. (popup_width h);
      check bool "disabled channels do not schedule frames" false
        (Lui_host.wants_repaint h))
    [ "opacity 0ms, transform 0ms"; "background-color 200ms ease" ];
  let h = transition_host "transform 200ms linear" in
  motion_frame h 0.;
  motion_frame h 0.1;
  check (float 0.00001) "undeclared opacity stays opaque" 1. (popup_alpha h);
  check (float 0.00001) "transform-only declaration still zooms" 23.4
    (popup_width h);
  let h = transition_host "all 240ms linear, opacity linear 120ms" in
  motion_frame h 0.;
  motion_frame h 0.06;
  check (float 0.00001) "last matching declaration wins for opacity" 0.5
    (popup_alpha h);
  check (float 0.00001) "all still controls transform" 23.1 (popup_width h);
  let h = transition_host "opacity 120ms linear, all 240ms linear" in
  motion_frame h 0.;
  motion_frame h 0.06;
  check (float 0.00001) "later all overrides a specific declaration" 0.25
    (popup_alpha h)

let test_popup_transition_reversal () =
  let h = transition_host "opacity 120ms linear, transform 120ms linear" in
  motion_frame h 0.;
  motion_frame h 0.06;
  check (float 0.00001) "entrance reaches half" 0.5 (popup_alpha h);
  Lui_host.set_hidden h (Some (fun id -> id = 3));
  ignore (Lui_host.repaint h);
  check (float 0.00001) "close preserves displayed opacity" 0.5 (popup_alpha h);
  motion_frame h 0.09;
  check (float 0.00001) "reversed track shortens to the remaining distance" 0.25
    (popup_alpha h);
  Lui_host.set_hidden h None;
  ignore (Lui_host.repaint h);
  check (float 0.00001) "reopen preserves displayed opacity" 0.25
    (popup_alpha h);
  motion_frame h 0.181;
  check (float 0.00001) "second reversal keeps its shortened deadline" 1.
    (popup_alpha h);
  check bool "reversal leaves no idle animation" false
    (Lui_host.wants_repaint h);
  let h = transition_host "opacity 0ms 50ms, transform 0ms 50ms" in
  motion_frame h 0.;
  motion_frame h 0.025;
  check (float 0.00001) "zero duration retains a positive delay" 0.
    (popup_alpha h);
  check bool "delayed jump schedules its deadline" true
    (Lui_host.wants_repaint h);
  motion_frame h 0.051;
  check (float 0.00001) "delayed jump finishes" 1. (popup_alpha h);
  check bool "delayed jump settles" false (Lui_host.wants_repaint h);
  let h = transition_host "opacity 10s 10s, transform 10s 10s" in
  Lui_host.set_reduced_motion h true;
  motion_frame h 0.;
  check (float 0.00001) "reduced motion bypasses declared delay" 1.
    (popup_alpha h);
  check bool "reduced motion keeps the host idle" false
    (Lui_host.wants_repaint h)

let test_popup_transition_refresh () =
  let h = transition_host "opacity 1s linear, transform 1s linear" in
  motion_frame h 0.;
  motion_frame h 0.25;
  ignore
    (Lui_host.apply_batch h
       (batch
          [
            SetProp
              ( 3,
                Transition,
                StringValue "opacity 200ms linear, transform 200ms linear" );
          ]));
  ignore (Lui_host.repaint h);
  motion_frame h 0.5;
  check (float 0.00001) "changing the recipe does not restart active tracks" 0.5
    (popup_alpha h);
  Lui_host.set_hidden h (Some (fun id -> id = 3));
  ignore (Lui_host.repaint h);
  motion_frame h 0.601;
  check bool "exit uses the latest recipe and shortened distance" true
    (popup_fill h = None);
  List.iter
    (fun easing ->
      let h = transition_host ("opacity 100ms " ^ easing) in
      check_raises "invalid native timing does not silently pick another curve"
        (Invalid_argument ("Invalid native transition easing: " ^ easing))
        (fun () -> motion_frame h 0.))
    [ "nonsense"; "cubic-bezier(2, 0, 0, 1)"; "steps(1, jump-none)" ]

let test_popup_invalid_time () =
  List.iter
    (fun declaration ->
      check bool "unitless transition times are rejected by the shared protocol" false
        (property_value_supported Transition (StringValue declaration)))
    [ "opacity 0"; "opacity 0 50ms"; "opacity 100ms 0" ]

let () =
  run "lui_host"
    [ ("motion", [test_case "popup enter and exit" `Quick test_popup_motion;
                    test_case "popup reversal and resize" `Quick test_popup_motion_reversal;
                    test_case "popup reduced motion" `Quick test_popup_motion_reduced;
                    test_case "popup reused id" `Quick test_popup_reused_id;
                    test_case "declared popup tracks" `Quick test_popup_declared_tracks;
                    test_case "declared popup easing" `Quick test_popup_declared_easing;
                    test_case "declared popup channels" `Quick test_popup_transition_channels;
                    test_case "declared popup reversal" `Quick test_popup_transition_reversal;
                    test_case "declared popup refresh" `Quick test_popup_transition_refresh;
                    test_case "invalid popup time" `Quick test_popup_invalid_time;
                    test_case "split transition" `Quick test_split_transition;
                    test_case "split reversal and removal" `Quick test_split_reversal_and_removal;
                    test_case "reduced motion and drag" `Quick test_split_reduced_motion_and_drag]);
      ( "dirty",
        [ test_case "create clean" `Quick test_create_clean;
          test_case "apply marks dirty" `Quick test_apply_marks_dirty;
          test_case "repaint clears" `Quick test_repaint_clears_dirty;
          test_case "resize marks dirty" `Quick test_resize_marks_dirty;
          test_case "set_hidden marks dirty" `Quick test_set_hidden_marks_dirty
        ] );
      ( "backend",
        [ test_case "backend apply" `Quick test_backend_profile ] );
      ( "visibility",
        [ test_case "closed popup first frame" `Quick test_hidden_popup_first_frame;
          test_case "retained popup toggle" `Quick test_hidden_popup_retained_toggle;
          test_case "wire visibility" `Quick test_hidden_preserves_wire_visibility ] ) ]
