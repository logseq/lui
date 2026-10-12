(* Backend-neutral input events. Platform drivers (SDL, X11, Win32)
   translate their OS events into these; the interaction machines in
   this library consume them. Coordinates are in logical (window)
   pixels unless a constructor says otherwise. *)

type key =
  | Return
  | Escape
  | Backspace
  | Delete
  | Tab
  | Space
  | Arrow_left
  | Arrow_right
  | Arrow_up
  | Arrow_down
  | Home
  | End
  | Page_up
  | Page_down
  | Other of int  (** SDL keycode for keys without special handling. *)

type mouse_button =
  | Left
  | Middle
  | Right
  | Other of int

type mods = {
  ctrl : bool;
  shift : bool;
  alt : bool;
  meta : bool;
}

val mods_none : mods

(** DOM button numbering: 0 primary, 1 middle, 2 secondary. *)
val button_to_int : mouse_button -> int

(** Web-compatible bitmask: 1 ctrl, 2 shift, 4 meta. The secondary
    button bit (8) is added by the event builder when applicable. *)
val mods_to_int : mods -> int

type t =
  | Move of float * float
  | Button_down of float * float * mouse_button * int * mods
      (** x y button click-count mods *)
  | Button_up of float * float * mouse_button * mods
  | Text_input of string  (** committed text from SDL_TEXTINPUT *)
  | Text_editing of string * int * int
      (** SDL_TEXTEDITING: composition text, selection start,
          selection length — feeds {!Lui_ime}, never dispatched *)
  | Caret of Lui_scene.rect
      (** driver-fed caret rect (device px) for candidate-window
          tracking; emitted once per frame while focused *)
  | Key_down of key * mods * bool  (** key, mods, repeat *)
  | Paste of string
      (** clipboard text the driver feeds after a [Paste_request]
          action — clipboard I/O stays outside the pure modules *)
  | Resize of int * int  (** new window size, logical pixels *)
  | Wheel of float * float
      (** dx dy — SDL convention: +y scrolls content up *)
  | Wheel_mods of float * float * mods
      (** wheel deltas with the modifier state at dispatch — Shift
          turns the vertical delta horizontal *)
  | Drop_file of string
      (** OS file drop (SDL_DROPFILE). Lands at the last pointer
          position — SDL drop events carry no coordinates. The
          payload offered to matching drop targets is
          ["file:" ^ path], so [data-drop-accept="file:"] selects
          it. *)
  | Drop_text of string
      (** OS text drop (SDL_DROPTEXT); payload ["text:" ^ s]. *)
  | Quit_input

(** SDL_Scancode integer values → keys (40 return, 41 escape, 42
    backspace, 76 delete, 43 tab, 44 space, 74 home, 75 page-up,
    77 end, 78 page-down, 79-82 arrows). Pure table so the driver
    stays thin and tests need no SDL. *)
val key_of_sdl_scancode : int -> key

(** SDL scancode → printable char for host-side typeahead and the
    accelerator table; [~shift] uppercases letters. *)
val char_of_scancode : ?shift:bool -> int -> char option

(** SDL_BUTTON_* integer values: 1 left, 2 middle, 3 right. *)
val button_of_sdl : int -> mouse_button
