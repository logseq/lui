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
  check bool "three" true
    (Lui_paint.edges_of_floats [1.; 2.; 3.] = (1., 2., 3., 2.));
  check bool "four" true
    (Lui_paint.edges_of_floats [1.; 2.; 3.; 4.] = (1., 2., 3., 4.))

let default_layout = fun _ -> Lui_paint.placement_of_rect (rect 0. 0. 100. 40.)

let hooks ?(layout = default_layout) () =
  { Lui_paint.default_hooks with
    layout;
    shadow_of = Lui_paint.parse_shadows (fun _ -> None) }

let scene () =
  Lui_scene.create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:64)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:64 ~h:64)

let paint_with h t ?(width = 200) ?(height = 200) ?(scale = 1.)
    ?spatial () =
  let s = scene () in
  Lui_paint.paint ?spatial h t s ~width ~height ~scale
    ~clear:(color 0 0 0 0);
  s

let test_select_indicator () =
  List.iter
    (fun kind ->
      List.iter
        (fun scale ->
          let t = store () in
          apply t
            [
              Lui_protocol.CreateNode (1, kind);
              SetProp (1, BorderWidth, IntValue 1);
              SetProp (1, TextValue, StringValue "A very long language name");
            ];
          let image = new_image ~w:1 ~h:1 (Bytes.make 4 '\255') in
          let requested = ref None and text_rect = ref None in
          let r =
            rect (20. *. scale) (10. *. scale) (256. *. scale) (32. *. scale)
          in
          let h =
            {
              (hooks ~layout:(fun _ -> Lui_paint.placement_of_rect r) ()) with
              Lui_paint.image_in =
                (fun _ slot ->
                  requested := Some slot;
                  Some image);
              text_ops =
                (fun _ region _ _ ->
                  text_rect := Some region;
                  []);
            }
          in
          let s = paint_with h t ~width:600 ~height:160 ~scale () in
          let expected =
            rect (247. *. scale) (18. *. scale) (16. *. scale) (16. *. scale)
          in
          check bool "select requests a trailing sixteen-point indicator" true
            (!requested = Some (rect 247. 18. 16. 16.));
          let images =
            List.filter_map (function Image i -> Some i | _ -> None) s.ops
          in
          check int "indicator painted exactly once" 1 (List.length images);
          check bool "indicator retains the requested slot" true
            ((List.hd images).irect2 = expected);
          let label = Option.get !text_rect in
          check bool "label ends before the icon" true
            (label.x +. label.w <= expected.x);
          check bool "label is clipped away from the icon" true
            (List.exists
               (function Push_clip c -> c.crect = label | _ -> false)
               s.ops);
          apply t [ SetProp (1, Enabled, BoolValue false) ];
          let disabled = paint_with h t ~width:600 ~height:160 ~scale () in
          let opacity =
            List.find_map
              (function Image i -> Some i.iopacity | _ -> None)
              disabled.ops
          in
          check bool "disabled indicator follows control opacity" true
            (Option.get opacity < 1.);
          requested := None;
          let narrow =
            {
              h with
              Lui_paint.layout =
                (fun _ ->
                  Lui_paint.placement_of_rect
                    (rect (20. *. scale) (10. *. scale) (20. *. scale)
                       (32. *. scale)));
            }
          in
          ignore (paint_with narrow t ~width:600 ~height:160 ~scale ());
          check bool "a narrow control does not request an out-of-bounds icon"
            true (!requested = None))
        [ 1.; 2. ])
    [ Lui_protocol.Select; Combobox ]

let test_image_fill_crop () =
  List.iter
    (fun (width, height, expected) ->
      let t = store () in
      apply t
        [
          Lui_protocol.CreateNode (1, FileImage);
          SetProp (1, ImageFitValue, StringValue "fill");
        ];
      let image =
        new_image ~w:width ~h:height (Bytes.make (width * height * 4) '\255')
      in
      let hooks =
        { (hooks ()) with Lui_paint.image_of = (fun _ -> Some image) }
      in
      let scene = paint_with hooks t () in
      let op =
        List.find_map (function Image i -> Some i | _ -> None) scene.ops
        |> Option.get
      in
      check bool "fill preserves the destination" true
        (op.irect2 = rect 0. 0. 100. 40.);
      check bool "fill crops the source without distorting its aspect" true
        (op.isrc = expected))
    [
      (200, 40, rect 50. 0. 100. 40.);
      (100, 100, rect 0. 30. 100. 40.);
      (100, 40, rect 0. 0. 100. 40.);
    ]

let test_fill_op () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, CornerRadius, StringValue "8") ];
  let s = paint_with (hooks ()) t () in
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
  let s = paint_with (hooks ()) t ~width:100 ~height:100 () in
  match s.ops with
  | [Fill a; Fill b] ->
    check int "first red" 255 a.fcolor.r;
    check int "second green" 255 b.fcolor.g
  | _ -> fail "expected two Fill ops in paint order"

(* The mounted_children hook restricts the child walk to its window —
   the mechanism a virtual list uses to skip unmounted rows without
   the paint pass touching them at all. *)
let test_mounted_range () =
  let t = store () in
  apply t
    ([ Lui_protocol.CreateNode (1, VirtualList) ]
    @ List.flatten
        (List.init 10 (fun i ->
             [ Lui_protocol.CreateNode (10 + i, ListItem);
               SetProp (10 + i, BackgroundValue, StringValue "#ff0000");
               Lui_protocol.InsertChild (1, 10 + i, i) ])));
  let h =
    { (hooks ()) with
      Lui_paint.mounted_children =
        (fun id -> if id = 1 then Some [ 12; 13; 14 ] else None) }
  in
  let s = paint_with h t ~width:100 ~height:10000 () in
  let fills =
    List.filter (function Lui_scene.Fill _ -> true | _ -> false) s.ops
  in
  check int "sliced fills" 3 (List.length fills)

let test_invisible () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, Visible, BoolValue false) ];
  let s = paint_with (hooks ()) t ~width:100 ~height:100 () in
  check int "no ops" 0 (List.length s.ops)

let test_clip () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Scroll);
      CreateNode (2, ViewThatFits);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let s = paint_with (hooks ()) t ~width:100 ~height:100 () in
  match s.ops with
  | [Push_clip _; Fill _; Pop_clip] -> ()
  | _ -> fail "expected clip-wrapped fill"

(* ---------- fills ---------- *)

let test_gradient () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp
        (1, BackgroundValue,
          StringValue "linear-gradient(90deg, #ff0000, #0000ff)") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] ->
    check bool "linear" true (f.fpaint = Linear);
    check int "from red" 255 f.fcolor.r;
    check int "to blue" 255 f.fcolor2.b;
    (match f.fgradient with
     | (x0, y0, x1, y1) ->
       let near a b = Float.abs (a -. b) < 0.001 in
       check bool "direction" true
         (near x0 0. && near y0 0.5 && near x1 1. && near y1 0.5))
  | _ -> fail "expected one Fill op"

let test_gradient_variants () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp
        (1, BackgroundValue,
          StringValue "oklab-gradient(to right, #ff0000, #0000ff)");
      SetProp
        (2, BackgroundValue,
          StringValue "stripes(45deg, #ff0000, #0000ff)");
      InsertChild (1, 2, 0) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill a; Fill b ] ->
    check bool "oklab" true (a.fpaint = Oklab);
    check bool "stripes" true (b.fpaint = Stripes);
    (match b.fgradient with
     | (x0, _y0, x1, _y1) ->
       check bool "45deg" true (Float.abs (x0 -. 0.1464) < 0.001
                                && Float.abs (x1 -. 0.8535) < 0.001))
  | _ -> fail "expected two Fill ops"

let test_dashed_border () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BorderWidth, StringValue "2");
      SetProp (1, BorderColorValue, StringValue "#ff0000");
      SetExtensionProp (1, "border-style", StringValue "dashed") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] -> check bool "dashed" true f.fdashed
  | _ -> fail "expected one Fill op"

let test_per_edge_borders () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BorderWidth, StringValue "1 2 3 4");
      SetProp (1, BorderColorValue, StringValue "#ff0000") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] ->
    check bool "widths" true (f.fborder = (1., 2., 3., 4.))
  | _ -> fail "expected one Fill op"

let test_per_edge_border_colors () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BorderWidth, StringValue "1");
      SetProp
        (1, BorderColorValue, StringValue "#ff0000 #00ff00") ];
  let s = paint_with (hooks ()) t () in
  (* two colors → one border fill per edge, each carrying its color *)
  match s.ops with
  | [ Fill t'; Fill r'; Fill b'; Fill l' ] ->
    check int "top red" 255 t'.fborder_color.r;
    check int "right green" 255 r'.fborder_color.g;
    check int "bottom red" 255 b'.fborder_color.r;
    check int "left green" 255 l'.fborder_color.g;
    check bool "top width" true (t'.fborder = (1., 0., 0., 0.))
  | _ -> fail "expected four edge fills"

(* ---------- shadows ---------- *)

let test_shadow_parse () =
  let resolve = function "ring" -> Some (color 0 120 255 255) | _ -> None in
  (match Lui_paint.parse_shadows resolve "0 2px 4px #00000080" with
   | [ (sp : Lui_paint.shadow_spec) ] ->
     check bool "dx" true (sp.dx = 0.);
     check bool "dy" true (sp.dy = 2.);
     check bool "blur" true (sp.blur = 4.);
     check bool "alpha" true (sp.scolor.a = 128);
     check bool "outset" true (not sp.inset)
   | _ -> fail "shadow parse failed");
  (match Lui_paint.parse_shadows resolve "inset 0 0 0 2px ring" with
   | [ (sp : Lui_paint.shadow_spec) ] ->
     check bool "inset" true sp.inset;
     check bool "spread" true (sp.spread = 2.);
     check int "ring blue" 255 sp.scolor.b
   | _ -> fail "inset parse failed");
  (match Lui_paint.parse_shadows resolve "0 1px 0 red inset, 0 -1px 0 blue inset" with
   | [ a; b ] ->
     check bool "two layers" true (a.inset && b.inset);
     check bool "css order kept" true (a.dy = 1. && b.dy = -1.)
   | _ -> fail "multi-layer parse failed");
  check bool "none" true
    (Lui_paint.parse_shadows resolve "none" = [])

let test_shadow_op () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ffffff");
      SetProp (1, Shadow, StringValue "0 2px 4px #00000080") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Shadow sh; Fill _ ] ->
    check bool "dy" true (sh.srect.y = 2.);
    check bool "blur" true (sh.sblur = 4.);
    check bool "not inset" true (not sh.sinset)
  | _ -> fail "expected shadow then fill"

let test_inset_shadow_op () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ffffff");
      SetProp (1, Shadow, StringValue "inset 0 0 0 2px #000000") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill _; Shadow sh ] ->
    check bool "inset" true sh.sinset;
    (* spread 2 deflates the shadow rect by 2 on every side *)
    check bool "deflate" true
      (sh.srect.x = 2. && sh.srect.w = 96.)
  | _ -> fail "expected fill then inset shadow"

(* ---------- state ---------- *)

let test_state_background () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, HoverBackground, StringValue "#00ff00") ];
  let h =
    { (hooks ()) with
      Lui_paint.state_of =
        (fun _ -> { Lui_paint.state_neutral with hovered = true }) }
  in
  let s = paint_with h t () in
  match s.ops with
  | [ Fill f ] -> check int "hover green" 255 f.fcolor.g
  | _ -> fail "expected one Fill op"

let test_state_precedence () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, Shadow, StringValue "0 0 0 1px #000000");
      SetProp (1, HoverShadow, StringValue "0 0 0 2px #000000");
      SetProp (1, PressedShadow, StringValue "0 0 0 3px #000000") ];
  let h =
    { (hooks ()) with
      Lui_paint.state_of =
        (fun _ ->
          { Lui_paint.state_neutral with hovered = true; pressed = true }) }
  in
  let s = paint_with h t () in
  match s.ops with
  | [ Shadow sh ] ->
    (* pressed comes after hover in the cascade *)
    check bool "pressed wins" true (sh.srect.w = 106.)
  | _ -> fail "expected one Shadow op"

let test_selected_shadow () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, ListItem);
      SetProp (1, Selected, BoolValue true);
      SetProp (1, Shadow, StringValue "0 0 0 1px #000000");
      SetProp (1, SelectedHoverShadow, StringValue "0 0 0 2px #000000") ];
  let h =
    { (hooks ()) with
      Lui_paint.state_of =
        (fun _ -> { Lui_paint.state_neutral with hovered = true }) }
  in
  let s = paint_with h t () in
  (* the list item also gains its selected accent fill from default
     chrome; the shadow assertion still checks the one Shadow op *)
  match List.filter_map (function Lui_scene.Shadow sh -> Some sh | _ -> None) s.ops with
  | [ sh ] -> check bool "sel+hover" true (sh.srect.w = 104.)
  | _ -> fail "expected one Shadow op"

let test_disabled_opacity () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Button);
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (1, Enabled, BoolValue false);
      SetProp (1, DisabledOpacity, FloatValue 0.5) ];
  let s = paint_with (hooks ()) t () in
  (* a view-styled background owns the whole surface: no default border
     is added, and the fill carries the disabled opacity *)
  match s.ops with
  | [ Fill bg ] -> check bool "half opacity" true (bg.fopacity = 0.5)
  | _ -> fail "expected bg fill only"

(* ---------- compositing ---------- *)

let test_opacity_multiply () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp (1, Opacity, FloatValue 0.5);
      SetProp (2, Opacity, FloatValue 0.5);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] -> check bool "quarter" true (f.fopacity = 0.25)
  | _ -> fail "expected one Fill op"


let test_viewport_cull () =
  (* Two stacked columns: only the on-screen one should emit a Fill. *)
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column); CreateNode (3, Column);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      SetProp (3, BackgroundValue, StringValue "#00ff00");
      InsertChild (1, 2, 0); InsertChild (1, 3, 1) ];
  let layout = function
    | 1 -> Lui_paint.placement_of_rect (rect 0. 0. 100. 200.)
    | 2 -> Lui_paint.placement_of_rect (rect 0. 0. 100. 40.)
    | 3 -> Lui_paint.placement_of_rect (rect 0. 500. 100. 40.) (* offscreen *)
    | _ -> Lui_paint.placement_of_rect (rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  let fills =
    List.filter_map (function Lui_scene.Fill f -> Some f | _ -> None) s.ops
  in
  check int "one on-screen fill" 1 (List.length fills);
  match fills with
  | [ f ] -> check int "red on-screen" 255 f.fcolor.r
  | _ -> fail "expected the on-screen fill only"

(* ---------- culling: node-not-drawn vs subtree-invisible ---------- *)

let layout_map f = fun id -> Lui_paint.placement_of_rect (f id)

(* A parent whose box misses the frame emits no chrome, but its
   subtree is NOT culled: an overflow:visible child laid out inside
   the viewport still paints. *)
let test_cull_escape_child () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 0. 500. 100. 40. (* parent offscreen *)
      | 2 -> rect 0. 50. 100. 40.  (* child inside the frame *)
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  match s.ops with
  | [ Fill _ ] -> ()
  | _ -> fail "expected the escaped child's fill"

(* A position:fixed descendant resolves against the frame, so it can
   paint even when its parent's box is entirely offscreen. *)
let test_cull_escape_fixed () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp (2, Position, StringValue "fixed");
      SetProp (2, InsetTop, FloatValue 10.);
      SetProp (2, InsetLeft, FloatValue 10.);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 0. 500. 100. 40.
      | 2 -> rect 0. 0. 20. 20.
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  match s.ops with
  | [ Fill f ] ->
    check bool "fixed at frame inset" true (f.frect.x = 10. && f.frect.y = 10.)
  | _ -> fail "expected the fixed child's fill"

(* A popover inside an offscreen parent is still promoted and paints
   at its own coordinates. *)
let test_cull_escape_popup () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Popover);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 0. 500. 100. 40.
      | 2 -> rect 0. 60. 80. 30.
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  (* the popover paints its own chrome (shadow/fill) at y=60 — the
     offscreen parent contributes nothing *)
  let fills =
    List.filter_map (function Lui_scene.Fill f -> Some f | _ -> None) s.ops
  in
  match fills with
  | f :: _ -> check bool "popover painted" true (f.frect.y = 60.)
  | _ -> fail "expected the promoted popover's ops"

(* A scroll container entirely offscreen still culls its clipped
   children — that subtree is provably invisible. *)
let test_cull_dead_clip () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Scroll);
      CreateNode (2, Column);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 0. 500. 100. 100.
      | 2 -> rect 0. 510. 80. 30.
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  check int "dead clip culls" 0 (List.length s.ops)

(* But a promoted popup escapes even a dead clip: it is an overlay,
   not clipped content. *)
let test_cull_dead_clip_popup () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Scroll);
      CreateNode (2, Popover);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 0. 500. 100. 100.
      | 2 -> rect 0. 60. 80. 30.
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t ~width:200 ~height:200 () in
  let fills =
    List.filter_map (function Lui_scene.Fill f -> Some f | _ -> None) s.ops
  in
  match fills with
  | f :: _ -> check bool "popover painted" true (f.frect.y = 60.)
  | _ -> fail "expected the popover to escape the dead clip"

let test_zindex () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Stack);
      CreateNode (2, Column); CreateNode (3, Column);
      SetProp (2, ZIndex, IntValue 2);
      SetProp (3, ZIndex, IntValue 1);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      SetProp (3, BackgroundValue, StringValue "#00ff00");
      InsertChild (1, 2, 0); InsertChild (1, 3, 1) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill a; Fill b ] ->
    check int "z1 first" 255 a.fcolor.g;
    check int "z2 last" 255 b.fcolor.r
  | _ -> fail "expected z-ordered fills"

let test_display_contents () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp (1, DisplayValue, StringValue "contents");
      SetProp (1, BackgroundValue, StringValue "#ff0000");
      SetProp (2, BackgroundValue, StringValue "#00ff00");
      InsertChild (1, 2, 0) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] -> check int "child only" 255 f.fcolor.g
  | _ -> fail "expected only the child's fill"

(* ---------- placement ---------- *)

let test_position_absolute () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Column);
      SetProp (2, Position, StringValue "absolute");
      SetProp (2, InsetTop, FloatValue 5.);
      SetProp (2, InsetLeft, FloatValue 8.);
      SetProp (2, BackgroundValue, StringValue "#ff0000");
      InsertChild (1, 2, 0) ];
  let layout =
    layout_map (function
      | 1 -> rect 10. 10. 100. 50.
      | 2 -> rect 0. 0. 20. 20.
      | _ -> rect 0. 0. 0. 0.)
  in
  let s = paint_with (hooks ~layout ()) t () in
  match s.ops with
  | [ Fill f ] ->
    check bool "placed" true (f.frect.x = 18. && f.frect.y = 15.)
  | _ -> fail "expected placed fill"

let test_position_relative () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, Position, StringValue "relative");
      SetProp (1, InsetLeft, FloatValue 4.);
      SetProp (1, BackgroundValue, StringValue "#ff0000") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] -> check bool "shifted" true (f.frect.x = 4.)
  | _ -> fail "expected shifted fill"

let test_popup_xy () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Popover);
      SetProp (1, PopupX, FloatValue 30.);
      SetProp (1, PopupY, FloatValue 40.);
      SetProp (1, BackgroundValue, StringValue "#ff0000") ];
  let s = paint_with (hooks ()) t () in
  (* Popup x/y are anchor inputs the layout engine resolves into the
     node's rect — paint must not re-apply them over the layout
     result (the default hook reports (0,0 100x40)). *)
  match List.rev s.ops with
  | Fill f :: _ ->
    check bool "popup" true (f.frect.x = 0. && f.frect.y = 0.)
  | _ -> fail "expected popup fill"

let test_layout_override () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      SetProp (1, BackgroundValue, StringValue "#ff0000") ];
  let layout =
    fun _ ->
      { Lui_paint.p_rect = rect 0. 0. 10. 10.;
        p_override = Some (rect 7. 8. 10. 10.) }
  in
  let s = paint_with (hooks ~layout ()) t () in
  match s.ops with
  | [ Fill f ] ->
    check bool "override" true (f.frect.x = 7. && f.frect.y = 8.)
  | _ -> fail "expected override fill"

(* ---------- kinds ---------- *)

let test_divider () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Divider);
      SetProp (1, BorderColorValue, StringValue "#ff0000") ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] ->
    (* 100x40 horizontal → 1px-tall line centered vertically *)
    check bool "line" true (f.frect.h = 1. && f.frect.y = 19.5)
  | _ -> fail "expected divider fill"

let test_spacer () =
  let t = store () in
  apply t [ Lui_protocol.CreateNode (1, Spacer) ];
  let s = paint_with (hooks ()) t () in
  check int "no ops" 0 (List.length s.ops)

let test_progress () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Progress);
      SetProp (1, ProgressValue, FloatValue 0.25) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill track; Fill fill' ] ->
    check bool "track full" true (track.frect.w = 100.);
    check bool "fill quarter" true (fill'.frect.w = 25.)
  | _ -> fail "expected track + fill"

let test_checkbox () =
  let calls = ref [] in
  let h =
    { (hooks ()) with
      Lui_paint.text_ops = (fun _ _ _ s -> calls := s :: !calls; []) }
  in
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Checkbox);
      SetProp (1, Checked, BoolValue true) ];
  let s = paint_with h t () in
  (match s.ops with
   | [ Fill f ] ->
     (* checked: accent-filled control box *)
     check int "accent fill" 235 f.fcolor.b
   | _ -> fail "expected control fill");
  check bool "check glyph" true (List.mem "\xe2\x9c\x93" !calls)

let test_checkbox_unchecked () =
  let t = store () in
  apply t [ Lui_protocol.CreateNode (1, Checkbox) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill f ] ->
    check bool "bordered" true (f.fborder = (1., 1., 1., 1.));
    (* unchecked box now paints the page face inside its border *)
    check bool "page face" true (f.fcolor.a = 255)
  | _ -> fail "expected bordered box"

let test_switch () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, SwitchControl);
      SetProp (1, Checked, BoolValue true) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill track; Lui_scene.Shadow _; Fill thumb ] ->
    check bool "track accent" true (track.fcolor.b = 235);
    (* track right-aligned in 100x40: 36x20 at x=64; checked thumb
       (d=16) sits 2px off the right edge → x=82, wearing a shadow *)
    check bool "thumb right" true (thumb.frect.x = 82.)
  | _ -> fail "expected track + thumb shadow + thumb"

let test_radio () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Radio);
      SetProp (1, Checked, BoolValue true) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill outer; Fill inner ] ->
    check int "outer accent" 235 outer.fcolor.b;
    check bool "inner smaller" true (inner.frect.w < outer.frect.w)
  | _ -> fail "expected ring + dot"

let test_spinner () =
  let t = store () in
  apply t [ Lui_protocol.CreateNode (1, Spinner) ];
  let s = paint_with (hooks ()) t () in
  (* radial indicator: twelve fading dots *)
  check int "twelve dots" 12 (List.length s.ops);
  match s.ops with
  | Fill f :: _ -> check int "dot opaque" 255 f.fcolor.a
  | _ -> fail "expected dot fills"

let test_slider () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Slider);
      SetProp (1, ProgressValue, FloatValue 0.5) ];
  let s = paint_with (hooks ()) t () in
  match s.ops with
  | [ Fill track; Fill fill'; Lui_scene.Shadow _; Lui_scene.Shadow _;
      Fill thumb ] ->
    (* track insets 10px either side for knob travel *)
    check bool "track inset" true (track.frect.w = 80.);
    check bool "half fill" true (fill'.frect.w = 40.);
    (* 20x16 capsule knob centered at the fraction: cx=50 → x=40 *)
    check bool "thumb middle" true (thumb.frect.x = 40.)
  | _ -> fail "expected track + fill + thumb shadows + thumb"

let test_scrollbar () =
  let t = store () in
  apply t [ Lui_protocol.CreateNode (1, Scroll) ];
  let layout _ = Lui_paint.placement_of_rect (rect 0. 0. 100. 100.) in
  let h =
    { (hooks ~layout ()) with
      Lui_paint.scroll_of =
        (fun _ -> Some { Lui_paint.sm_offset = 0.; sm_extent = 0.5 }) }
  in
  let s = paint_with h t ~width:100 ~height:100 () in
  (* scroll container clips; the thumb is the last op inside the clip:
     6px wide, 2.5px off the right edge, half the height *)
  match List.rev s.ops with
  | Pop_clip :: Fill f :: _ ->
    check bool "thumb half" true (f.frect.h = 50.);
    check bool "right edge" true (f.frect.x = 91.5)
  | _ -> fail "expected thumb inside clip"

let test_extension () =
  let t = store () in
  apply t [ Lui_protocol.CreateExtension (1, "badge", "") ];
  let s = paint_with (hooks ()) t () in
  (* unregistered extension falls back to a box fill *)
  check int "fallback" 0 (List.length s.ops)

(* ---------- secure field ---------- *)

(* The strings the paint pass hands the text engine, in order. *)
let text_calls t =
  let calls = ref [] in
  let h =
    { (hooks ()) with
      Lui_paint.text_ops =
        (fun _ _ _ s ->
          calls := s :: !calls;
          []) }
  in
  ignore (paint_with h t ());
  List.rev !calls

let test_secure_masked () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, SecureField);
      SetProp (1, TextValue, StringValue "hunter2") ];
  let calls = text_calls t in
  (* The real text must never reach the renderer — only the bullet
     mask, one grapheme one bullet. *)
  check (list string) "mask only" [ "•••••••" ] calls

let test_secure_masked_graphemes () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, SecureField);
      SetProp
        (1, TextValue,
          StringValue
            "e\xcc\x81x\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9") ];
  (* "é"(combining) + "x" + ZWJ-joined pair: three graphemes. *)
  let calls = text_calls t in
  check (list string) "one bullet per grapheme" [ "•••" ] calls

let test_secure_placeholder_unmasked () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, SecureField);
      SetProp (1, PlaceholderValue, StringValue "password hint") ];
  let calls = text_calls t in
  (* the placeholder is a hint, not a secret — it stays readable *)
  check (list string) "placeholder readable" [ "password hint" ] calls

let test_secure_mask_units () =
  let bullets s = Lui_paint.secure_mask s in
  check string "ascii" "•••••••" (bullets "hunter2");
  check string "empty" "" (bullets "");
  (* combining mark attaches: "e" + U+0301 is one grapheme *)
  check string "combining" "•" (bullets "e\xcc\x81");
  (* precomposed counts the same *)
  check string "precomposed" "•" (bullets "\xc3\xa9");
  (* emoji modifier joins its base *)
  check string "skin tone" "•"
    (bullets "\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbb");
  (* ZWJ chain is one grapheme *)
  check string "zwj family" "•"
    (bullets
       "\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7");
  (* regional indicators pair per flag *)
  check string "two flags" "••"
    (bullets
       "\xf0\x9f\x87\xab\xf0\x9f\x87\xb7\xf0\x9f\x87\xba\xf0\x9f\x87\xb8");
  (* idempotent: masked bullets re-mask one-to-one *)
  check string "idempotent" "•••" (bullets "•••")

let test_secure_byte_of_masked () =
  let s = "hunter2" in
  check int "start" 0 (Lui_paint.secure_byte_of_masked s 0);
  check int "second char" 1 (Lui_paint.secure_byte_of_masked s 3);
  check int "end" 7 (Lui_paint.secure_byte_of_masked s 21);
  (* a masked offset past the end clamps to the text's end *)
  check int "clamp" 7 (Lui_paint.secure_byte_of_masked s 300);
  (* multibyte: "éx" is 2 graphemes, 4 bytes *)
  let m = "e\xcc\x81x" in
  check int "past composed" 3 (Lui_paint.secure_byte_of_masked m 3);
  check int "end composed" 4 (Lui_paint.secure_byte_of_masked m 6)

(* ---------- coverage ---------- *)

let test_coverage_table () =
  let names =
    List.map Lui_wire_schema.property_name Lui_wire_schema.all_properties
  in
  let missing =
    List.filter
      (fun n -> not (List.mem_assoc n Lui_paint.prop_coverage))
      names
  in
  check bool "all props classified" true (missing = [])

(* ---------- spatial index ---------- *)

(* Build an index over the same rects a layout-map hook hands the
   walk — integral rects so [rect_snap] is the identity. *)
let spatial_of store f =
  Lui_spatial.build Lui_paint.spatial_env store
    ~rect_of:(fun id -> f id)

let ops_of s = (s.ops, s.glyphs, s.wide)

let test_spatial_negative_bounds () =
  let t = store () in
  apply t [CreateNode (1, Column); CreateNode (2, Column); InsertChild (1,2,0)];
  let idx = spatial_of t (function
    | 1 -> rect (-100.) (-100.) 10. 10.
    | _ -> rect (-80.) (-80.) 20. 20.) in
  let root = Option.get (Lui_spatial.info idx 1) in
  check bool "Negative subtree bounds must not grow to the coordinate origin"
    true (root.b=rect (-100.) (-100.) 40. 40.);
  check bool "Fully scrolled-off subtrees must not enter the origin viewport"
    false (Lui_spatial.keep idx ~clip:None ~esc:false
      (Lui_spatial.Region (rect 0. 0. 100. 100.)) 1)

let test_spatial_build_allocation () =
  let t = store () in
  for id=1 to 1000 do
    Lui_store.apply_op t (CreateNode (id, Column));
    if id>1 then Lui_store.apply_op t (InsertChild (id-1,id,0))
  done;
  let bounds = rect 10. 20. 100. 80. in
  let env = {Lui_spatial.shown=(fun _ _ -> true); promotes=(fun _ _ -> false);
    ordered=Lui_store.children} in
  let build () = Lui_spatial.build env t ~rect_of:(fun _ -> bounds) in
  ignore (build ());
  let before = Gc.allocated_bytes () in
  let idx = build () in
  let allocated = Gc.allocated_bytes () -. before in
  check bool "Every subtree must retain its complete bounds" true
    ((Option.get (Lui_spatial.info idx 1)).b=bounds
     && (Option.get (Lui_spatial.info idx 1000)).b=bounds);
  Printf.printf "1000-node spatial snapshot allocated %.0f bytes\n%!" allocated;
  check bool "Spatial builds must not allocate mutable bounds and tuples for every node"
    true (allocated <= 150000.)

let test_spatial_paint_equiv () =
  (* Everything the cull must respect at once: a scroll clip with
     off-clip children, a promoted popup inside a fully offscreen
     parent, a hidden subtree, a display:contents wrapper, a zero-area
     spacer and z-reordered siblings. *)
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, Column);
      CreateNode (2, Scroll);
      CreateNode (3, Column); CreateNode (4, Column);
      CreateNode (5, Popover);
      CreateNode (6, Column); CreateNode (7, Spacer);
      CreateNode (8, Column); CreateNode (9, Column);
      CreateNode (10, Column); CreateNode (11, Column);
      SetProp (2, BackgroundValue, StringValue "#101010");
      SetProp (3, BackgroundValue, StringValue "#ff0000");
      SetProp (4, BackgroundValue, StringValue "#00ff00");
      SetProp (5, BackgroundValue, StringValue "#0000ff");
      SetProp (6, Visible, BoolValue false);
      SetProp (6, BackgroundValue, StringValue "#ffffff");
      SetProp (8, DisplayValue, StringValue "contents");
      SetProp (9, BackgroundValue, StringValue "#ffff00");
      SetProp (10, ZIndex, IntValue 2);
      SetProp (10, BackgroundValue, StringValue "#00ffff");
      SetProp (11, ZIndex, IntValue 1);
      SetProp (11, BackgroundValue, StringValue "#ff00ff");
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      InsertChild (4, 5, 0);
      InsertChild (1, 6, 1); InsertChild (1, 7, 2);
      InsertChild (1, 8, 3); InsertChild (8, 9, 0);
      InsertChild (1, 10, 4); InsertChild (1, 11, 5) ];
  let rects = function
    | 1 -> rect 0. 0. 200. 200.
    | 2 -> rect 0. 0. 200. 100.
    | 3 -> rect 0. 0. 200. 20.
    | 4 -> rect 0. 300. 200. 20.   (* fully offscreen + off-clip *)
    | 5 -> rect 10. 50. 60. 30.    (* promoted popup back onscreen *)
    | 6 -> rect 0. 100. 200. 50.
    | 7 -> rect 0. 150. 0. 0.
    | 8 -> rect 0. 160. 200. 40.
    | 9 -> rect 0. 160. 200. 40.
    | 10 -> rect 0. 20. 100. 100.
    | 11 -> rect 50. 20. 100. 100.
    | _ -> rect 0. 0. 0. 0.
  in
  let layout = layout_map rects in
  let idx = spatial_of t rects in
  let a = paint_with (hooks ~layout ()) t () in
  let b = paint_with (hooks ~layout ()) t ~spatial:idx () in
  check bool "indexed paint emits identical scene" true
    (ops_of a = ops_of b)

let test_spatial_visit_bound () =
  (* A 300-row column under a 100px viewport: the interval index must
     visit only the band, not every mounted row. *)
  let t = store () in
  let ops = ref [ Lui_protocol.InsertChild (1, 2, 0);
                  CreateNode (2, Column); CreateNode (1, Root) ] in
  for i = 0 to 299 do
    ops :=
      InsertChild (2, 10 + i, i)
      :: CreateNode (10 + i, ViewThatFits)
      :: !ops
  done;
  apply t (List.rev !ops);
  let rects = function
    | 1 -> rect 0. 0. 200. 100.
    | 2 -> rect 0. 0. 200. 6000.
    | id -> rect 0. (float_of_int (id - 10) *. 20.) 200. 20.
  in
  let idx = spatial_of t rects in
  let count ?spatial () =
    let n = ref 0 in
    Lui_paint.walk ~scale:1. ~viewport:(rect 0. 0. 200. 100.) t
      ~layout:(layout_map rects)
      ~enter:(fun () _ -> incr n;
             { Lui_paint.b_emit = false; b_down = true; b_ctx = () })
      ~ghost_enter:(fun () _ _ -> ())
      ~leave:(fun _ _ -> ())
      ?spatial:(Option.map
                  (fun i -> (i, Lui_spatial.Region (rect 0. 0. 200. 100.)))
                  spatial)
      ();
    !n
  in
  let full = count () and pruned = count ~spatial:idx () in
  check int "unindexed visits everything" 302 full;
  check bool "indexed visits the band only" true (pruned <= 12)

let test_spatial_degenerate_kept () =
  (* A zero-area child inside a wide parent must still run its
     emission path — the index keeps zero-bound subtrees reachable
     for region queries. *)
  let t = store () in
  let ops =
    ref [ Lui_protocol.InsertChild (1, 2, 0);
          CreateNode (2, Column); CreateNode (1, Root) ]
  in
  for i = 0 to 39 do
    ops :=
      InsertChild (2, 10 + i, i)
      :: CreateNode (10 + i, ViewThatFits)
      :: SetProp (10 + i, BackgroundValue, StringValue "#ff0000")
      :: !ops
  done;
  (* one zero-area box at a scrolled-off position *)
  ops :=
    InsertChild (2, 500, 40)
    :: CreateNode (500, Column)
    :: SetProp (500, BackgroundValue, StringValue "#00ff00")
    :: !ops;
  apply t (List.rev !ops);
  let rects = function
    | 1 -> rect 0. 0. 200. 200.
    | 2 -> rect 0. 0. 200. 2000.
    | 500 -> rect 0. 5000. 0. 0.
    | id -> rect 0. (float_of_int (id - 10) *. 40.) 200. 40.
  in
  let idx = spatial_of t rects in
  let a = paint_with (hooks ~layout:(layout_map rects) ()) t () in
  let b =
    paint_with (hooks ~layout:(layout_map rects) ()) t ~spatial:idx ()
  in
  check bool "degenerate ops preserved" true (ops_of a = ops_of b)


(* A labeled menu-item with an icon prop paints its glyph exactly once,
   in the fixed leading slot (x+8). The labeled side-slot path used to
   paint a second copy beside it. *)
let test_menu_item_single_icon () =
  let t = store () in
  apply t
    [ Lui_protocol.CreateNode (1, MenuItem);
      SetProp (1, InlineIconName, StringValue "settings");
      SetProp (1, TextValue, StringValue "Settings") ];
  let img = Lui_scene.new_image ~w:4 ~h:4 (Bytes.make 64 '\255') in
  let h =
    { (hooks ~layout:(fun _ ->
          Lui_paint.placement_of_rect (rect 0. 0. 200. 32.)) ())
      with Lui_paint.image_of = (fun id -> if id = 1 then Some img else None);
      image_in = (fun id _ -> if id = 1 then Some img else None) }
  in
  let s = paint_with h t () in
  let images =
    List.filter_map (function Image i -> Some i | _ -> None) s.ops
  in
  check int "one icon image" 1 (List.length images);
  match images with
  | [ i ] ->
    check (float 0.01) "leading slot x" 8. i.irect2.x;
    apply t [CreateNode (2, Kbd); SetProp (2, TextValue, StringValue "K"); InsertChild (1, 2, 0)];
    let images = List.filter_map (function Image i -> Some i | _ -> None) (paint_with h t ()).ops in
    check int "shortcut children preserve the menu icon" 1 (List.length images)
  | _ -> ()

let test_menu_selection_indicator () =
  List.iter
    (fun scale ->
      let t = store () in
      apply t
        [
          Lui_protocol.CreateNode (1, MenuItem);
          SetProp (1, TextValue, StringValue "English");
          SetProp (1, Selected, BoolValue true);
        ];
      let r =
        rect (20. *. scale) (10. *. scale) (200. *. scale) (32. *. scale)
      in
      let h = hooks ~layout:(fun _ -> Lui_paint.placement_of_rect r) () in
      let images scene =
        List.filter_map (function Image i -> Some i | _ -> None) scene.ops
      in
      let selected = images (paint_with h t ~width:500 ~height:100 ~scale ()) in
      check int "selected menu row paints one check" 1 (List.length selected);
      let mark = List.hd selected in
      check bool "check contains ink" true
        (Bytes.exists (fun byte -> byte <> '\000') mark.iimage.ipix);
      let repeated =
        List.hd (images (paint_with h t ~width:500 ~height:100 ~scale ()))
      in
      check bool "unchanged rows reuse the check bitmap" true
        (mark.iimage == repeated.iimage);
      check bool "selection check occupies the trailing sixteen-point slot" true
        (mark.irect2
        = rect (196. *. scale) (18. *. scale) (16. *. scale) (16. *. scale));
      let tp = Lui_paint.text_placement_of t 1 in
      check (float 0.01) "selection reserves label space" 32. tp.tp_pad_right;
      apply t [ SetProp (1, Selected, BoolValue false) ];
      check int "unchecked menu row hides its check" 0
        (List.length (images (paint_with h t ~width:500 ~height:100 ~scale ())));
      let tp = Lui_paint.text_placement_of t 1 in
      check (float 0.01) "unchecked options preserve alignment" 32.
        tp.tp_pad_right;
      apply t [ RemoveProp (1, Selected) ];
      check (float 0.01) "ordinary actions need no selection slot" 8.
        (Lui_paint.text_placement_of t 1).tp_pad_right)
    [ 1.; 2. ]

let test_menu_selection_placement () =
  let property =
    List.find_opt
      (fun p -> Lui_wire_schema.property_name p = "selection-placement")
      Lui_wire_schema.all_properties
  in
  check bool "selection placement has a typed wire property" true
    (Option.is_some property);
  let property = Option.get property in
  List.iter
    (fun scale ->
      let t = store () in
      apply t
        [
          Lui_protocol.CreateNode (1, MenuItem);
          SetProp (1, TextValue, StringValue "English");
          SetProp (1, Selected, BoolValue true);
          SetProp (1, property, StringValue "leading");
          SetProp (1, PaddingHorizontal, IntValue 12);
          SetProp (1, Gap, IntValue 4);
        ];
      let r =
        rect (20. *. scale) (10. *. scale) (200. *. scale) (32. *. scale)
      in
      let h = hooks ~layout:(fun _ -> Lui_paint.placement_of_rect r) () in
      let images scene =
        List.filter_map (function Image i -> Some i | _ -> None) scene.ops
      in
      let first =
        List.hd (images (paint_with h t ~width:500 ~height:100 ~scale ()))
      in
      check bool "leading selection honors typed padding" true
        (first.irect2
        = rect (32. *. scale) (18. *. scale) (16. *. scale) (16. *. scale));
      let tp = Lui_paint.text_placement_of t 1 in
      check (float 0.01) "leading check and gap reserve label space" 32.
        tp.tp_pad_left;
      check (float 0.01) "leading check leaves trailing padding intact" 12.
        tp.tp_pad_right;
      apply t [ SetProp (1, Enabled, BoolValue false) ];
      let disabled =
        List.hd (images (paint_with h t ~width:500 ~height:100 ~scale ()))
      in
      check bool "disabled check follows row opacity" true
        (disabled.iopacity > 0. && disabled.iopacity < first.iopacity);
      apply t [ SetProp (1, property, StringValue "trailing") ];
      check (float 0.01) "placement changes update trailing label space" 32.
        (Lui_paint.text_placement_of t 1).tp_pad_right)
    [ 1.; 2. ]

let test_control_single_icon () =
  List.iter
    (fun kind ->
      List.iter
        (fun scale ->
          List.iter
            (fun label ->
              List.iter
                (fun placement ->
                  let t = store () in
                  apply t
                    ([
                       Lui_protocol.CreateNode (1, kind);
                       SetProp (1, InlineIconName, StringValue "keyboard");
                       SetProp (1, IconPlacementValue, StringValue placement);
                     ]
                    @
                    match label with
                    | None -> []
                    | Some value ->
                        [ SetProp (1, TextValue, StringValue value) ]);
                  let image = new_image ~w:4 ~h:4 (Bytes.make 64 '\255') in
                  let label_rect = ref None in
                  let r =
                    rect (20. *. scale) (10. *. scale) (240. *. scale)
                      (40. *. scale)
                  in
                  let h =
                    {
                      (hooks
                         ~layout:(fun _ -> Lui_paint.placement_of_rect r)
                         ())
                      with
                      Lui_paint.image_of = (fun _ -> Some image);
                      image_in = (fun _ _ -> Some image);
                      text_ops =
                        (fun _ region _ _ ->
                          label_rect := Some region;
                          []);
                    }
                  in
                  let painted =
                    paint_with h t ~width:600 ~height:160 ~scale ()
                  in
                  let images =
                    List.filter_map
                      (function Image value -> Some value | _ -> None)
                      painted.ops
                  in
                  check int "a control paints its icon once" 1
                    (List.length images);
                  let slot = (List.hd images).irect2 in
                  match label with
                  | Some value when value <> "" ->
                      let ink = Option.get !label_rect in
                      let pad =
                        (Lui_paint.text_placement_of t 1).tp_pad_left *. scale
                      in
                      check bool "the label leaves the icon slot clear" true
                        (if placement = "trailing" then
                           ink.x +. ink.w -. pad <= slot.x
                         else ink.x +. pad >= slot.x +. slot.w)
                  | _ ->
                      check bool "an icon-only control stays centered" true
                        (abs_float
                           (slot.x +. (slot.w /. 2.) -. (r.x +. (r.w /. 2.)))
                        < 0.01))
                [ "leading"; "trailing" ])
            [ None; Some ""; Some "Search by keys" ])
        [ 1.; 2. ])
    [ Lui_protocol.Button; ToggleButton; Toggle; MenuTrigger ]

let test_text_edge_placement () =
  let t = store () in
  apply t
    [
      Lui_protocol.CreateNode (1, SearchField);
      SetProp (1, PaddingHorizontal, IntValue 10);
      SetProp (1, PaddingVertical, IntValue 6);
      SetProp (1, PaddingLeft, IntValue 28);
      SetProp (1, PaddingRight, IntValue 8);
      SetProp (1, PaddingTop, IntValue 3);
      SetProp (1, PaddingBottom, IntValue 9);
    ];
  let placement = Lui_paint.text_placement_of t 1 in
  check (float 0.001) "text starts at its left edge inset" 28.
    placement.tp_pad_left;
  check (float 0.001) "text starts at its top edge inset" 3.
    placement.tp_pad_top

let () =
  run "lui_paint"
    [ ("color",
       [ test_case "hex" `Quick test_hex;
         test_case "select indicator" `Quick test_select_indicator;
         test_case "image fill crop" `Quick test_image_fill_crop;
         test_case "edges" `Quick test_edges ]);
      ("ops",
       [ test_case "fill" `Quick test_fill_op;
         test_case "order" `Quick test_children_order;
         test_case "invisible" `Quick test_invisible;
         test_case "clip" `Quick test_clip ]);
      ("fills",
       [ test_case "gradient" `Quick test_gradient;
         test_case "gradient variants" `Quick test_gradient_variants;
         test_case "dashed border" `Quick test_dashed_border;
         test_case "per-edge borders" `Quick test_per_edge_borders;
         test_case "per-edge colors" `Quick test_per_edge_border_colors ]);
      ("shadows",
       [ test_case "parse" `Quick test_shadow_parse;
         test_case "op" `Quick test_shadow_op;
         test_case "inset op" `Quick test_inset_shadow_op ]);
      ("state",
       [ test_case "hover bg" `Quick test_state_background;
         test_case "precedence" `Quick test_state_precedence;
         test_case "selected+hover" `Quick test_selected_shadow;
         test_case "disabled opacity" `Quick test_disabled_opacity ]);
      ("compositing",
       [ test_case "opacity multiply" `Quick test_opacity_multiply;
         test_case "viewport cull" `Quick test_viewport_cull;
         test_case "z-index" `Quick test_zindex;
         test_case "display contents" `Quick test_display_contents;
         test_case "mounted range" `Quick test_mounted_range;
         test_case "cull: escaped child" `Quick test_cull_escape_child;
         test_case "cull: fixed descendant" `Quick test_cull_escape_fixed;
         test_case "cull: promoted popup" `Quick test_cull_escape_popup;
         test_case "cull: dead clip" `Quick test_cull_dead_clip;
         test_case "cull: popup escapes dead clip" `Quick
           test_cull_dead_clip_popup ]);
      ("placement",
       [ test_case "absolute" `Quick test_position_absolute;
         test_case "relative" `Quick test_position_relative;
         test_case "popup xy" `Quick test_popup_xy;
         test_case "layout override" `Quick test_layout_override ]);
      ("kinds",
       [ test_case "divider" `Quick test_divider;
         test_case "spacer" `Quick test_spacer;
         test_case "progress" `Quick test_progress;
         test_case "checkbox" `Quick test_checkbox;
         test_case "checkbox unchecked" `Quick test_checkbox_unchecked;
         test_case "switch" `Quick test_switch;
         test_case "radio" `Quick test_radio;
         test_case "spinner" `Quick test_spinner;
         test_case "slider" `Quick test_slider;
         test_case "scrollbar" `Quick test_scrollbar;
         test_case "extension" `Quick test_extension;
         test_case "menu item single icon" `Quick test_menu_item_single_icon;
         test_case "menu selection indicator" `Quick test_menu_selection_indicator;
         test_case "menu selection placement" `Quick test_menu_selection_placement;
         test_case "control single icon" `Quick test_control_single_icon;
         test_case "text edge placement" `Quick test_text_edge_placement ]);
      ("secure",
       [ test_case "masked paint" `Quick test_secure_masked;
         test_case "mask per grapheme" `Quick test_secure_masked_graphemes;
         test_case "placeholder unmasked" `Quick test_secure_placeholder_unmasked;
         test_case "mask units" `Quick test_secure_mask_units;
         test_case "masked offset map" `Quick test_secure_byte_of_masked ]);
      ("spatial",
       [ test_case "negative bounds" `Quick test_spatial_negative_bounds;
         test_case "build allocation" `Quick test_spatial_build_allocation;
         test_case "paint equivalence" `Quick test_spatial_paint_equiv;
         test_case "visit bound" `Quick test_spatial_visit_bound;
         test_case "degenerate kept" `Quick test_spatial_degenerate_kept ]);
      ("coverage",
       [ test_case "all props" `Quick test_coverage_table ]) ]
