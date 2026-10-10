(* Linux helpers for the window host: the renderer ladder decision,
   the accessibility action mapping and the tray-icon bitmap — the
   pure pieces the driver ([main.ml]) and the test suite share.
   Nothing here touches SDL, GL or a bus. *)

open Lui_protocol

(* The renderer ladder. [LUI_GPU=0|cpu] renders on the CPU
   ([Lui_raster]) and presents through [Lui_blit]; [LUI_GPU=vulkan]
   renders offscreen through [Lui_vulkan], reads the frame back and
   presents through [Lui_blit] — its present path is offscreen-only,
   so the blit texture is the window's share of the GPU. Anything else
   tries a GL 3.3 core context on the SDL window feeding [Lui_gl].

   Every rung can still fail at init (no display, no driver, no
   context): the driver walks the list left to right and always ends
   at [Noop], so the process never dies for want of a GPU. *)
type renderer_rung = Cpu | Vulkan | Gl | Noop

let ladder ~env =
  match env with
  | "0" | "cpu" -> [ Cpu; Noop ]
  | "vulkan" -> [ Vulkan; Gl; Noop ]
  | _ -> [ Gl; Noop ]

(* The last-resort renderer: consumes the scene, produces a correctly
   sized zeroed frame, and proves the loop paces, checks and exits
   without any graphics stack at all. *)
let noop_renderer : Lui_host.renderer =
  { Lui_host.name = "noop";
    render =
      (fun (s : Lui_scene.t) ->
         Bytes.create (s.Lui_scene.width * s.Lui_scene.height * 4)) }

(* AT-triggered action -> protocol event, mirroring the pointer path:
   a screen reader's "press" lands exactly where a click's [Press]
   does, behind the same admission gate ([event_supported] +
   [node_enabled]). The AT-SPI action names are the ones
   [Lui_ax_linux.actions_of] serves: "press" on activatable roles,
   "toggle" on checkable ones, "expand"/"contract" on expandable
   items. *)
let a11y_event_of_action store id name =
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
  match name with
  | "press" ->
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
  | "toggle" -> pick (toggle_event ())
  | "expand" -> pick (ToggleChanged (id, true))
  | "contract" -> pick (ToggleChanged (id, false))
  | _ -> None

(* Value request from an AT (Value:SetCurrentValue): the protocol's
   [ValueChanged] behind the same gate. *)
let a11y_event_of_value store id v =
  let e = ValueChanged (id, v) in
  if
    Lui_window.node_enabled store id
    && Lui_window.event_supported store id e
  then Some e
  else None

(* 22x22 non-premultiplied RGBA icon: a filled rounded square in the
   theme's primary color with a transparent margin — the tray pixel
   payload [Lui_shell_linux.image_of_rgba] encodes. Pure bitmap
   math so the asset needs no file on disk. *)
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
