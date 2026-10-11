(* Windows helpers for the window host: the decoded-event →
   [Lui_window.Input.t] translation, the renderer ladder decision,
   the UIA action → protocol event mapping and the tray-icon bitmap —
   the pure pieces the driver ([main.ml]) and the test suite share.
   Nothing here touches Win32, D3D11 or a session. *)

(** {1 Event translation} *)

val key_of_vk : int -> Lui_window.Input.key
(** Win32 virtual-key codes → keys (0x0D return, 0x1B escape, 0x08
    backspace, 0x2E delete, 0x09 tab, 0x20 space, 0x24 home, 0x21/0x22
    page up/down, 0x23 end, 0x25-0x28 arrows). Pure table so the
    driver stays thin and tests need no Win32. *)

val button_of_win32 : int -> Lui_window.Input.mouse_button
(** Driver-internal button numbering: 1 left, 2 middle, 3 right —
    the [Lui_win32] event order. *)

val mods_of_mask : int -> Lui_window.Input.mods
(** The [Lui_win32] mods bitmask (1 ctrl, 2 shift, 4 alt, 8 meta) →
    the [Input.mods] record. *)

val input_of_event : scale:float -> Lui_win32.event ->
  Lui_window.Input.t option
(** One window event → at most one backend-neutral input. Pointer
    coordinates arrive in client (device) pixels and are converted to
    logical pixels with the current DPI scale; [Resize] carries the
    logical size the layout engine wants. *)

(** {1 Renderer ladder} *)

type renderer_rung = Cpu | D3d11 | Gl | Noop
(** [LUI_GPU=0|cpu] renders on the CPU ([Lui_raster]) and presents
    through DIB blits; the default rung [D3d11] tries a DXGI
    swapchain on the window first, then an offscreen target whose
    frames are read back and blitted; [gl] is only meaningful on
    builds that link [Lui_gl] — this one cannot (no GL bindings on
    the VM) so the rung always reports and falls through. Every rung
    can still fail at init: the driver walks the list left to right
    and always ends at [Noop], so the process never dies for want of
    a GPU. *)

val ladder : env:string -> renderer_rung list

val noop_renderer : Lui_host.renderer
(** The last-resort renderer: consumes the scene, produces a
    correctly sized zeroed frame, and proves the loop paces, checks
    and exits without any graphics stack at all. *)

(** {1 Assistive-technology actions} *)

val a11y_event_of_action : Lui_store.t -> int -> Lui_ax_windows.action ->
  Lui_protocol.event option
(** AT-triggered action → protocol event, mirroring the pointer path:
    a screen reader's [Press] lands exactly where a click's [Press]
    does, behind the same admission gate ([event_supported] +
    [node_enabled]). [Focus] and [Scroll_to_visible] are not protocol
    events — the driver handles them directly ([Ui.set_focused]; no
    scroll-into-view event exists yet). *)

val a11y_event_of_value : Lui_store.t -> int -> float ->
  Lui_protocol.event option
(** Value request from an AT (UIA Value.SetValue): the protocol's
    [ValueChanged] behind the same gate. *)

(** {1 Tray icon} *)

val tray_icon_rgba : unit -> bytes
(** 22x22 non-premultiplied RGBA icon: a filled rounded square in the
    theme's primary color with a transparent margin — the tray pixel
    payload [Lui_shell_windows.image_of_rgba] encodes. Pure bitmap
    math so the asset needs no file on disk. *)
