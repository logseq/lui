(* Cell attributes set by SGR sequences, and the color theme that
   resolves them at paint time. *)

type cell_color = Default | Palette of int | Rgb of int * int * int

type underline =
  | No_underline | Single | Double | Curly | Dotted | Dashed

type t = {
  fg : cell_color;
  bg : cell_color;
  ulc : cell_color;
  bold : bool;
  faint : bool;
  italic : bool;
  underline : underline;
  blink : bool;
  inverse : bool;
  invisible : bool;
  strike : bool;
  overline : bool;
}

val default : t
val equal : t -> t -> bool

val palette256 : Lui_scene.color array
(** The xterm 256-color palette. *)

val rgba : int -> Lui_scene.color
(** [rgba i] unpacks 0xRRGGBBAA. *)

val rgb24 : int -> Lui_scene.color
(** [rgb24 i] unpacks 0xRRGGBB with alpha 255. *)

type theme = {
  fg : Lui_scene.color;
  bg : Lui_scene.color;
  cursor : Lui_scene.color;
  cursor_text : Lui_scene.color;
  selection : Lui_scene.color;
  selection_text : Lui_scene.color option;
  palette : Lui_scene.color array;
}

val dark_theme : unit -> theme
val light_theme : unit -> theme

val color_of : theme -> cell_color -> Lui_scene.color -> Lui_scene.color
(** [color_of th cc def] resolves [cc] against [th], defaulting to [def]. *)

val resolve : theme -> t ->
  Lui_scene.color * Lui_scene.color * Lui_scene.color
(** [resolve th a] is (ink, paper, underline ink) with inverse and faint
    applied. *)

val sgr : t -> (int * int array) array -> t
(** [sgr a ps] applies an SGR parameter run. Each item pairs the main
    value (-1 when empty) with its colon sub-parameters; extended color
    forms may consume following items. *)
