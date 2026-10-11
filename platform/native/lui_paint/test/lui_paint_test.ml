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
    shadow_of = Lui_paint.parse_shadow (fun _ -> None) }

let scene () =
  Lui_scene.create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:64)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:64 ~h:64)

let paint_with h t ?(width = 200) ?(height = 200) ?(scale = 1.) () =
  let s = scene () in
  Lui_paint.paint h t s ~width ~height ~scale ~clear:(color 0 0 0 0);
  s

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
  (match Lui_paint.parse_shadow resolve "0 2px 4px #00000080" with
   | Some (sp : Lui_paint.shadow_spec) ->
     check bool "dx" true (sp.dx = 0.);
     check bool "dy" true (sp.dy = 2.);
     check bool "blur" true (sp.blur = 4.);
     check bool "alpha" true (sp.scolor.a = 128);
     check bool "outset" true (not sp.inset)
   | None -> fail "shadow parse failed");
  (match Lui_paint.parse_shadow resolve "inset 0 0 0 2px ring" with
   | Some (sp : Lui_paint.shadow_spec) ->
     check bool "inset" true sp.inset;
     check bool "spread" true (sp.spread = 2.);
     check int "ring blue" 255 sp.scolor.b
   | None -> fail "inset parse failed");
  check bool "none" true
    (Lui_paint.parse_shadow resolve "none" = None)

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
  (* the button also gains a default control border; both fills carry
     the disabled opacity *)
  match s.ops with
  | [ Fill bg; Fill border ] ->
    check bool "half opacity" true (bg.fopacity = 0.5 && border.fopacity = 0.5)
  | _ -> fail "expected bg + border fills"

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

let layout_map f = fun id -> Lui_paint.placement_of_rect (f id)

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
  (* the styled background fill lands first; popover defaults add
     shadow + border after it *)
  match s.ops with
  | Fill f :: _ ->
    check bool "popup" true (f.frect.x = 30. && f.frect.y = 40.)
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
  (* ring minus one quarter: three border-edge fills *)
  check int "three edges" 3 (List.length s.ops);
  match s.ops with
  | Fill f :: _ -> check bool "edge width" true (f.fborder = (2., 0., 0., 0.))
  | _ -> fail "expected edge fills"

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

let () =
  run "lui_paint"
    [ ("color",
       [ test_case "hex" `Quick test_hex;
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
         test_case "z-index" `Quick test_zindex;
         test_case "display contents" `Quick test_display_contents ]);
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
         test_case "extension" `Quick test_extension ]);
      ("coverage",
       [ test_case "all props" `Quick test_coverage_table ]) ]
