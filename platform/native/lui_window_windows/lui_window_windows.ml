(* Windows helpers for the window host — see lui_window_windows.mli.
   Everything here is pure OCaml over the shared [Lui_window] core so
   the driver stays thin and tests need no Win32. *)

open Lui_protocol
open Lui_window

(* ---------- event translation ---------- *)

(* Win32 virtual-key constants for the keys with special handling;
   everything else reaches the app as [Other vk]. *)
let key_of_vk = function
  | 0x0D -> Input.Return (* VK_RETURN — keypad-enter is the same VK *)
  | 0x1B -> Input.Escape
  | 0x08 -> Input.Backspace
  | 0x2E -> Input.Delete
  | 0x09 -> Input.Tab
  | 0x20 -> Input.Space
  | 0x24 -> Input.Home
  | 0x21 -> Input.Page_up
  | 0x22 -> Input.Page_down
  | 0x23 -> Input.End
  | 0x25 -> Input.Arrow_left
  | 0x27 -> Input.Arrow_right
  | 0x26 -> Input.Arrow_up
  | 0x28 -> Input.Arrow_down
  | n -> Input.Other n

let button_of_win32 = function
  | 1 -> Input.Left
  | 2 -> Input.Middle
  | 3 -> Input.Right
  | n -> Input.Other n

let mods_of_mask m =
  Input.
    { ctrl = m land 1 <> 0;
      shift = m land 2 <> 0;
      alt = m land 4 <> 0;
      meta = m land 8 <> 0 }

(* Client pixels are device pixels under per-monitor DPI: pointer
   coordinates convert to the logical space [Ui] and the layout
   engine work in; the resize event reports the logical size. *)
let input_of_event ~scale (e : Lui_win32.event) =
  let open Input in
  match e.tag with
  | 1 -> Some Quit_input
  | 2 ->
    Some
      (Resize
         ( int_of_float (float e.a /. scale),
           int_of_float (float e.b /. scale) ))
  | 3 ->
    Some (Key_down (key_of_vk e.a, mods_of_mask e.b, e.c <> 0))
  | 4 -> Some (Text_input e.text)
  | 5 -> Some (Text_editing (e.text, e.a, e.b))
  | 6 -> Some (Move (e.x /. scale, e.y /. scale))
  | 7 ->
    Some
      (Button_down
         ( e.x /. scale,
           e.y /. scale,
           button_of_win32 e.a,
           e.b,
           mods_of_mask e.c ))
  | 8 ->
    Some
      (Button_up
         (e.x /. scale, e.y /. scale, button_of_win32 e.a,
          mods_of_mask e.c))
  | 9 -> Some (Wheel (e.x, e.y))
  | _ -> None

(* ---------- renderer ladder ---------- *)

type renderer_rung = Cpu | D3d11 | Gl | Noop

let ladder ~env =
  match env with
  | "0" | "cpu" -> [ Cpu; Noop ]
  | "gl" | "opengl" -> [ Gl; D3d11; Cpu; Noop ]
  | _ -> [ D3d11; Gl; Cpu; Noop ]

(* The last-resort renderer: consumes the scene, produces a correctly
   sized zeroed frame, and proves the loop paces, checks and exits
   without any graphics stack at all. *)
let noop_renderer : Lui_host.renderer =
  { Lui_host.name = "noop";
    render =
      (fun (s : Lui_scene.t) ->
         Bytes.create (s.Lui_scene.width * s.Lui_scene.height * 4)) }

(* ---------- assistive-technology actions ---------- *)

let float_prop store id name =
  match Lui_store.prop store id name with
  | Some (FloatValue f) -> Some f
  | Some (IntValue n) -> Some (float n)
  | Some (StringValue s) -> (try Some (float_of_string s)
                             with _ -> None)
  | _ -> None

(* UIA action -> protocol event, mirroring the pointer path: a screen
   reader's [Press] lands exactly where a click's [Press] does,
   behind the same admission gate ([event_supported] +
   [node_enabled]). [Expand]/[Collapse] map to the boolean toggle,
   [Set_value] to [ValueChanged], and [Increment]/[Decrement] step
   the node's numeric [value] prop by its [step] (default 1) inside
   [min]/[max] when present. *)
let a11y_event_of_action store id (act : Lui_ax_windows.action) =
  let open Lui_window in
  let ok e = node_enabled store id && event_supported store id e in
  let pick e = if ok e then Some e else None in
  let toggle_event () =
    (* Checkable kinds carry "checked"; toggle kinds carry
       "selected"; treeitems carry "expanded". *)
    let prop =
      match kind_name store id with
      | "toggle-button" | "toggle" -> "selected"
      | "list-item" -> "expanded"
      | _ -> "checked"
    in
    ToggleChanged (id, not (bool_prop store id prop))
  in
  let step dir =
    let cur = Option.value ~default:0. (float_prop store id "value") in
    let st =
      Option.value ~default:1. (float_prop store id "step") *. dir
    in
    let lo = Option.value ~default:Float.neg_infinity
        (float_prop store id "min") in
    let hi = Option.value ~default:Float.infinity
        (float_prop store id "max") in
    pick (ValueChanged (id, Float.min hi (Float.max lo (cur +. st))))
  in
  match act with
  | Lui_ax_windows.Press ->
    (match kind_name store id with
     | "toggle-button" | "toggle" | "checkbox" | "switch" ->
       pick (toggle_event ())
     | "radio" ->
       (* Mirrors the click path: prefer Change, then a set-true
          toggle, then a plain Press — first admitted wins. *)
       (match pick (Change id) with
        | Some _ as e -> e
        | None ->
          (match pick (ToggleChanged (id, true)) with
           | Some _ as e -> e
           | None -> pick (Press id)))
     | _ -> pick (Press id))
  | Lui_ax_windows.Expand -> pick (ToggleChanged (id, true))
  | Lui_ax_windows.Collapse -> pick (ToggleChanged (id, false))
  | Lui_ax_windows.Set_value s ->
    (match float_of_string_opt s with
     | Some v -> pick (ValueChanged (id, v))
     | None ->
       (* Textual Value.SetValue goes through TextChanged when the
          node admits it. *)
       pick (TextChanged (id, s)))
  | Lui_ax_windows.Increment -> step 1.
  | Lui_ax_windows.Decrement -> step (-1.)
  | Lui_ax_windows.Focus | Lui_ax_windows.Scroll_to_visible -> None

(* Value request from an AT (UIA Value.SetValue with a number): the
   protocol's [ValueChanged] behind the same gate. *)
let a11y_event_of_value store id v =
  let e = ValueChanged (id, v) in
  if
    Lui_window.node_enabled store id
    && Lui_window.event_supported store id e
  then Some e
  else None

(* 22x22 non-premultiplied RGBA icon: a filled rounded square in the
   theme's primary color with a transparent margin — the tray pixel
   payload [Lui_shell_windows.image_of_rgba] encodes. *)
let tray_icon_rgba () =
  let size = 22 in
  let b = Bytes.make (size * size * 4) '\000' in
  let put x y r g bl a =
    let i = ((y * size) + x) * 4 in
    Bytes.set b i (Char.chr r);
    Bytes.set b (i + 1) (Char.chr g);
    Bytes.set b (i + 2) (Char.chr bl);
    Bytes.set b (i + 3) (Char.chr a)
  in
  let r = 5. in
  for y = 1 to size - 2 do
    for x = 1 to size - 2 do
      let fx = float x +. 0.5 and fy = float y +. 0.5 in
      let dx =
        Float.max (2.5 -. fx) (fx -. float (size - 1) +. 1.5)
      in
      let dy =
        Float.max (2.5 -. fy) (fy -. float (size - 1) +. 1.5)
      in
      let inside =
        if dx <= 0. || dy <= 0. then true
        else (dx *. dx) +. (dy *. dy) <= r *. r
      in
      if inside then put x y 76 116 246 255
    done
  done;
  b
