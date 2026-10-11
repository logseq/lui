(* Thin bindings over the Win32 stubs of the window host executable.
   See lui_win32.mli for the event-tag contract. *)

type event = {
  tag : int;
  a : int;
  b : int;
  c : int;
  x : float;
  y : float;
  text : string;
}

let none = { tag = 0; a = 0; b = 0; c = 0; x = 0.; y = 0.; text = "" }

external create_window :
  w:int -> h:int -> title:string -> hidden:bool -> nativeint
  = "lww_create_window"
external destroy_window : nativeint -> unit = "lww_destroy_window"
external show_window : nativeint -> bool -> unit = "lww_show_window"
external set_title : nativeint -> string -> unit = "lww_set_title"
external client_size : nativeint -> int * int = "lww_client_size"
external next_event : unit -> event = "lww_next_event"
external present_frame : nativeint -> Bytes.t -> w:int -> h:int -> bool
  = "lww_present_frame"
external present_region :
  nativeint -> x0:int -> y0:int -> x1:int -> y1:int -> pix:Bytes.t ->
  stride:int -> bool = "lww_present_region_byte" "lww_present_region"
external dpi_scale : nativeint -> float = "lww_dpi_scale"
external set_ime_rect :
  nativeint -> x:int -> y:int -> w:int -> h:int -> unit
  = "lww_set_ime_rect"
external set_ime_enabled : nativeint -> bool -> unit
  = "lww_set_ime_enabled"
external send_wm_getobject :
  nativeint -> wparam:nativeint -> lparam:nativeint -> nativeint
  = "lww_send_wm_getobject"

external request_attention : nativeint -> unit
  = "lww_request_attention"
external perf_s : unit -> float = "lww_perf_s"
external delay_ms : int -> unit = "lww_delay_ms"
