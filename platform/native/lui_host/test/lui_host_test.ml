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
        [ test_case "backend apply" `Quick test_backend_profile ] ) ]
