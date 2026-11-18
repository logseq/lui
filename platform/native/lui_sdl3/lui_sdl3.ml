(* SDL3 host operations and owned event snapshots. Native resources retain
   the distinct types provided by the pinned SDL3 binding. *)
module S = Sdl3.Sdl
module T = Sdl3.T

type window = T.window
type renderer = T.renderer
type texture = T.texture
type gl_context = T.gl_context
type cursor = T.cursor

let require = function Ok value -> value | Error (`Msg message) -> failwith ("SDL3: " ^ message)

module Init = struct
  let video = S.init_video
  let events = S.init_events
  let ( + ) = ( lor )
end

module Window = struct
  let none = 0L
  let hidden = S.window_hidden
  let resizable = S.window_resizable
  let high_pixel_density = S.window_high_pixel_density
  let opengl = S.window_opengl
  let metal = S.window_metal
  let borderless = S.window_borderless
  let ( + ) = Int64.logor
end

module Gl = struct
  type attr = T.gl_attr
  let context_major_version = T.GL_CONTEXT_MAJOR_VERSION
  let context_minor_version = T.GL_CONTEXT_MINOR_VERSION
  let context_profile_mask = T.GL_CONTEXT_PROFILE_MASK
  let doublebuffer = T.GL_DOUBLEBUFFER
  let depth_size = T.GL_DEPTH_SIZE
  let stencil_size = T.GL_STENCIL_SIZE
  let context_flags = T.GL_CONTEXT_FLAGS
  let context_profile_core = S.gl_context_profile_core
  let context_forward_compatible_flag = S.gl_context_forward_compatible_flag
end

module Kmod = struct
  let ctrl = S.kmod_lctrl lor S.kmod_rctrl
  let shift = S.kmod_lshift lor S.kmod_rshift
  let alt = S.kmod_lalt lor S.kmod_ralt
  let gui = S.kmod_lgui lor S.kmod_rgui
  let lctrl = S.kmod_lctrl
  let rctrl = S.kmod_rctrl
  let lshift = S.kmod_lshift
  let rshift = S.kmod_rshift
  let lalt = S.kmod_lalt
  let ralt = S.kmod_ralt
  let lgui = S.kmod_lgui
  let rgui = S.kmod_rgui
end

module Scancode = struct
  let lshift = S.scancode_lshift
  let a = S.scancode_a
  let c = S.scancode_c
  let v = S.scancode_v
  let x = S.scancode_x
  let z = S.scancode_z
end

module System_cursor = struct
  type t = T.system_cursor
  let arrow = T.SYSTEM_CURSOR_DEFAULT
  let ibeam = T.SYSTEM_CURSOR_TEXT
  let hand = T.SYSTEM_CURSOR_POINTER
  let no = T.SYSTEM_CURSOR_NOT_ALLOWED
  let wait = T.SYSTEM_CURSOR_WAIT
  let waitarrow = T.SYSTEM_CURSOR_PROGRESS
  let sizewe = T.SYSTEM_CURSOR_EW_RESIZE
  let sizens = T.SYSTEM_CURSOR_NS_RESIZE
  let sizeall = T.SYSTEM_CURSOR_MOVE
  let sizenwse = T.SYSTEM_CURSOR_NWSE_RESIZE
  let sizenesw = T.SYSTEM_CURSOR_NESW_RESIZE
  let crosshair = T.SYSTEM_CURSOR_CROSSHAIR
end

module Rect = struct
  type t = T.rect
  let create ~x ~y ~w ~h = T.Rect.create ~x ~y ~w ~h ()
end

module Pixel = struct let format_argb8888 = S.pixelformat_argb8888 end
module Texture = struct let access_streaming = S.textureaccess_streaming end

let work_event = ref 0

let init flags =
  match S.init flags with
  | Ok () when !work_event = 0 ->
    let event = S.Event.registers 1 in
    if event < S.event_user || event >= S.event_last then begin
      let error = S.Error.get () in
      S.quit ();
      Error (`Msg error)
    end else begin
      work_event := event;
      Ok ()
    end
  | result -> result

let pending = Hashtbl.create 8
let pending_lock = Mutex.create ()
let next_work = Atomic.make 0
let work_error = ref None

let take_work id =
  Mutex.protect pending_lock (fun () ->
      let work = Hashtbl.find_opt pending id in
      Hashtbl.remove pending id;
      work)

let run_work userdata =
  let id = Nativeint.to_int (Ctypes.raw_address_of_ptr userdata) in
  Option.iter
    (fun work ->
      try
        Fun.protect work ~finally:(fun () ->
            require (S.Event.push (S.Event.create ~typ:!work_event ())))
      with exn ->
        let bt = Printexc.get_raw_backtrace () in
        if Option.is_none !work_error then work_error := Some (exn, bt))
    (take_work id)

let quit () =
  S.quit ();
  Mutex.protect pending_lock (fun () -> Hashtbl.clear pending);
  work_event := 0;
  work_error := None

let run_on_main_thread work =
  if S.is_main_thread () then work ()
  else begin
    let id = 1 + Atomic.fetch_and_add next_work 1 in
    Mutex.protect pending_lock (fun () -> Hashtbl.add pending id work);
    let data = Ctypes.ptr_of_raw_address (Nativeint.of_int id) in
    match S.run_on_main_thread run_work data false with
    | Ok () -> ()
    | Error _ as failure ->
      ignore (take_work id);
      require failure
  end

let check_work_error () =
  match !work_error with
  | None -> ()
  | Some (exn, bt) ->
    work_error := None;
    Printexc.raise_with_backtrace exn bt
let get_error = S.Error.get
let delay = S.delay
let get_performance_counter = S.get_performance_counter
let get_performance_frequency = S.get_performance_frequency
let get_ticks = S.get_ticks
let get_ticks_ns = S.get_ticks_ns
let get_mod_state = S.get_mod_state
let set_mod_state = S.set_mod_state
let get_scancode_name = S.Scancode.get_name
let create_window title ~w ~h flags = S.Window.create title w h flags
let destroy_window = S.Window.destroy
let show_window window = require (S.Window.show window)
let raise_window window = require (S.Window.raise_ window)
let get_window_id = S.Window.get_id
type native_handle =
  | Cocoa_window of nativeint
  | X11_window of int
  | Wayland_surface of nativeint

let native_handle window =
  let props = S.Window.get_properties window in
  let pointer key =
    Ctypes.raw_address_of_ptr (S.get_pointer_property props key Ctypes.null)
  in
  let cocoa = pointer S.prop_window_cocoa_window_pointer in
  if cocoa <> Nativeint.zero then Some (Cocoa_window cocoa)
  else
    let wayland = pointer S.prop_window_wayland_surface_pointer in
    if wayland <> Nativeint.zero then Some (Wayland_surface wayland)
    else
      let xid = S.get_number_property props S.prop_window_x11_window_number 0 in
      if xid <> 0 then Some (X11_window xid) else None
let get_window_size window = require (S.Window.get_size window)
let get_window_size_in_pixels window = require (S.Window.get_size_in_pixels window)
let unsafe_ptr_of_window (window : window) = Ctypes.(raw_address_of_ptr (to_voidp window))
let set_window_minimum_size window ~w ~h = require (S.Window.set_minimum_size window w h)
let get_window_display_id window =
  match S.Window.get_display_for window with
  | 0 -> Error (`Msg (S.Error.get ()))
  | id -> Ok id
let display_refresh_rate id =
  match S.Display.get_current_mode id with
  | Error _ as error -> error
  | Ok mode -> Ok (T.DisplayMode.get mode T.DisplayMode.refresh_rate)
let gl_set_attribute attr value = S.gl_set_attribute (T.gl_attr_to_enum attr) value
let gl_get_attribute attr = S.gl_get_attribute (T.gl_attr_to_enum attr)
let gl_create_context = S.gl_create_context
let gl_make_current = S.gl_make_current
let gl_delete_context context = require (S.gl_destroy_context context)
let gl_set_swap_interval = S.gl_set_swap_interval
let gl_swap_window window = require (S.Window.gl_swap window)
type capitalization = None_ | Sentences | Words | Letters

let start_text_input ?(multiline=false) ?(secure=false)
    ?autocorrect ?capitalization window =
  let props = S.Properties.create () in
  if props = 0 then failwith ("SDL3: " ^ S.Error.get ());
  Fun.protect ~finally:(fun () -> S.Properties.destroy props) (fun () ->
      let set = S.set_boolean_property props in
      let set_number = S.set_number_property props in
      require (set S.prop_textinput_multiline_boolean multiline);
      if secure then require (set_number S.prop_textinput_type_number
        S.textinput_type_text_password_hidden);
      Option.iter (fun enabled ->
          require (set S.prop_textinput_autocorrect_boolean enabled))
        (if secure then Some false else autocorrect);
      Option.iter (fun hint ->
          let value = match hint with
            | None_ -> S.capitalize_none | Sentences -> S.capitalize_sentences
            | Words -> S.capitalize_words | Letters -> S.capitalize_letters in
          require (set_number S.prop_textinput_capitalization_number value))
        (if secure then Some None_ else capitalization);
      require (S.start_text_input_with_properties window props))
let stop_text_input window = require (S.stop_text_input window)
let is_text_input_active = S.text_input_active
let set_text_input_area window rect ~cursor =
  require (S.set_text_input_area window rect cursor)
let create_system_cursor cursor = S.SystemCursor.create (T.system_cursor_to_enum cursor)
let set_cursor cursor = require (S.Cursor.set cursor)
let destroy_cursor = S.Cursor.destroy
let create_renderer ?(software=false) ?(vsync=false) window =
  match S.Renderer.create window (if software then "software" else "") with
  | Error _ as error -> error
  | Ok renderer ->
    if not vsync then Ok renderer
    else match S.Renderer.set_v_sync renderer 1 with
      | Ok () -> Ok renderer
      | Error _ as error -> S.Renderer.destroy renderer; error
let destroy_renderer = S.Renderer.destroy
let renderer_name = S.Renderer.get_name
let get_renderer_output_size = S.Renderer.get_output_size
let create_texture renderer format access ~w ~h = S.Texture.create renderer format access w h
let destroy_texture = S.Texture.destroy
let update_texture texture rect pixels pitch =
  S.Texture.update texture rect Ctypes.(to_voidp (bigarray_start array1 pixels)) pitch
let render_copy renderer texture = S.render_texture renderer texture None None
let render_debug_text renderer ~x ~y text = S.render_debug_text renderer x y text
let render_present renderer = require (S.Renderer.present renderer)

module Event = struct
  type window_change =
    | Resized | Pixel_size_changed | Display_scale_changed | Display_changed
    | Close_requested | Moved | Hidden | Minimized | Shown | Restored
    | Exposed | Focus_gained | Focus_lost | Other_window of int
  type key = {scancode : int; keymod : int; repeat : bool}
  type motion = {x : float; y : float; xrel : float; yrel : float}
  type button = {x : float; y : float; button : int; clicks : int}
  type kind =
    | Quit
    | Window of window_change * int * int
    | Display_changed
    | Render_reset
    | Key_down of key | Key_up of key
    | Text_input of string
    | Text_editing of string * int * int
    | Mouse_motion of motion
    | Mouse_button_down of button | Mouse_button_up of button
    | Mouse_wheel of float * float
    | Drop_file of string | Drop_text of string
    | Drop_begin | Drop_complete
    | User of int
    | Other of int
  type event = {timestamp_ns : int64; window_id : int; kind : kind}
  type t = {raw : T.event; mutable event : event}
  let make ?(timestamp_ns=0L) ?(window_id=0) kind = {timestamp_ns; window_id; kind}
  let create () = {raw=S.Event.create (); event=make (Other 0)}
  let of_event event = {raw=S.Event.create (); event}
  let value event = event.event

  let window_change : int -> window_change = function
    | n when n = S.event_window_resized -> Resized
    | n when n = S.event_window_pixel_size_changed -> Pixel_size_changed
    | n when n = S.event_window_display_scale_changed -> Display_scale_changed
    | n when n = S.event_window_display_changed -> Display_changed
    | n when n = S.event_window_close_requested -> Close_requested
    | n when n = S.event_window_moved -> Moved
    | n when n = S.event_window_hidden -> Hidden
    | n when n = S.event_window_minimized -> Minimized
    | n when n = S.event_window_shown -> Shown
    | n when n = S.event_window_restored -> Restored
    | n when n = S.event_window_exposed -> Exposed
    | n when n = S.event_window_focus_gained -> Focus_gained
    | n when n = S.event_window_focus_lost -> Focus_lost
    | n -> Other_window n

  let snapshot raw =
    let typ = S.Event.(get raw typ) in
    let common_event = S.Event.(get raw common) in
    let timestamp_ns = T.CommonEvent.(get common_event timestamp) in
    let window_id, kind =
      if typ = S.event_quit then 0, Quit
      else if typ >= S.event_window_first && typ <= S.event_window_last then
        let window_event = S.Event.(get raw window) in
        T.WindowEvent.(get window_event window_id),
        Window (window_change typ, T.WindowEvent.(get window_event data1), T.WindowEvent.(get window_event data2))
      else if typ >= S.event_display_first && typ <= S.event_display_last then 0, Display_changed
      else if typ = S.event_render_targets_reset || typ = S.event_render_device_reset then 0, Render_reset
      else if typ = S.event_key_down || typ = S.event_key_up then
        let key_event = S.Event.(get raw key) in
        let payload = {scancode=T.KeyboardEvent.(get key_event scancode);
                       keymod=T.KeyboardEvent.(get key_event mod_); repeat=T.KeyboardEvent.(get key_event repeat)} in
        T.KeyboardEvent.(get key_event window_id), (if typ = S.event_key_down then Key_down payload else Key_up payload)
      else if typ = S.event_text_input then
        let text_event = S.Event.(get raw text) in
        T.TextInputEvent.(get text_event window_id), Text_input T.TextInputEvent.(get text_event text)
      else if typ = S.event_text_editing then
        let edit_event = S.Event.(get raw edit) in
        T.TextEditingEvent.(get edit_event window_id),
        Text_editing (T.TextEditingEvent.(get edit_event text), T.TextEditingEvent.(get edit_event start), T.TextEditingEvent.(get edit_event length))
      else if typ = S.event_mouse_motion then
        let motion_event = S.Event.(get raw motion) in
        T.MouseMotionEvent.(get motion_event window_id), Mouse_motion {
          x=T.MouseMotionEvent.(get motion_event x); y=T.MouseMotionEvent.(get motion_event y);
          xrel=T.MouseMotionEvent.(get motion_event xrel); yrel=T.MouseMotionEvent.(get motion_event yrel)}
      else if typ = S.event_mouse_button_down || typ = S.event_mouse_button_up then
        let button_event = S.Event.(get raw button) in
        let payload = {x=T.MouseButtonEvent.(get button_event x); y=T.MouseButtonEvent.(get button_event y);
                       button=T.MouseButtonEvent.(get button_event button); clicks=T.MouseButtonEvent.(get button_event clicks)} in
        T.MouseButtonEvent.(get button_event window_id), (if typ = S.event_mouse_button_down then Mouse_button_down payload else Mouse_button_up payload)
      else if typ = S.event_mouse_wheel then
        let wheel_event = S.Event.(get raw wheel) in
        T.MouseWheelEvent.(get wheel_event window_id), Mouse_wheel (T.MouseWheelEvent.(get wheel_event x), T.MouseWheelEvent.(get wheel_event y))
      else if typ >= S.event_drop_file && typ <= S.event_drop_position then
        let drop_event = S.Event.(get raw drop) in
        let kind =
          if typ = S.event_drop_file then Drop_file T.DropEvent.(get drop_event data)
          else if typ = S.event_drop_text then Drop_text T.DropEvent.(get drop_event data)
          else if typ = S.event_drop_begin then Drop_begin
          else if typ = S.event_drop_complete then Drop_complete
          else Other typ in
        T.DropEvent.(get drop_event window_id), kind
      else if typ >= S.event_user && typ < S.event_last then
        let user_event = S.Event.(get raw user) in
        T.UserEvent.(get user_event window_id), User T.UserEvent.(get user_event code)
      else 0, Other typ in
    {timestamp_ns; window_id; kind}
end

let receive_event receive event =
  let raw = Option.map (fun event -> event.Event.raw) event in
  let received = receive raw in
  check_work_error ();
  if received then begin
    Option.iter (fun event -> event.Event.event <- Event.snapshot event.Event.raw) event;
    true
  end else false
let poll_event event = receive_event S.Event.poll event
let wait_event event =
  receive_event (fun raw -> require (S.Event.wait raw); true) event
let wait_event_timeout event timeout =
  receive_event (fun raw -> S.Event.wait_timeout raw timeout) event
let pump_events () =
  S.Event.pumps ();
  check_work_error ()
let push_key_event window ~down ~scancode ~keymod ~repeat =
  let event = S.Event.create () in
  let key_event = S.Event.(get event key) in
  T.KeyboardEvent.set key_event T.KeyboardEvent.typ (if down then S.event_key_down else S.event_key_up);
  T.KeyboardEvent.set key_event T.KeyboardEvent.window_id (get_window_id window);
  T.KeyboardEvent.set key_event T.KeyboardEvent.scancode scancode;
  T.KeyboardEvent.set key_event T.KeyboardEvent.mod_ keymod;
  T.KeyboardEvent.set key_event T.KeyboardEvent.down down;
  T.KeyboardEvent.set key_event T.KeyboardEvent.repeat repeat;
  require (S.Event.push event)
let push_quit_event () = require (S.Event.push (S.Event.create ~typ:S.event_quit ()))

let push_expose_event window =
  let event = S.Event.create () in
  let window_event = S.Event.(get event window) in
  T.WindowEvent.set window_event T.WindowEvent.typ S.event_window_exposed;
  T.WindowEvent.set window_event T.WindowEvent.window_id (get_window_id window);
  require (S.Event.push event)
