(* Cell attributes the SGR sequences set, and the palette they index. *)

type cell_color = Default | Palette of int | Rgb of int * int * int

type underline =
  | No_underline | Single | Double | Curly | Dotted | Dashed

type t = {
  fg : cell_color;
  bg : cell_color;
  ulc : cell_color;    (* underline color; Default follows fg *)
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

let default = {
  fg = Default; bg = Default; ulc = Default;
  bold = false; faint = false; italic = false; underline = No_underline;
  blink = false; inverse = false; invisible = false; strike = false;
  overline = false;
}

let equal (a : t) (b : t) = a = b

(* The xterm 256-color palette: the 16 base colors, the 6x6x6 cube and
   the grayscale ramp. *)
let palette256 : Lui_scene.color array =
  let c = Lui_scene.color in
  let a = Array.make 256 (c 0 0 0 255) in
  let base = [|
    (0, 0, 0); (205, 49, 49); (13, 188, 121); (229, 229, 16);
    (36, 114, 200); (188, 63, 188); (17, 168, 205); (229, 229, 229);
    (102, 102, 102); (241, 76, 76); (35, 209, 139); (245, 245, 67);
    (59, 142, 234); (214, 112, 214); (41, 184, 219); (255, 255, 255) |]
  in
  Array.iteri (fun i (r, g, b) -> a.(i) <- c r g b 255) base;
  let cube i =
    if i = 0 then 0 else 55 + i * 40
  in
  for i = 16 to 231 do
    let n = i - 16 in
    a.(i) <- c (cube (n / 36)) (cube ((n / 6) mod 6)) (cube (n mod 6)) 255
  done;
  for i = 232 to 255 do
    let g = 8 + (i - 232) * 10 in
    a.(i) <- c g g g 255
  done;
  a

let rgba i =
  Lui_scene.color ((i lsr 24) land 0xFF) ((i lsr 16) land 0xFF)
    ((i lsr 8) land 0xFF) (i land 0xFF)

let rgb24 i =
  Lui_scene.color ((i lsr 16) land 0xFF) ((i lsr 8) land 0xFF) (i land 0xFF)
    255

let with_alpha (c : Lui_scene.color) a = { c with Lui_scene.a = a }

(* The terminal's effective colors: the palette plus the defaults and
   the accent colors programs may override (OSC 4/10/11/12). *)
type theme = {
  fg : Lui_scene.color;
  bg : Lui_scene.color;
  cursor : Lui_scene.color;
  cursor_text : Lui_scene.color;
  selection : Lui_scene.color;
  selection_text : Lui_scene.color option;
  palette : Lui_scene.color array;
}

let dark_theme () = {
  fg = Lui_scene.color 229 229 229 255; bg = Lui_scene.color 24 24 24 255;
  cursor = Lui_scene.color 229 229 229 255;
  cursor_text = Lui_scene.color 24 24 24 255;
  selection = Lui_scene.color 68 114 196 110; selection_text = None;
  palette = palette256;
}

let light_theme () = {
  fg = Lui_scene.color 36 36 36 255; bg = Lui_scene.color 255 255 255 255;
  cursor = Lui_scene.color 36 36 36 255;
  cursor_text = Lui_scene.color 255 255 255 255;
  selection = Lui_scene.color 51 131 232 90; selection_text = None;
  palette = palette256;
}

(* Resolve a cell color slot against the theme and a fallback. *)
let color_of th cc def =
  match cc with
  | Default -> def
  | Palette i ->
    if i >= 0 && i < Array.length th.palette then th.palette.(i) else def
  | Rgb (r, g, b) -> Lui_scene.color r g b 255

(* The colors a cell with attributes [a] paints with, before selection:
   inverse swaps the resolved pair, faint halves the ink's alpha, blink
   is a paint-time flag the caller combines with its blink phase. *)
let resolve th (a : t) =
  let fg = color_of th a.fg th.fg and bg = color_of th a.bg th.bg in
  let fg, bg = if a.inverse then (bg, fg) else (fg, bg) in
  let fg = if a.faint then with_alpha fg (fg.Lui_scene.a / 2) else fg in
  let ulc =
    match a.ulc with
    | Default -> fg
    | c -> color_of th c th.fg
  in
  (fg, bg, ulc)

(* SGR: apply one parameter run (semicolon item) at index [i] of [ps],
   which pairs each value with its colon sub-parameters. [ps] items are
   (value, subs) with value -1 for an empty slot. Returns the next index
   to read — extended colors consume their following arguments. *)
let sgr_apply a ps i =
  let v, subs = ps.(i) in
  let sub j = if j < Array.length subs then subs.(j) else -1 in
  let extended k =
    (* 38;5;n  38;2;r;g;b  and the colon forms 38:5:n / 38:2:[cs:]r:g:b *)
    match Array.length subs with
    | 0 -> (
      match (if i + k < Array.length ps then fst ps.(i + k) else -1) with
      | 5 ->
        (if i + k + 1 < Array.length ps
         then Palette (max 0 (fst ps.(i + k + 1)))
         else Default), i + k + 1
      | 2 ->
        let p j = if i + k + j < Array.length ps then fst ps.(i + k + j) else 0 in
        Rgb (p 1 land 0xFF, p 2 land 0xFF, p 3 land 0xFF), i + k + 3
      | _ -> Default, i + k)
    | _ -> (
      match sub 0 with
      | 5 -> Palette (max 0 (sub 1)), i
      | 2 ->
        (* 38:2:<colorspace>:r:g:b and the short 38:2:r:g:b both occur *)
        let off = if Array.length subs >= 5 then 1 else 0 in
        Rgb (sub (1 + off) land 0xFF, sub (2 + off) land 0xFF,
             sub (3 + off) land 0xFF), i
      | _ -> Default, i)
  in
  let color k =
    let c, used = extended k in
    ((fun x -> match c with Default -> x | _ -> c), used)
  in
  match v with
  | -1 | 0 -> (default, i)
  | 1 -> ({ a with bold = true }, i)
  | 2 -> ({ a with faint = true }, i)
  | 3 -> ({ a with italic = true }, i)
  | 4 -> (
    let u =
      match sub 0 with
      | 0 -> No_underline | 2 -> Double | 3 -> Curly
      | 4 -> Dotted | 5 -> Dashed | _ -> Single
    in
    ({ a with underline = u }, i))
  | 5 | 6 -> ({ a with blink = true }, i)
  | 7 -> ({ a with inverse = true }, i)
  | 8 -> ({ a with invisible = true }, i)
  | 9 -> ({ a with strike = true }, i)
  | 21 -> ({ a with underline = Double; bold = false }, i)
  | 22 -> ({ a with bold = false; faint = false }, i)
  | 23 -> ({ a with italic = false }, i)
  | 24 -> ({ a with underline = No_underline }, i)
  | 25 -> ({ a with blink = false }, i)
  | 27 -> ({ a with inverse = false }, i)
  | 28 -> ({ a with invisible = false }, i)
  | 29 -> ({ a with strike = false }, i)
  | _ when v >= 30 && v <= 37 -> ({ a with fg = Palette (v - 30) }, i)
  | 38 -> let keep, j = color 1 in ({ a with fg = keep a.fg }, j)
  | 39 -> ({ a with fg = Default }, i)
  | _ when v >= 40 && v <= 47 -> ({ a with bg = Palette (v - 40) }, i)
  | 48 -> let keep, j = color 1 in ({ a with bg = keep a.bg }, j)
  | 49 -> ({ a with bg = Default }, i)
  | 53 -> ({ a with overline = true }, i)
  | 55 -> ({ a with overline = false }, i)
  | 58 -> let keep, j = color 1 in ({ a with ulc = keep a.ulc }, j)
  | 59 -> ({ a with ulc = Default }, i)
  | _ when v >= 90 && v <= 97 -> ({ a with fg = Palette (v - 90 + 8) }, i)
  | _ when v >= 100 && v <= 107 -> ({ a with bg = Palette (v - 100 + 8) }, i)
  | _ -> (a, i)

let sgr a ps =
  if Array.length ps = 0 then default
  else
    let rec loop i a =
      if i >= Array.length ps then a
      else
        let a', j = sgr_apply a ps i in
        loop (j + 1) a'
    in
    loop 0 a
