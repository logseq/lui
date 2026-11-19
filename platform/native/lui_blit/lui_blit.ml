(* SDL software present path for CPU-rendered frames. *)

module Sdl = Lui_sdl3

type pix_ba =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type t = {
  renderer : Sdl.renderer;
  mutable texture : Sdl.texture;
  mutable upload : pix_ba; (* full-frame staging for [update] *)
  mutable w : int;
  mutable h : int;
}

let name = "lui_blit"

let err fmt = Printf.ksprintf (fun s -> Error s) fmt

let sdl_error prefix = function
  | Ok v -> Ok v
  | Error (`Msg m) -> err "%s: %s" prefix m

(* The frame buffer is premultiplied BGRA in memory byte order.  On
   little-endian, SDL_PIXELFORMAT_ARGB8888 stores bytes B,G,R,A per
   pixel — the same layout (the spike verified this end to end). *)
let tex_format = Sdl.Pixel.format_argb8888

let make_texture renderer ~w ~h =
  Sdl.create_texture renderer tex_format Sdl.Texture.access_streaming
    ~w ~h

let create win ~w ~h =
  match sdl_error "create_renderer"
          (Sdl.create_renderer win ~software:true) with
  | Error _ as e -> e
  | Ok renderer ->
    (match sdl_error "create_texture" (make_texture renderer ~w ~h) with
     | Error _ as e -> e
     | Ok texture ->
       Ok { renderer; texture;
            upload = Bigarray.Array1.create Bigarray.int8_unsigned
                       Bigarray.c_layout (w * h * 4);
            w; h })

let resize t ~w ~h =
  match make_texture t.renderer ~w ~h with
  | Error (`Msg m) -> err "resize texture: %s" m
  | Ok texture ->
    Sdl.destroy_texture t.texture;
    t.texture <- texture;
    t.upload <- Bigarray.Array1.create Bigarray.int8_unsigned
                  Bigarray.c_layout (w * h * 4);
    t.w <- w;
    t.h <- h;
    Ok ()

(* Copy [h] rows of [w] pixels out of a [stride]-pixel-wide buffer
   into a tight bigarray. *)
let copy_rows ~pix ~stride ~x0 ~y0 ~w ~h ~dst =
  for row = 0 to h - 1 do
      let src = ((y0 + row) * stride + x0) * 4 in
      let sub = Bigarray.Array1.sub dst (row * w * 4) (w * 4) in
      for i = 0 to (w * 4) - 1 do
        sub.{i} <- int_of_char (Bytes.get pix (src + i))
      done
    done

(* update_texture's pitch is in bigarray elements; for an 8-bit kind
   that equals bytes. *)
let update t ~pix ~stride =
  if Bytes.length pix < stride * t.h * 4 then
    err "pix buffer too small (%d < %d)" (Bytes.length pix) (stride * t.h * 4)
  else begin
    copy_rows ~pix ~stride ~x0:0 ~y0:0 ~w:t.w ~h:t.h ~dst:t.upload;
    sdl_error "update_texture"
      (Sdl.update_texture t.texture None t.upload (t.w * 4))
  end

let update_region t ~x0 ~y0 ~x1 ~y1 ~pix ~stride =
  let x0 = max 0 x0 and y0 = max 0 y0 in
  let x1 = min t.w x1 and y1 = min t.h y1 in
  if x1 <= x0 || y1 <= y0 then Ok ()
  else begin
    let rw = x1 - x0 and rh = y1 - y0 in
    (* SDL_UpdateTexture reads the rect's pixels contiguously at the
       rect pitch — repack the damaged rows into a tight buffer. *)
    let tmp = Bigarray.Array1.create Bigarray.int8_unsigned
                Bigarray.c_layout (rw * rh * 4) in
    copy_rows ~pix ~stride ~x0 ~y0 ~w:rw ~h:rh ~dst:tmp;
    let rect = Sdl.Rect.create ~x:x0 ~y:y0 ~w:rw ~h:rh in
    sdl_error "update_texture region"
      (Sdl.update_texture t.texture (Some rect) tmp (rw * 4))
  end

let present t =
  ignore (Sdl.render_copy t.renderer t.texture);
  Sdl.render_present t.renderer

let create_blit = create

module Popups = struct
  type surface = {
    window : Sdl.window;
    blit : t;
    geometry : int * int * int * int;
    mutable seen : bool;
    mutable origin : float * float;
    mutable ratio : float * float;
  }

  type t = (int, surface) Hashtbl.t

  let create () = Hashtbl.create 4

  let clear windows =
    Hashtbl.iter (fun _ surface -> Sdl.destroy_window surface.window) windows;
    Hashtbl.clear windows

  let finish windows =
    Hashtbl.filter_map_inplace (fun _ surface ->
      if surface.seen then begin surface.seen <- false; Some surface end
      else begin Sdl.destroy_window surface.window; None end) windows

  let present windows ~parent ~id ~tooltip ~scale ~rect:(px, py, width, height) pixels =
    let pw = int_of_float width and ph = int_of_float height in
    let logical n = int_of_float (Float.round (n /. scale)) in
    let x = logical px and y = logical py in
    let w = max 1 (logical width) and h = max 1 (logical height) in
    let origin = (px /. scale, py /. scale) in
    let ratio = (width /. scale /. float w, height /. scale /. float h) in
    let geometry = (x, y, w, h) in
    let surface =
      match Hashtbl.find_opt windows id with
      | Some surface when surface.geometry = geometry -> Some surface
      | old ->
        Option.iter (fun surface -> Sdl.destroy_window surface.window) old;
        Hashtbl.remove windows id;
        match Sdl.create_popup_window parent ~tooltip ~x ~y ~w ~h with
        | Error _ -> None
        | Ok window ->
          match create_blit window ~w:pw ~h:ph with
          | Error _ -> Sdl.destroy_window window; None
          | Ok blit ->
            let surface = { window; blit; geometry; seen = false; origin; ratio } in
            Hashtbl.add windows id surface;
            Some surface
    in
    match surface with
    | None -> false
    | Some surface ->
      let target = surface.blit in
      let sized = if target.w = pw && target.h = ph then Ok ()
        else resize target ~w:pw ~h:ph in
      match sized with
      | Error _ -> false
      | Ok () ->
        let pix, stride = pixels () in
        match update target ~pix ~stride with
        | Error _ -> false
        | Ok () ->
          match
            (try Sdl.show_window surface.window;
                 match Sdl.render_copy target.renderer target.texture with
                 | Error _ -> false
                 | Ok () -> Sdl.render_present target.renderer; true
             with Failure _ -> false)
          with
          | false -> false
          | true ->
            surface.origin <- origin;
            surface.ratio <- ratio;
            surface.seen <- true;
            true

  let route windows event =
    let e = Sdl.Event.value event in
    Hashtbl.fold (fun _ surface found ->
      if found <> None || Sdl.get_window_id surface.window <> e.window_id
      then found
      else
        let x, y = surface.origin in
        let sx, sy = surface.ratio in
        Some (Sdl.Event.map_pointer
          (fun a b -> x +. a *. sx, y +. b *. sy) event)) windows None
end
