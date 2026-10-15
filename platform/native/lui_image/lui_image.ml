(* Image decoding and color-atlas management for the native backend.
   See lui_image.mli for the contract. *)

open Bigarray

type format = Png | Gif | Bmp | Pnm | Jpeg

(* Decoded image: premultiplied RGBA8 in a flat bigarray, rows tightly
   packed (4 * width bytes per row). [digest] identifies the encoded
   input and keys the cache. *)
type image = {
  iw : int;
  ih : int;
  iformat : format;
  idigest : string;
  ipix : (int, int8_unsigned_elt, c_layout) Array1.t;
}

let width i = i.iw
let height i = i.ih
let size_bytes i = Array1.dim i.ipix
let format i = i.iformat
let pixels i = i.ipix

let pixels_bytes i =
  let n = Array1.dim i.ipix in
  Bytes.init n (fun k -> Char.chr (Array1.unsafe_get i.ipix k))

let to_scene_image i = Lui_scene.new_image ~w:i.iw ~h:i.ih (pixels_bytes i)

(* ------------------------------------------------------------------ *)
(* Decoding                                                            *)

let sniff b =
  let n = Bytes.length b in
  let u8 i = Char.code (Bytes.get b i) in
  if n >= 8 && u8 0 = 0x89 && u8 1 = 0x50 && u8 2 = 0x4E && u8 3 = 0x47
     && u8 4 = 0x0D && u8 5 = 0x0A && u8 6 = 0x1A && u8 7 = 0x0A
  then Some Png
  else if n >= 3 && u8 0 = 0xFF && u8 1 = 0xD8 && u8 2 = 0xFF then Some Jpeg
  else if n >= 6
          && (Bytes.sub_string b 0 6 = "GIF87a"
              || Bytes.sub_string b 0 6 = "GIF89a")
  then Some Gif
  else if n >= 2 && u8 0 = 0x42 && u8 1 = 0x4D then Some Bmp
  else if n >= 2 && u8 0 = 0x50 && u8 1 >= 0x31 && u8 1 <= 0x36 then Some Pnm
  else None

let format_name = function
  | Png -> "png" | Gif -> "gif" | Bmp -> "bmp" | Pnm -> "pnm" | Jpeg -> "jpeg"

(* Premultiply one 8-bit channel by 8-bit alpha, rounding half-up. *)
let premul8 c a = (c * a + 127) / 255

(* Convert a decoded imagelib image into premultiplied RGBA8. Values
   are normalized to 8 bits via max_val (255 for Pix8, 65535 for Pix16
   PNGs, arbitrary for PNM). *)
let of_imagelib ~digest ~iformat (im : Image.image) : image =
  let w = im.Image.width and h = im.Image.height in
  let mv = im.Image.max_val in
  let scale v = if mv = 255 then v else (v * 255 + mv / 2) / mv in
  let px = Array1.create Int8_unsigned C_layout (4 * w * h) in
  let set k v = Array1.unsafe_set px k v in
  (match im.Image.pixels with
   | Image.RGB (r, g, b) ->
     for y = 0 to h - 1 do
       for x = 0 to w - 1 do
         let k = 4 * (y * w + x) in
         set k (scale (Image.Pixmap.get r x y));
         set (k + 1) (scale (Image.Pixmap.get g x y));
         set (k + 2) (scale (Image.Pixmap.get b x y));
         set (k + 3) 255
       done
     done
   | Image.RGBA (r, g, b, a) ->
     for y = 0 to h - 1 do
       for x = 0 to w - 1 do
         let k = 4 * (y * w + x) in
         let av = scale (Image.Pixmap.get a x y) in
         set k (premul8 (scale (Image.Pixmap.get r x y)) av);
         set (k + 1) (premul8 (scale (Image.Pixmap.get g x y)) av);
         set (k + 2) (premul8 (scale (Image.Pixmap.get b x y)) av);
         set (k + 3) av
       done
     done
   | Image.Grey g ->
     for y = 0 to h - 1 do
       for x = 0 to w - 1 do
         let k = 4 * (y * w + x) in
         let v = scale (Image.Pixmap.get g x y) in
         set k v; set (k + 1) v; set (k + 2) v; set (k + 3) 255
       done
     done
   | Image.GreyA (g, a) ->
     for y = 0 to h - 1 do
       for x = 0 to w - 1 do
         let k = 4 * (y * w + x) in
         let av = scale (Image.Pixmap.get a x y) in
         let v = premul8 (scale (Image.Pixmap.get g x y)) av in
         set k v; set (k + 1) v; set (k + 2) v; set (k + 3) av
       done
     done);
  { iw = w; ih = h; iformat; idigest = digest; ipix = px }

let decode (b : bytes) : (image, string) result =
  match sniff b with
  | None -> Error "unrecognized image format"
  | Some Jpeg ->
    Error "jpeg decoding unsupported: bundled decoder is size-only"
  | Some iformat ->
    let reader = ImageUtil.chunk_reader_of_string (Bytes.to_string b) in
    (try
       let im =
         match iformat with
         | Png -> ImageLib.PNG.parsefile reader
         | Gif -> ImageLib.GIF.parsefile reader
         | Bmp -> ImageLib.BMP.ReadBMP.parsefile reader
         | Pnm -> ImageLib.PPM.parsefile reader
         | Jpeg -> assert false
       in
       Ok (of_imagelib ~digest:(Digest.to_hex (Digest.bytes b)) ~iformat im)
     with e ->
       Error (Printf.sprintf "%s decode failed: %s"
                (format_name iformat) (Printexc.to_string e)))

(* ------------------------------------------------------------------ *)
(* Object-fit sizing                                                   *)

type fit = Contain | Cover | Fill | Natural

(* n / d rounded half-up, for n, d >= 0. *)
let round_div n d = (2 * n + d) / (2 * d)

let fit_size f ~iw ~ih ~w ~h =
  match f with
  | Fill -> (w, h)
  | Natural -> (iw, ih)
  | Contain ->
    if w * ih < h * iw then (w, round_div (ih * w) iw)
    else (round_div (iw * h) ih, h)
  | Cover ->
    if w * ih > h * iw then (w, round_div (ih * w) iw)
    else (round_div (iw * h) ih, h)

let fit_rect f ~iw ~ih ~x ~y ~w ~h =
  if iw <= 0 || ih <= 0 || w <= 0 || h <= 0 then (x, y, 0, 0)
  else
    let (sw, sh) = fit_size f ~iw ~ih ~w ~h in
    (x + (w - sw) / 2, y + (h - sh) / 2, sw, sh)

(* ------------------------------------------------------------------ *)
(* Color-atlas upload                                                  *)

type entry = {
  ex : int;
  ey : int;
  ew : int;
  eh : int;
  egen : int;
  etransient : bool;
}

let upload ?(transient = true) (atlas : Lui_scene.Atlas.t) i =
  if atlas.Lui_scene.Atlas.bpp <> 4 then
    Error "atlas is not a color atlas (bpp <> 4)"
  else
    let w = i.iw and h = i.ih in
    let rec try_alloc () =
      let r =
        if transient then Lui_scene.Atlas.alloc_transient atlas w h
        else Lui_scene.Atlas.alloc_last atlas w h
      in
      match r with
      | Some (x, y) -> Some (x, y)
      | None -> if Lui_scene.Atlas.grow atlas then try_alloc () else None
    in
    match try_alloc () with
    | None ->
      Error (Printf.sprintf "atlas full: %dx%d does not fit" w h)
    | Some (x, y) ->
      Lui_scene.Atlas.put atlas ~x ~y ~w ~h ~src:(pixels_bytes i) ~stride:(4 * w);
      Ok { ex = x; ey = y; ew = w; eh = h; egen = atlas.Lui_scene.Atlas.gen;
           etransient = transient }

(* ------------------------------------------------------------------ *)
(* Cache                                                               *)

module Cache = struct
  (* One decoded image plus its atlas uploads. LRU is tracked with a
     monotonically increasing [stamp] — eviction scans for the oldest
     stamp; caches hold few images so the linear scan is cheap. *)
  type stored = { entry : entry; frame : int }

  type slot = {
    img : image;
    nbytes : int;
    mutable stamp : int;
    mutable entries : (Lui_scene.Atlas.t * stored) list;
  }

  type t = {
    max_bytes : int;
    mutable nbytes : int;
    mutable clock : int;
    mutable frame : int;
    slots : (string, slot) Hashtbl.t;
  }

  let create ?(max_bytes = 64 * 1024 * 1024) () =
    { max_bytes; nbytes = 0; clock = 0; frame = 0; slots = Hashtbl.create 16 }

  let length c = Hashtbl.length c.slots
  let bytes_used c = c.nbytes

  let digest_of b = Digest.to_hex (Digest.bytes b)

  let mem c b = Hashtbl.mem c.slots (digest_of b)

  let evict c =
    (* Drop oldest-stamp slots until under budget; always keep at least
       the most recent slot so a single oversized image still caches. *)
    let rec loop () =
      if c.nbytes > c.max_bytes && Hashtbl.length c.slots > 1 then (
        let oldest =
          Hashtbl.fold
            (fun k s acc ->
              match acc with
              | None -> Some (k, s.stamp)
              | Some (_, st) -> if s.stamp < st then Some (k, s.stamp) else acc)
            c.slots None
        in
        match oldest with
        | None -> ()
        | Some (k, _) ->
          (match Hashtbl.find_opt c.slots k with
           | Some s -> c.nbytes <- c.nbytes - s.nbytes
           | None -> ());
          Hashtbl.remove c.slots k;
          loop ())
    in
    loop ()

  let slot_of c b =
    let d = digest_of b in
    match Hashtbl.find_opt c.slots d with
    | Some s -> c.clock <- c.clock + 1; s.stamp <- c.clock; Ok s
    | None ->
      (match decode b with
       | Error msg -> Error msg
       | Ok img ->
         c.clock <- c.clock + 1;
         let s = { img; nbytes = size_bytes img; stamp = c.clock;
                   entries = [] } in
         Hashtbl.replace c.slots img.idigest s;
         c.nbytes <- c.nbytes + s.nbytes;
         evict c;
         Ok s)

  let decode c b =
    match slot_of c b with
    | Ok s -> Ok s.img
    | Error msg -> Error msg

  (* An entry is live while the atlas generation it was written in is
     current and, for transient regions, the cache is still in the frame
     it was uploaded in (a renderer reset_transient frees the space). *)
  let live c (a : Lui_scene.Atlas.t) st =
    st.entry.egen = a.Lui_scene.Atlas.gen
    && (not st.entry.etransient || st.frame = c.frame)

  let atlas_entry ?(transient = true) c (a : Lui_scene.Atlas.t) b =
    match slot_of c b with
    | Error msg -> Error msg
    | Ok s ->
      s.entries <- List.filter (fun (a', st) -> live c a' st) s.entries;
      (match
         List.find_opt
           (fun (a', st) -> a' == a && st.entry.etransient = transient)
           s.entries
       with
       | Some (_, st) -> Ok st.entry
       | None ->
         (match upload ~transient a s.img with
          | Error msg -> Error msg
          | Ok e ->
            s.entries <- (a, { entry = e; frame = c.frame }) :: s.entries;
            Ok e))

  let begin_frame c = c.frame <- c.frame + 1

  let clear c =
    Hashtbl.reset c.slots;
    c.nbytes <- 0
end
