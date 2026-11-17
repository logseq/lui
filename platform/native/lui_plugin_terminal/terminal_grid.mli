(* The screen model: visible grid, scrollback ring, cursor and modes,
   damage tracking, reflow on resize, and the selection. *)

module A = Terminal_attrs

type cell = private {
  mutable text : string;      (* grapheme cluster, "" when blank/spacer *)
  mutable attrs : A.t;
  mutable wide : bool;        (* cluster occupies this cell and the next *)
  mutable spacer : bool;      (* second half of a wide cluster *)
  mutable link : int;
}

type row = private { cells : cell array; mutable wrapped : bool; mutable id : int }

type t

val create : cols:int -> rows:int -> max_scrollback:int -> t

val cols : t -> int
val rows : t -> int
val sb_len : t -> int
val cursor : t -> int * int
val pen : t -> A.t
val is_alt : t -> bool
val view : t -> int
val tabs : t -> bool array
val cursor_style : t -> int * bool    (* DECSCUSR shape, blink flag *)

(* Document rows index into scrollback ++ screen; [doc_row t i] for
   0 <= i < sb_len + rows. *)
val doc_row : t -> int -> row
val screen_row : t -> int -> row
val cell_at : t -> int -> int -> cell option
val screen_cell : t -> int -> int -> cell option
val row_text : t -> int -> string
val row_id_at : t -> int -> int option
val shown_row : t -> int -> (int * row) option
(** [shown_row t y] maps a viewport row to (document index, row), taking
    the scrollback viewport offset into account. *)

(* Cursor control *)
val set_cursor : t -> int -> int -> unit
val move_cursor : t -> int -> int -> unit
val cursor_col : t -> int -> unit
val cursor_row : t -> int -> unit

(* Scrolling *)
val scroll_up : t -> ?top:int -> ?bot:int -> int -> unit
val scroll_down : t -> ?top:int -> ?bot:int -> int -> unit
val index : t -> unit
val rev_index : t -> unit
val newline : t -> unit
val insert_lines : t -> int -> unit
val delete_lines : t -> int -> unit
val set_scroll_region : t -> int -> int -> unit
val scroll_region : t -> int * int

(* Erase *)
val erase_in_line : t -> int -> unit
val erase_in_display : t -> int -> unit
val erase_chars : t -> int -> unit

(* Insert / delete characters *)
val insert_chars : t -> int -> unit
val delete_chars : t -> int -> unit

(* Printing *)
val set_pen : t -> A.t -> unit
val set_link : t -> int -> unit
val put : t -> string -> int -> unit
val extend : t -> string -> unit

(* Tabs *)
val tab_forward : t -> int -> unit
val tab_backward : t -> int -> unit
val tab_set : t -> unit
val tab_clear : t -> int -> unit

(* Save / restore; [extra] carries parser state through the pair. *)
val save_cursor : t -> int -> unit
val restore_cursor : t -> int

(* Alt screen *)
val enter_alt : t -> bool -> unit
val exit_alt : t -> bool -> unit

(* Modes *)
val set_mode : t -> int -> bool -> unit      (* DECSET/DECRST numbers *)
val set_ansi_mode : t -> int -> bool -> unit (* SM/RM numbers *)
val set_decawm : t -> bool -> unit
val set_appcursor : t -> bool -> unit
val set_cursor_style : t -> int -> unit

val mode_appcursor : t -> bool
val mode_decawm : t -> bool
val mode_cursor_visible : t -> bool
val mode_focus : t -> bool
val mode_altscroll : t -> bool
val mode_sync : t -> bool
val mode_graphemes : t -> bool
val mode_bracketed : t -> bool
val mode_mouse : t -> int
val mode_mouse_fmt : t -> int
val mode_lnm : t -> bool

val decaln : t -> unit
(** DECALN: fill every cell with 'E'. *)

(* Resize and viewport *)
val resize : t -> cols:int -> rows:int -> unit
val scroll_view : t -> int -> unit
val set_view : t -> int -> unit

(* Selection. Positions are (row id, column); ids are stable across
   scrolling and come from [row.id] / [row_id_at]. *)
type sel_kind = Sel_char | Sel_word | Sel_line

val sel_start : t -> id:int -> col:int -> sel_kind -> unit
val sel_extend : t -> id:int -> col:int -> unit
val sel_clear : t -> unit
val sel_covers : t -> row:int -> col:int -> bool
val sel_text : t -> string
val has_selection : t -> bool

(* Damage *)
val dirty_row : t -> int -> bool
val damaged : t -> bool
val sb_dirty : t -> bool
val clear_damage : t -> unit

val is_word_byte : char -> bool
