type color =
  [ `background | `surface | `surface_raised | `card
  | `foreground | `muted_foreground | `primary | `secondary | `accent | `muted
  | `destructive | `warning | `success | `info | `border | `input | `ring
  | `glass | `bar | `transparent | `hex of int | `token of string ]
type space = [ `none | `xs | `sm | `md | `lg | `xl | `page | `px of int ]
type radius = [ `none | `sm | `md | `lg | `xl | `full | `px of int ]
type text_role = [ `display | `title | `headline | `subheadline | `body | `caption | `footnote | `code ]

let color_value : color -> string = function
  | `background -> "background" | `surface -> "surface" | `surface_raised -> "surface-raised"
  | `card -> "card" | `foreground -> "foreground" | `muted_foreground -> "muted-foreground"
  | `primary -> "primary" | `secondary -> "secondary" | `accent -> "accent" | `muted -> "muted"
  | `destructive -> "destructive" | `warning -> "warning" | `success -> "success" | `info -> "info"
  | `border -> "border" | `input -> "input" | `ring -> "ring" | `glass -> "glass" | `bar -> "bar"
  | `transparent -> "transparent"
  | `hex value ->
    let value = max 0 (min 0xffffffff value) in
    Printf.sprintf (if value <= 0xffffff then "#%06x" else "#%08x") value
  | `token value -> if String.trim value = "" then "transparent" else value

let space_value_for (os : Lui_protocol.operating_system) : space -> int =
  let touch = match os with IOS | AndroidOS -> true | _ -> false in
  function
  | `none -> 0
  | `xs -> 4
  | `sm -> if touch then 10 else 8
  | `md -> if touch then 16 else 12
  | `lg | `page -> if touch then 20 else 16
  | `xl -> if touch then 28 else 24
  | `px value -> max 0 value

let space_value : space -> int = space_value_for GenericOS

let radius_value : radius -> int = function
  | `none -> 0 | `sm -> 4 | `md -> 6 | `lg -> 8 | `xl -> 12 | `full -> 9999
  | `px value -> max 0 value

let text_role_value : text_role -> string = function
  | `display -> "display" | `title -> "title" | `headline -> "headline" | `subheadline -> "subheadline"
  | `body -> "body" | `caption -> "caption" | `footnote -> "footnote" | `code -> "code"
