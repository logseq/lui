(* Audio playback and video frame decode — see lui_media.mli for the
   contract and per-platform coverage. The C side decodes to
   interleaved float32 PCM and premultiplied RGBA frames; everything
   else (clocks, frame scheduling, callbacks, the plugin service)
   lives here. *)

type player_h
type video_h

external c_audio_available : unit -> bool = "lui_media_audio_available"
external c_decode_available : unit -> bool = "lui_media_decode_available"
external c_video_available : unit -> bool = "lui_media_video_available"

external c_decode :
  string -> bool -> bool * string * int * int * int * string
  = "lui_media_decode"
(* src is_data -> ok err frames rate channels pcm_f32le *)

external c_player_create : unit -> player_h = "lui_media_player_create"
external c_player_load : player_h -> string -> bool -> string
  = "lui_media_player_load"
external c_player_play : player_h -> unit = "lui_media_player_play"
external c_player_pause : player_h -> unit = "lui_media_player_pause"
external c_player_stop : player_h -> unit = "lui_media_player_stop"
external c_player_unload : player_h -> unit = "lui_media_player_unload"
external c_player_seek : player_h -> float -> unit = "lui_media_player_seek"
external c_player_set_volume : player_h -> float -> unit
  = "lui_media_player_set_volume"
external c_player_set_loop : player_h -> bool -> unit
  = "lui_media_player_set_loop"
external c_player_info : player_h -> float * float * int * float * int
  = "lui_media_player_info" (* duration position state volume loop *)
external c_player_take_ended : player_h -> bool
  = "lui_media_player_take_ended"

external c_video_open : string -> video_h = "lui_media_video_open"
external c_video_close : video_h -> unit = "lui_media_video_close"
external c_video_duration : video_h -> float = "lui_media_video_duration"
external c_video_size : video_h -> int * int = "lui_media_video_size"
external c_video_seek : video_h -> float -> unit = "lui_media_video_seek"
external c_video_next : video_h -> bool * float * int * int * string * string
  = "lui_media_video_next"
(* -> found pts w h rgba_bytes err *)

external c_write_test_video : string -> int -> int -> float -> bool * string
  = "lui_media_write_test_video"

type player_state = Stopped | Playing | Paused | Ended

type player = {
  ph : player_h;
  pid : int;
  mutable ecb : (player -> unit) option;
}

type video = {
  vh : video_h;
  vid : int;
  vdur : float;
  mutable vclosed : bool;
  mutable vstate : player_state;
  mutable base : float;   (* position at the last clock change *)
  mutable t0 : float;     (* wall clock of that change *)
  mutable rate_f : float;
  mutable vol_f : float;
  mutable img : Lui_scene.image option;
  mutable cur_pts : float;
  mutable pend : (float * string) option; (* next frame, decoded ahead *)
  mutable pixw : int;
  mutable pixh : int;
  mutable eof : bool;
  mutable vecb : (video -> unit) option;
  mutable fresh : bool;
  mutable err : string;
}

let audio_available = c_audio_available
let decode_available = c_decode_available
let video_available = c_video_available

let state_of_int = function
  | 1 -> Playing
  | 2 -> Paused
  | 3 -> Ended
  | _ -> Stopped

let string_of_state = function
  | Stopped -> "stopped"
  | Playing -> "playing"
  | Paused -> "paused"
  | Ended -> "ended"

(* Handle registry: shared by [poll_events] and the plugin service. *)
let next_id = ref 0
let gen_id () = incr next_id; !next_id
let players : (int, player) Hashtbl.t = Hashtbl.create 8
let videos : (int, video) Hashtbl.t = Hashtbl.create 8
let events : (string * int * string) Queue.t = Queue.create ()
let pending : (unit -> unit) Queue.t = Queue.create ()

let now () = Unix.gettimeofday ()

let video_position v =
  let pos =
    if v.vstate = Playing then v.base +. ((now ()) -. v.t0) *. v.rate_f
    else v.base
  in
  Float.min (Float.max pos 0.) v.vdur

let commit_pend v =
  match v.pend with
  | None -> ()
  | Some (pts, bytes) ->
    v.pend <- None;
    let pix = Bytes.of_string bytes in
    (match v.img with
     | Some i
       when i.Lui_scene.iw = v.pixw && i.Lui_scene.ih = v.pixh ->
       Bytes.blit pix 0 i.Lui_scene.ipix 0 (Bytes.length i.Lui_scene.ipix);
       Lui_scene.image_changed i
     | _ -> v.img <- Some (Lui_scene.new_image ~w:v.pixw ~h:v.pixh pix));
    v.cur_pts <- pts;
    v.fresh <- true

let decode_next v =
  let found, pts, w, h, bytes, err = c_video_next v.vh in
  v.err <- err;
  if found then begin
    v.pend <- Some (pts, bytes);
    v.pixw <- w;
    v.pixh <- h
  end
  else v.eof <- true

let check_ended v =
  if v.eof && v.vstate = Playing then begin
    v.vstate <- Ended;
    Queue.add ("video", v.vid, "ended") events;
    match v.vecb with
    | Some f -> Queue.add (fun () -> f v) pending
    | None -> ()
  end

(* Decode one frame into [pend] if empty, then commit it so a fresh
   [img] always exists right after open/seek, then decode one ahead. *)
let prime v =
  if v.pend = None && not v.eof then decode_next v;
  commit_pend v;
  if v.pend = None && not v.eof then decode_next v

(* Advance the decoder until the pending frame is ahead of position. *)
let pull v =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  if v.img = None then prime v;
  let pos = video_position v in
  let rec go () =
    match v.pend with
    | Some (pts, _) when pts <= pos +. 0.0005 ->
      commit_pend v;
      if not v.eof then decode_next v;
      go ()
    | _ -> ()
  in
  go ();
  check_ended v;
  v

let poll_events () =
  (* Players report completion through the C-side flag; videos reach
     Ended inside [pull], which enqueues the callback. Playing videos
     are pulled here too so the plugin's event stream advances without
     a repaint loop. *)
  Hashtbl.iter
    (fun _ p ->
      if c_player_take_ended p.ph then begin
        Queue.add ("audio", p.pid, "ended") events;
        match p.ecb with
        | Some f -> Queue.add (fun () -> f p) pending
        | None -> ()
      end)
    players;
  Hashtbl.iter
    (fun _ v ->
      if (not v.vclosed) && v.vstate = Playing then ignore (pull v))
    videos;
  while not (Queue.is_empty pending) do
    let f = Queue.pop pending in
    (try f () with _ -> ())
  done

(* ------------------------------------------------------------------ *)
(* Audio                                                               *)

let player_create () =
  try
    let p = { ph = c_player_create (); pid = gen_id (); ecb = None } in
    Hashtbl.add players p.pid p;
    Ok p
  with Failure e -> Error e

let load p src =
  match c_player_load p.ph src false with
  | "" -> Ok ()
  | e -> Error e

let load_bytes p data =
  match c_player_load p.ph data true with
  | "" -> Ok ()
  | e -> Error e

let play p = c_player_play p.ph
let pause p = c_player_pause p.ph
let stop p = c_player_stop p.ph
let unload p = c_player_unload p.ph
let seek p t = c_player_seek p.ph (Float.max 0. t)
let set_volume p v = c_player_set_volume p.ph (Float.min (Float.max v 0.) 1.)
let set_loop p b = c_player_set_loop p.ph b

let info p = c_player_info p.ph
let duration p = let d, _, _, _, _ = info p in d
let volume p = let _, _, _, v, _ = info p in v
let loops p = let _, _, _, _, l = info p in l <> 0
let position p =
  poll_events ();
  let _, pos, _, _, _ = info p in
  pos
let status p = let _, _, s, _, _ = info p in state_of_int s

let on_ended p f = p.ecb <- Some f

type pcm = {
  pcm_rate : int;
  pcm_channels : int;
  pcm_frames : int;
  pcm_data : Bytes.t;
}

let pcm_of_result (ok, err, frames, rate, ch, data) =
  if not ok then Error err
  else
    Ok
      { pcm_rate = rate; pcm_channels = ch; pcm_frames = frames;
        pcm_data = Bytes.of_string data }

let decode_of f arg =
  (* Stubs raise on platforms without a media backend; the API contract
     is graceful errors, so translate the raise into [Error]. *)
  try pcm_of_result (f arg) with Failure m -> Error m

let decode path = decode_of (fun b -> c_decode b false) path
let decode_bytes b = decode_of (fun b -> c_decode b true) b

(* ------------------------------------------------------------------ *)
(* Video                                                               *)

let video_open path =
  try
    let vh = c_video_open path in
    let v =
      { vh; vid = gen_id (); vdur = c_video_duration vh;
        vclosed = false; vstate = Stopped; base = 0.; t0 = now ();
        rate_f = 1.; vol_f = 1.; img = None; cur_pts = 0.; pend = None;
        pixw = 0; pixh = 0; eof = false; vecb = None; fresh = false;
        err = "" }
    in
    ignore (prime v);
    Hashtbl.add videos v.vid v;
    Ok v
  with Failure e -> Error e

let video_close v =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  v.vclosed <- true;
  v.vstate <- Stopped;
  c_video_close v.vh;
  Hashtbl.remove videos v.vid

let video_play v =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  (match v.vstate with
   | Ended ->
     v.eof <- false;
     v.pend <- None;
     c_video_seek v.vh 0.;
     ignore (prime v);
     v.base <- 0.
   | _ -> ());
  v.t0 <- now ();
  v.vstate <- Playing

let video_pause v =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  if v.vstate = Playing then begin
    v.base <- video_position v;
    v.vstate <- Paused
  end

let video_seek v t =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  let t = Float.min (Float.max t 0.) v.vdur in
  v.base <- t;
  v.t0 <- now ();
  v.eof <- false;
  v.pend <- None;
  if v.vstate = Ended then v.vstate <- Stopped;
  c_video_seek v.vh t;
  ignore (prime v)

let video_set_rate v r =
  if v.vclosed then invalid_arg "Lui_media: video closed";
  let r = Float.min (Float.max r 0.01) 16. in
  if v.vstate = Playing then begin
    v.base <- video_position v;
    v.t0 <- now ()
  end;
  v.rate_f <- r

let video_rate v = v.rate_f
let video_set_volume v x = v.vol_f <- Float.min (Float.max x 0.) 1.
let video_volume v = v.vol_f
let video_duration v = v.vdur
let video_status v = v.vstate
let video_natural_size v = c_video_size v.vh
let video_on_ended v f = v.vecb <- Some f
let video_has_new_frame v = v.fresh
let video_frame_pts v = v.cur_pts

let current_frame v =
  ignore (pull v);
  poll_events ();
  if v.err <> "" then Some (Error v.err)
  else Option.map (fun i -> Ok i) v.img

(* ------------------------------------------------------------------ *)
(* Node adapter                                                        *)

type fit = Contain | Cover | Fill

let placeholder_img =
  lazy (Lui_scene.new_image ~w:1 ~h:1 (Bytes.make 4 '\000'))

let video_node_at ?(x = 0.) ?(y = 0.) ?(fit = Contain) ?(opacity = 1.)
    ~w ~h v =
  ignore (pull v);
  let img =
    match v.img with Some i -> i | None -> Lazy.force placeholder_img
  in
  let (dx, dy, dw, dh) =
    match fit with
    | Fill -> (x, y, w, h)
    | Contain | Cover ->
      let sw = float img.Lui_scene.iw and sh = float img.Lui_scene.ih in
      if sw <= 0. || sh <= 0. || w <= 0. || h <= 0. then (x, y, 0., 0.)
      else
        let k =
          match fit with
          | Contain -> Float.min (w /. sw) (h /. sh)
          | _ -> Float.max (w /. sw) (h /. sh)
        in
        let dw = sw *. k and dh = sh *. k in
        (x +. ((w -. dw) /. 2.), y +. ((h -. dh) /. 2.), dw, dh)
  in
  Lui_scene.Image
    { Lui_scene.irect2 = Lui_scene.rect dx dy dw dh;
      iradii = (0., 0., 0., 0.); icontinuous = false; iimage = img;
      isrc =
        Lui_scene.rect 0. 0. (float img.Lui_scene.iw)
          (float img.Lui_scene.ih);
      igrayscale = false; iopacity = opacity }

let video_node v w h = video_node_at ~w ~h v

(* ------------------------------------------------------------------ *)
(* App wiring                                                          *)

type state = { vids : video list ref }

let state_create () = { vids = ref [] }
let state_attach s v =
  if not (List.exists (fun x -> x == v) !(s.vids)) then
    s.vids := v :: !(s.vids)
let state_detach s v =
  s.vids := List.filter (fun x -> not (x == v)) !(s.vids)

let want_frame s =
  List.exists (fun v -> v.fresh || v.vstate = Playing) !(s.vids)

let frame_done s =
  List.iter (fun v -> v.fresh <- false) !(s.vids)

(* ------------------------------------------------------------------ *)
(* Plugin service                                                      *)

let b64_decode s =
  let tbl = Array.make 256 (-1) in
  String.iteri
    (fun i c -> tbl.(Char.code c) <- i)
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let n = String.length s in
  let b = Buffer.create (n / 4 * 3) in
  let acc = ref 0 and bits = ref 0 and ok = ref true in
  String.iter
    (fun c ->
      if c = '=' then ()
      else
        match tbl.(Char.code c) with
        | -1 -> ok := false
        | v ->
          acc := (!acc lsl 6) lor v;
          bits := !bits + 6;
          if !bits >= 8 then begin
            bits := !bits - 8;
            Buffer.add_char b (Char.chr ((!acc lsr !bits) land 0xff))
          end)
    s;
  if !ok then Ok (Buffer.contents b) else Error "invalid base64"

let jmem name j = Yojson.Safe.Util.member name j

let jint name j =
  match jmem name j with
  | `Int i -> i
  | _ -> invalid_arg ("missing \"" ^ name ^ "\"")

let jfloat ?(d = 0.) name j =
  match jmem name j with
  | `Int i -> float i
  | `Float f -> f
  | `Intlit s | `String s -> (try float_of_string s with _ -> d)
  | _ -> d

let jstr name j =
  match jmem name j with
  | `String s -> s
  | _ -> invalid_arg ("missing \"" ^ name ^ "\"")

let jbool ?(d = false) name j =
  match jmem name j with `Bool b -> b | _ -> d

let get_player j =
  match Hashtbl.find_opt players (jint "player" j) with
  | Some p -> p
  | None -> invalid_arg "no such player"

let get_video j =
  match Hashtbl.find_opt videos (jint "video" j) with
  | Some v -> v
  | None -> invalid_arg "no such video"

let with_json payload f =
  match (try Ok (Yojson.Safe.from_string payload)
         with Yojson.Json_error e -> Error ("invalid JSON: " ^ e)) with
  | Error _ as e -> e
  | Ok j ->
    (try Ok (Yojson.Safe.to_string (f j)) with
     | Invalid_argument e -> Error e
     | Failure e -> Error e)

let audio_open j =
  match jmem "data_base64" j with
  | `String b64 ->
    (match b64_decode b64 with
     | Error e -> Error e
     | Ok data ->
       (match player_create () with
        | Error e -> Error e
        | Ok p ->
          (match load_bytes p data with
           | Error e -> Error e
           | Ok () -> Ok p)))
  | _ ->
    (match player_create () with
     | Error e -> Error e
     | Ok p ->
       (match load p (jstr "path" j) with
        | Error e -> Error e
        | Ok () -> Ok p))

let plugin =
  let method_ name f = (name, fun payload -> with_json payload f) in
  Lui_plugin.v "media"
    [ method_ "audio.open" (fun j ->
        let p =
          match audio_open j with
          | Ok p -> p
          | Error e -> invalid_arg e
        in
          if jmem "volume" j <> `Null then
            set_volume p (jfloat ~d:1. "volume" j);
          if jbool "loop" j then set_loop p true;
          `Assoc [ ("player", `Int p.pid) ]);
      method_ "audio.play" (fun j -> play (get_player j); `Assoc []);
      method_ "audio.pause" (fun j -> pause (get_player j); `Assoc []);
      method_ "audio.stop" (fun j -> stop (get_player j); `Assoc []);
      method_ "audio.unload" (fun j -> unload (get_player j); `Assoc []);
      method_ "audio.close" (fun j ->
        let p = get_player j in
        unload p;
        Hashtbl.remove players p.pid;
        `Assoc []);
      method_ "audio.seek" (fun j ->
        seek (get_player j) (jfloat "position" j); `Assoc []);
      method_ "audio.volume" (fun j ->
        set_volume (get_player j) (jfloat ~d:1. "volume" j); `Assoc []);
      method_ "audio.loop" (fun j ->
        set_loop (get_player j) (jbool "loop" j); `Assoc []);
      method_ "audio.status" (fun j ->
        let p = get_player j in
        poll_events ();
        `Assoc
          [ ("state", `String (string_of_state (status p)));
            ("duration", `Float (duration p));
            ("position", `Float (position p));
            ("volume", `Float (volume p));
            ("loop", `Bool (loops p)) ]);
      method_ "video.open" (fun j ->
        match video_open (jstr "path" j) with
        | Error e -> invalid_arg e
        | Ok v -> `Assoc [ ("video", `Int v.vid) ]);
      method_ "video.play" (fun j -> video_play (get_video j); `Assoc []);
      method_ "video.pause" (fun j -> video_pause (get_video j); `Assoc []);
      method_ "video.close" (fun j -> video_close (get_video j); `Assoc []);
      method_ "video.seek" (fun j ->
        video_seek (get_video j) (jfloat "position" j); `Assoc []);
      method_ "video.rate" (fun j ->
        video_set_rate (get_video j) (jfloat ~d:1. "rate" j); `Assoc []);
      method_ "video.volume" (fun j ->
        video_set_volume (get_video j) (jfloat ~d:1. "volume" j); `Assoc []);
      method_ "video.status" (fun j ->
        let v = get_video j in
        poll_events ();
        let w, h = video_natural_size v in
        `Assoc
          [ ("state", `String (string_of_state (video_status v)));
            ("duration", `Float (video_duration v));
            ("position", `Float (video_position v));
            ("rate", `Float (video_rate v));
            ("volume", `Float (video_volume v));
            ("width", `Int w); ("height", `Int h) ]);
      method_ "video.frame" (fun j ->
        let v = get_video j in
        match current_frame v with
        | Some (Error e) -> invalid_arg e
        | _ ->
          let w, h = video_natural_size v in
          `Assoc
            [ ("pts", `Float (video_frame_pts v));
              ("width", `Int w); ("height", `Int h) ]);
      method_ "events" (fun _j ->
        poll_events ();
        let evs = Queue.fold (fun acc e -> e :: acc) [] events in
        Queue.clear events;
        `Assoc
          [ ( "events",
              `List
                (List.map
                   (fun (kind, id, ev) ->
                     `Assoc
                       [ ("kind", `String kind); ("id", `Int id);
                         ("event", `String ev) ])
                   evs) ) ]) ]

let register_plugin () = Lui_plugin.use [ plugin ]

module Testing = struct
  let write_test_video path ~w ~h ~secs =
    match c_write_test_video path w h secs with
    | true, _ -> Ok ()
    | false, e -> Error (if e = "" then "write_test_video failed" else e)
end
