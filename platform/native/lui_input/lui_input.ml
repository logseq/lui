(* Backend-neutral input events for the native window hosts and the
   interaction runtime. Platform drivers translate their OS events
   (SDL, X11, Win32) into these; the interaction machines in this
   library consume them and emit actions for the driver to perform.
   Pure tables and types only — no SDL, no store, no scene. *)

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
  | Other of int

type mouse_button =
  | Left
  | Middle
  | Right
  | Other of int

let button_to_int = function
  | Left -> 0
  | Middle -> 1
  | Right -> 2
  | Other n -> n

type mods = {
  ctrl : bool;
  shift : bool;
  alt : bool;
  meta : bool;
}

let mods_none = { ctrl = false; shift = false; alt = false; meta = false }

(* Same bitmask the web backend emits: 1 ctrl, 2 shift, 4 meta. The
   secondary-button bit 8 is set by the detail builder on right
   clicks, matching press_detail's modifiers field. *)
let mods_to_int m =
  (if m.ctrl then 1 else 0)
  lor (if m.shift then 2 else 0)
  lor (if m.meta then 4 else 0)

type t =
  | Move of float * float
  | Button_down of float * float * mouse_button * int * mods
  | Button_up of float * float * mouse_button * mods
  | Text_input of string
  | Text_editing of string * int * int
  | Caret of Lui_scene.rect
  | Key_down of key * mods * bool
  | Paste of string
  | Resize of int * int
  | Wheel of float * float
  | Wheel_mods of float * float * mods
  | Drop_file of string
  | Drop_text of string
  | Quit_input

(* SDL_Scancode integer constants, kept in this module (not the
   driver) so the table is unit-testable without SDL linked. *)
let key_of_sdl_scancode = function
  | 40 | 88 -> Return (* return, keypad-enter *)
  | 41 -> Escape
  | 42 -> Backspace
  | 76 -> Delete
  | 43 -> Tab
  | 44 -> Space
  | 74 -> Home
  | 75 -> Page_up
  | 77 -> End
  | 78 -> Page_down
  | 80 -> Arrow_left
  | 79 -> Arrow_right
  | 81 -> Arrow_down
  | 82 -> Arrow_up
  | n -> Other n

(* Inverse of the letter/digit half of the table above — used by
   host-side typeahead and the accelerator table, which match on
   characters rather than named keys. *)
let char_of_scancode ?(shift = false) = function
  | n when n >= 4 && n <= 29 ->
    let c = Char.chr (Char.code 'a' + n - 4) in
    Some (if shift then Char.uppercase_ascii c else c)
  | n when n >= 30 && n <= 38 ->
    Some (Char.chr (Char.code '1' + n - 30))
  | 39 -> Some '0'
  | _ -> None

(* SDL_BUTTON_* integer constants: 1 left, 2 middle, 3 right. *)
let button_of_sdl = function
  | 1 -> Left
  | 2 -> Middle
  | 3 -> Right
  | n -> Other n
