(* Character width for terminal cells: 0 for combining/format
   codepoints, 2 for wide (CJK, emoji), 1 otherwise. *)

val width : int -> int
(** [width cp] is the number of cells codepoint [cp] occupies. *)

val is_zero : int -> bool
(** [is_zero cp] holds when [cp] is a combining mark, joiner, format or
   tag character that occupies no cell of its own. *)

val is_wide : int -> bool
(** [is_wide cp] holds when [cp] occupies two cells. *)

val is_zwj : int -> bool
(** [is_zwj cp] holds for U+200D (zero-width joiner). *)

val is_vs : int -> bool
(** [is_vs cp] holds for variation selectors (U+FE00..U+FE0F and the
    supplementary plane range). *)

val is_ri : int -> bool
(** [is_ri cp] holds for regional indicator symbols (flag pairs). *)
