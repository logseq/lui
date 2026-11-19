(** Canonical design tokens. Conversion preserves the Phase 2 wire vocabulary;
    hosts resolve semantic colors and typography in their own theme. *)
type color =
  [ `background | `surface | `surface_raised | `card
  | `foreground | `muted_foreground | `primary | `secondary | `accent | `muted
  | `destructive | `warning | `success | `info | `border | `input | `ring
  | `glass | `bar | `transparent | `hex of int | `token of string ]
type space = [ `none | `xs | `sm | `md | `lg | `xl | `page | `px of int ]
type radius = [ `none | `sm | `md | `lg | `xl | `full | `px of int ]
type text_role = [ `display | `title | `headline | `subheadline | `body | `caption | `footnote | `code ]

val color_value : color -> string
val space_value : space -> int
val radius_value : radius -> int
val text_role_value : text_role -> string
