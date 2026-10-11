(* The glass corpus behind the glass parity suites: panes of each
   style and tint over a varied backdrop, blurs constant and masked,
   and the scroll edge's soft and hard looks — the same Lui_scene.t
   values on the CPU and GPU sides, with what each comparison may
   show. *)

open Lui_scene
module Tk = Lui_raster_testkit.Testkit
module G = Lui_plugin_glass
open Lui_parity.Parity

(* What a pane blurs, lenses and lights: colored blocks overlapping
   enough that tone, refraction and the rim all draw differently. *)
let content =
  [ Tk.ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
    Tk.ifill (rect 10. 8. 40. 28.) (color 250 204 21 255);
    Tk.ifill ~radii:(Tk.radii 6.) (rect 30. 16. 36. 30.)
      (color 219 39 119 255);
    Tk.ifill (rect 46. 30. 40. 26.) (color 16 185 129 255) ]

let pane rc m =
  let s = Tk.scene ~w:96 ~h:64 content in
  G.glass ~scene:s ~radii:(Tk.radii 10.) rc m;
  s

let with_blur f =
  let s = Tk.scene ~w:96 ~h:64 content in
  f s;
  s

let corpus : (string * (unit -> Lui_scene.t) * expect) list =
  [ ( "glass_regular",
      (fun () -> pane (rect 18. 12. 60. 40.) (G.material ())),
      Within (2, j_backdrop) );
    ( "glass_regular_dark",
      (fun () -> pane (rect 18. 12. 60. 40.) (G.material ~dark:true ())),
      Within (2, j_backdrop) );
    ( "glass_clear",
      (fun () -> pane (rect 18. 12. 60. 40.) (G.material ~style:G.Clear ())),
      Loose
        ( 2,
          4,
          8,
          "the Clear ramp's curve amplifies a backdrop LSB and the \
           lens may refract a boundary pixel across a sharp content \
           edge — " ^ j_backdrop ) );
    ( "glass_tint",
      (fun () ->
        pane (rect 18. 12. 60. 40.)
          (G.material ~tint:(color 200 60 60 90) ())),
      Within (2, j_backdrop) );
    ( "glass_grow",
      (fun () ->
        pane (rect 18. 12. 60. 40.)
          (G.material ~interactive:true ())),
      Within (2, j_backdrop) );
    ( "glass_grow_pressed",
      (fun () ->
        let s = Tk.scene ~w:96 ~h:64 content in
        G.glass ~scene:s ~radii:(Tk.radii 10.) ~grow:1.
          (rect 18. 12. 60. 40.)
          (G.material ~interactive:true ());
        s),
      Within (2, j_backdrop) );
    ( "blur",
      (fun () -> with_blur (fun s -> G.blur ~scene:s ~radius:6.
                     (rect 12. 10. 72. 44.))),
      Within (2, j_backdrop) );
    ( "blur_masked",
      (fun () ->
        with_blur (fun s ->
            G.blur ~scene:s ~radius:8.
              ~mask:(G.fade ~from:1. ~to_:0. ~angle:180. ())
              (rect 12. 10. 72. 44.))),
      Within (2, j_backdrop) );
    ( "scroll_edge_soft",
      (fun () ->
        with_blur (fun s ->
            G.scroll_edge ~scene:s ~bg:(color 250 250 250 255)
              (rect 0. 0. 96. 22.))),
      Within (1, j_grad) );
    ( "scroll_edge_hard",
      (fun () ->
        with_blur (fun s ->
            G.scroll_edge ~scene:s ~hard:true
              ~bg:(color 242 242 247 255)
              (rect 0. 0. 96. 22.))),
      Within (2, j_backdrop) ) ]
