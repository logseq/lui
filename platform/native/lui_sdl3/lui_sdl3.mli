(** SDL3 operations used by experimental native hosts. Resources have distinct
    types. Text input is window-scoped. Event snapshots own their text/drop
    strings, preserve floating-point coordinates and use nanosecond timestamps.
    Texture upload pitches are bytes for every Bigarray element kind. *)

type window = Sdl3.T.window
type renderer = Sdl3.T.renderer
type texture = Sdl3.T.texture
type gl_context = Sdl3.T.gl_context
type cursor = Sdl3.T.cursor
module Init :
  sig val video : int val events : int val ( + ) : int -> int -> int end
module Window :
  sig
    val none : int64
    val hidden : int64
    val resizable : int64
    val high_pixel_density : int64
    val opengl : int64
    val metal : int64
    val borderless : int64
    val ( + ) : int64 -> int64 -> int64
  end
module Gl :
  sig
    type attr = Sdl3.T.gl_attr
    val context_major_version : Sdl3.T.gl_attr
    val context_minor_version : Sdl3.T.gl_attr
    val context_profile_mask : Sdl3.T.gl_attr
    val doublebuffer : Sdl3.T.gl_attr
    val depth_size : Sdl3.T.gl_attr
    val stencil_size : Sdl3.T.gl_attr
    val context_flags : Sdl3.T.gl_attr
    val context_profile_core : int
    val context_forward_compatible_flag : int
  end
module Kmod :
  sig
    val ctrl : int
    val shift : int
    val alt : int
    val gui : int
    val lctrl : int
    val rctrl : int
    val lshift : int
    val rshift : int
    val lalt : int
    val ralt : int
    val lgui : int
    val rgui : int
  end
module Scancode :
  sig
    val lshift : int
    val a : int
    val c : int
    val v : int
    val x : int
    val z : int
  end
module System_cursor :
  sig
    type t = Sdl3.T.system_cursor
    val arrow : Sdl3.T.system_cursor
    val ibeam : Sdl3.T.system_cursor
    val hand : Sdl3.T.system_cursor
    val no : Sdl3.T.system_cursor
    val wait : Sdl3.T.system_cursor
    val waitarrow : Sdl3.T.system_cursor
    val sizewe : Sdl3.T.system_cursor
    val sizens : Sdl3.T.system_cursor
    val sizeall : Sdl3.T.system_cursor
    val sizenwse : Sdl3.T.system_cursor
    val sizenesw : Sdl3.T.system_cursor
    val crosshair : Sdl3.T.system_cursor
  end
module Rect :
  sig
    type t = Sdl3.T.rect
    val create : x:int -> y:int -> w:int -> h:int -> Sdl3.T.Rect.t
  end
module Pixel : sig val format_argb8888 : int end
module Texture : sig val access_streaming : int end
val init : int -> unit Sdl3.T.result
val quit : unit -> unit
val get_error : unit -> string
val delay : int -> unit
val get_performance_counter : unit -> int64
val get_performance_frequency : unit -> int64
val get_ticks : unit -> int64
val get_ticks_ns : unit -> int64
val get_mod_state : unit -> int
val set_mod_state : int -> unit
val get_scancode_name : Sdl3.T.scancode_enum -> string
val create_window :
  string ->
  w:int ->
  h:int -> int64 -> Sdl3.T.window Sdl3.T.result
val create_popup_window :
  window -> tooltip:bool -> x:int -> y:int -> w:int -> h:int ->
  window Sdl3.T.result
val destroy_window : Sdl3.T.window -> unit
val show_window : Sdl3.T.window -> unit
val raise_window : Sdl3.T.window -> unit
val get_window_id : Sdl3.T.window -> int
val get_window_size : Sdl3.T.window -> int * int
val get_window_size_in_pixels : Sdl3.T.window -> int * int
val unsafe_ptr_of_window : window -> nativeint
val set_window_minimum_size :
  Sdl3.T.window -> w:int -> h:int -> unit
val get_window_display_id :
  Sdl3.T.window -> (int, [> `Msg of string ]) result
val display_refresh_rate : int -> (float, [ `Msg of string ]) result
val gl_set_attribute : Sdl3.T.gl_attr -> int -> unit Sdl3.T.result
val gl_get_attribute : Sdl3.T.gl_attr -> int Sdl3.T.result
val gl_create_context :
  Sdl3.T.window ->
  Sdl3.T.gl_context_state Sdl3.T.result
val gl_make_current :
  Sdl3.T.window ->
  Sdl3.T.gl_context -> unit Sdl3.T.result
val gl_delete_context : Sdl3.T.gl_context -> unit
val gl_set_swap_interval : int -> unit Sdl3.T.result
val gl_swap_window : Sdl3.T.window -> unit
type capitalization = None_ | Sentences | Words | Letters
val start_text_input :
  ?multiline:bool -> ?secure:bool -> ?autocorrect:bool ->
  ?capitalization:capitalization -> Sdl3.T.window -> unit
val stop_text_input : Sdl3.T.window -> unit
val is_text_input_active : Sdl3.T.window -> bool
val set_text_input_area :
  Sdl3.T.window -> Sdl3.T.rect option -> cursor:int -> unit
val run_on_main_thread : (unit -> unit) -> unit

type native_handle =
  | Cocoa_window of nativeint
  | X11_window of int
  | Wayland_surface of nativeint

val native_handle : Sdl3.T.window -> native_handle option
val create_system_cursor :
  Sdl3.T.system_cursor -> Sdl3.T.cursor Sdl3.T.result
val set_cursor : Sdl3.T.cursor -> unit
val destroy_cursor : Sdl3.T.cursor -> unit
val create_renderer :
  ?software:bool ->
  ?vsync:bool ->
  Sdl3.T.window ->
  (Sdl3.T.renderer, [ `Msg of string ]) result
val destroy_renderer : Sdl3.T.renderer -> unit
val renderer_name : Sdl3.T.renderer -> string
val get_renderer_output_size :
  Sdl3.T.renderer -> (int * int) Sdl3.T.result
val create_texture :
  Sdl3.T.renderer ->
  Sdl3.T.pixel_format_enum ->
  Sdl3.T.texture_access_enum ->
  w:int -> h:int -> Sdl3.T.texture Sdl3.T.result
val destroy_texture : Sdl3.T.texture -> unit
val update_texture :
  Sdl3.T.texture ->
  Sdl3.T.rect option ->
  ('a, 'b, 'c) Bigarray.Array1.t -> int -> unit Sdl3.T.result
val render_copy :
  Sdl3.T.renderer ->
  Sdl3.T.texture -> unit Sdl3.T.result
val render_debug_text :
  Sdl3.T.renderer ->
  x:float -> y:float -> string -> unit Sdl3.T.result
val render_present : Sdl3.T.renderer -> unit
module Event :
  sig
    type window_change =
        Resized
      | Pixel_size_changed
      | Display_scale_changed
      | Display_changed
      | Close_requested
      | Moved
      | Hidden
      | Minimized
      | Shown
      | Restored
      | Exposed
      | Focus_gained
      | Focus_lost
      | Other_window of int
    type key = { scancode : int; keymod : int; repeat : bool; }
    type motion = { x : float; y : float; xrel : float; yrel : float; }
    type button = { x : float; y : float; button : int; clicks : int; }
    type kind =
        Quit
      | Window of window_change * int * int
      | Display_changed
      | Render_reset
      | Key_down of key
      | Key_up of key
      | Text_input of string
      | Text_editing of string * int * int
      | Mouse_motion of motion
      | Mouse_button_down of button
      | Mouse_button_up of button
      | Mouse_wheel of float * float
      | Drop_file of string
      | Drop_text of string
      | Drop_begin
      | Drop_complete
      | User of int
      | Other of int
    type event = { timestamp_ns : int64; window_id : int; kind : kind; }
    type t
    val make : ?timestamp_ns:int64 -> ?window_id:int -> kind -> event
    val create : unit -> t
    val of_event : event -> t
    val value : t -> event
    val map_pointer : (float -> float -> float * float) -> t -> t
  end
val poll_event : Event.t option -> bool
val wait_event : Event.t option -> bool
val wait_event_timeout : Event.t option -> int -> bool
val pump_events : unit -> unit
val push_key_event :
  Sdl3.T.window ->
  down:bool -> scancode:int -> keymod:int -> repeat:bool -> unit
val push_quit_event : unit -> unit
val push_expose_event : Sdl3.T.window -> unit
