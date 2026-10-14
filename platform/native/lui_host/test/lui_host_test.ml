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

let () =
  run "lui_host"
    [ ( "dirty",
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
