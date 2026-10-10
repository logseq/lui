open Alcotest
open Lui_scene

let store () = Lui_store.create ()

let apply t ops = Lui_store.apply_batch t { Lui_protocol.generation = 1; ops }

let test_hex () =
  check bool "#rgb" true
    (Lui_paint.color_of_hex "#fff" = Some (color 255 255 255 255));
  check bool "#rrggbb" true
    (Lui_paint.color_of_hex "#121212" = Some (color 18 18 18 255));
  check bool "#rrggbbaa" true
    (Lui_paint.color_of_hex "#ff000080" = Some (color 255 0 0 128));
  check bool "theme name" true (Lui_paint.color_of_hex "bar" = None)

let test_edges () =
  check bool "one" true (Lui_paint.edges_of_floats [4.] = (4., 4., 4., 4.));
  check bool "two" true (Lui_paint.edges_of_floats [1.; 2.] = (1., 2., 1., 2.));
  check bool "four" true
    (Lui_paint.edges_of_floats [1.; 2.; 3.; 4.] = (1., 2., 3., 4.))

let hooks ?(layout = fun _ -> rect 0. 0. 100. 40.) () =
  { Lui_paint.color_of = (fun _ -> None);
    layout;
    text_ops = (fun _ _ _ _ -> []);
    image_of = (fun _ -> None);
    shadow_of = (fun _ -> None) }

let scene () =
  Lui_scene.create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:64)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:64 ~h:64)

let test_fill_op () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, CornerRadius, StringValue "8") ];
  let s = scene () in
  Lui_paint.paint (hooks ()) t s ~width:200 ~height:200 ~scale:1. ~clear:(color 0 0 0 0);
  match s.ops with
  | [ Fill f ] ->
    check int "red" 255 f.fcolor.r;
    (match f.fradii with
     | (tl, _, _, _) -> check bool "radius" true (tl = 8.))
  | _ -> fail "expected one Fill op"

let test_children_order () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column); CreateNode (2, ViewThatFits);
      CreateNode (3, ViewThatFits);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      SetProp (3, BackgroundValue, StringValue "#00ff00");
      InsertChild (1, 2, 0); InsertChild (1, 3, 1) ];
  let s = scene () in
  Lui_paint.paint (hooks ()) t s ~width:100 ~height:100 ~scale:1. ~clear:(color 0 0 0 0);
  match s.ops with
  | [Fill a; Fill b] ->
    check int "first red" 255 a.fcolor.r;
    check int "second green" 255 b.fcolor.g
  | _ -> fail "expected two Fill ops in paint order"

let test_invisible () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, Visible, BoolValue false) ];
  let s = scene () in
  Lui_paint.paint (hooks ()) t s ~width:100 ~height:100 ~scale:1. ~clear:(color 0 0 0 0);
  check int "no ops" 0 (List.length s.ops)

let test_clip () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Scroll);
      CreateNode (2, ViewThatFits);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let s = scene () in
  Lui_paint.paint (hooks ()) t s ~width:100 ~height:100 ~scale:1. ~clear:(color 0 0 0 0);
  match s.ops with
  | [Push_clip _; Fill _; Pop_clip] -> ()
  | _ -> fail "expected clip-wrapped fill"

let () =
  run "lui_paint"
    [ ("color",
       [ test_case "hex" `Quick test_hex;
         test_case "edges" `Quick test_edges ]);
      ("ops",
       [ test_case "fill" `Quick test_fill_op;
         test_case "order" `Quick test_children_order;
         test_case "invisible" `Quick test_invisible;
         test_case "clip" `Quick test_clip ]) ]
