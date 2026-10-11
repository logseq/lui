(* Thin bindings over the Win32 stubs of the window host executable:
   window creation, the decoded input-event queue, DIB presentation,
   IMM32 candidate placement and the high-resolution clock. Shell
   services (tray, menus, notifications, clipboard, dialogs) live in
   [Lui_shell_windows], which owns its own message window. Every
   entry point raises on non-Windows platforms; the executable and
   the real-call tests are gated on mingw64. *)

(** One decoded window event. [tag] selects the variant:

    - 0: no event pending (other fields meaningless)
    - 1: quit requested (WM_CLOSE / WM_DESTROY / WM_QUIT)
    - 2: resize — [a] = width, [b] = height, device pixels
    - 3: key down — [a] = VK code, [b] = mods bitmask, [c] = repeat
    - 4: text input — [text] = committed UTF-8 (WM_CHAR or IME result)
    - 5: text editing — [text] = composition UTF-8, [a] = selection
         start (UTF-8 byte offset), [b] = selection length
    - 6: mouse move — [x], [y] client pixels
    - 7: button down — [x], [y] client px, [a] = button (1 left, 2
         middle, 3 right), [b] = click count, [c] = mods bitmask
    - 8: button up — [x], [y] client px, [a] = button, [c] = mods
    - 9: wheel — [x] = horizontal lines, [y] = vertical lines
    - 10: present requested (WM_PAINT) — re-draw the last scene

    The mods bitmask: 1 ctrl, 2 shift, 4 alt, 8 meta (the Win key). *)
type event = {
  tag : int;
  a : int;
  b : int;
  c : int;
  x : float;
  y : float;
  text : string;
}

val none : event
(** The tag-0 event [next_event] returns when the queue is empty. *)

val create_window :
  w:int -> h:int -> title:string -> hidden:bool -> nativeint
(** Creates the host window ([w]×[h] logical pixels — the client area
    lands at that size times the window's DPI scale) and returns its
    HWND. The window's procedure forwards WM_GETOBJECT to the
    [lui_ax_windows] bridge and enqueues decoded input events.
    [hidden] leaves the window unshown for headless runs. *)

val destroy_window : nativeint -> unit
val show_window : nativeint -> bool -> unit
val set_title : nativeint -> string -> unit
val client_size : nativeint -> int * int
(** The client area in device pixels. *)

val next_event : unit -> event
(** Pumps one round of the message loop (TranslateMessage +
    DispatchMessage) and returns the oldest queued event, or [none].
    Call until it returns [none] — the equivalent of SDL_PollEvent. *)

val present_frame : nativeint -> Bytes.t -> w:int -> h:int -> bool
(** Blits a premultiplied BGRA frame ([w*h*4] bytes) into the window's
    client area. False on failure (no DC). *)

val present_region :
  nativeint -> x0:int -> y0:int -> x1:int -> y1:int -> pix:Bytes.t ->
  stride:int -> bool
(** Blits only the given rectangle of the full frame (damage path);
    [stride] is pixels per row of [pix]. *)

val dpi_scale : nativeint -> float
(** The window's DPI scale (GetDpiForWindow / 96). *)

val set_ime_rect : nativeint -> x:int -> y:int -> w:int -> h:int -> unit
(** Positions the IME candidate/composition window at the given
    client-space rect (device px). No-op without an IME context. *)

val set_ime_enabled : nativeint -> bool -> unit
(** Associates/disassociates the default IME context — the Windows
    half of text-input start/stop. *)

val send_wm_getobject :
  nativeint -> wparam:nativeint -> lparam:nativeint -> nativeint
(** A real [SendMessageW(hwnd, WM_GETOBJECT, wp, lp)] — the reply is
    produced by the window procedure's forwarding to the
    [Lui_ax_windows] bridge, so tests can verify the same path a
    screen reader uses (rather than calling the bridge directly). *)

val request_attention : nativeint -> unit
(** Flashes the window in the taskbar until it activates. *)

val perf_s : unit -> float
(** Seconds on the high-resolution performance counter. *)

val delay_ms : int -> unit
