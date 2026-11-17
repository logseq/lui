(* Audio playback and video frame decode for the native backend.

   Two handle types:

   - [player]: a decoded-in-memory audio player. [load]/[load_bytes]
     decode the whole file to float PCM up front, so [seek], [loop]
     and [position] are exact and cheap; several players mix onto one
     shared output (short sounds are the design target).
   - [video]: a pull-based video decoder. Each repaint asks
     {!current_frame} for the frame covering the playback position;
     the decoder advances forward only as far as needed, so cost stays
     proportional to frames actually shown.

   Platform coverage (every entry point exists everywhere):

   - macOS: real implementation. Audio decodes through ExtAudioFile /
     AudioFile and plays through a shared AVAudioEngine; video decodes
     through AVAssetReader into premultiplied RGBA frames.
   - Linux: audio decode via a runtime-resolved libsndfile with an
     [ffmpeg] subprocess fallback; playback via a runtime-resolved
     SDL2 device queue, with an [ffplay] subprocess fallback that only
     supports play/stop. Video is not implemented there.
   - Windows and everything else: the availability flags are [false]
     and every constructor reports an error; nothing else needs
     conditional code on the caller side.

   Video frames decode to the pixel convention of {!Lui_scene.image}:
   premultiplied RGBA8, four bytes per pixel, rows tightly packed — a
   frame can be handed to an [Image] op without conversion. The
   platform decoder delivers frames already converted to sRGB (BT.709
   sources are mapped by the decompressor).

   Callbacks: [on_ended]/[video_on_ended] run on the OCaml thread
   inside {!poll_events}, which is also called implicitly by
   [position], [video_position] and [current_frame] — a UI loop that
   repaints or polls position gets end events without extra plumbing. *)

type player_state =
  | Stopped
  | Playing
  | Paused
  | Ended

val audio_available : unit -> bool
(** Whether audio decode and playback are usable on this platform. *)

val decode_available : unit -> bool
(** Whether {!decode}/{!decode_bytes} can run on this platform.
    Subset of {!audio_available}; kept separate so tests and samplers
    can use the decoder where playback is missing. *)

val video_available : unit -> bool
(** Whether {!video_open} can run on this platform. *)

(* ------------------------------------------------------------------ *)
(* Audio                                                               *)

type player

val player_create : unit -> (player, string) result
(** A fresh, empty player. Fails where audio output is unsupported. *)

val load : player -> string -> (unit, string) result
(** Decode [path] into the player, replacing any previous content. *)

val load_bytes : player -> string -> (unit, string) result
(** Same as {!load} but takes the encoded file's bytes. *)

val play : player -> unit
(** Start or resume playback. From [Ended], restarts at position 0. *)

val pause : player -> unit
val stop : player -> unit
(** Pause / stop (stop also rewinds to position 0). *)

val unload : player -> unit
(** Drop the decoded buffer; the player may be [load]ed again. *)

val seek : player -> float -> unit
(** Move to [t] seconds, clamped to \[0, duration]. Works in any
    state; a playing player keeps playing, a paused one re-arms. *)

val set_volume : player -> float -> unit
val volume : player -> float
(** Output gain, clamped to \[0, 1]. *)

val set_loop : player -> bool -> unit
val loops : player -> bool
(** Loop the loaded content. *)

val duration : player -> float
(** Loaded length in seconds; 0 when empty. *)

val position : player -> float
(** Playback position in seconds. *)

val status : player -> player_state
val on_ended : player -> (player -> unit) -> unit
(** [on_ended p f] runs [f] once each time [p] finishes a non-looping
    playback, from {!poll_events}. Only one callback is kept — a
    second call replaces the first. *)

(* Decoded PCM: interleaved float32 little-endian samples. *)
type pcm = {
  pcm_rate : int;
  pcm_channels : int;
  pcm_frames : int;
  pcm_data : Bytes.t;  (** [4 * channels * frames] bytes *)
}

val decode : string -> (pcm, string) result
(** [decode path] decodes a whole audio file to PCM without creating
    a player. *)

val decode_bytes : string -> (pcm, string) result
(** Same as {!decode} from encoded bytes. *)

(* ------------------------------------------------------------------ *)
(* Video                                                               *)

type video

val video_open : string -> (video, string) result
(** Open a local file path (a [file://] URL also works). Decodes the
    first frame eagerly so {!video_natural_size} and the poster frame
    are ready immediately. *)

val video_close : video -> unit
(** Release the decoder. The handle becomes invalid; further calls
    raise [Invalid_argument]. *)

val video_play : video -> unit
val video_pause : video -> unit
val video_seek : video -> float -> unit
(** Seek to [t] seconds (clamped). The next pull decodes from there. *)

val video_set_rate : video -> float -> unit
val video_rate : video -> float
(** Playback speed multiplier, clamped to \[0.01, 16]. *)

val video_set_volume : video -> float -> unit
val video_volume : video -> float
(** Volume for the video's audio channel. Video sound is not rendered
    at v1 — the value is stored and reported so API users can wire it
    ahead of time. *)

val video_duration : video -> float
val video_position : video -> float
val video_status : video -> player_state
val video_natural_size : video -> int * int
(** Decoded frame size (pixels), before any rotation metadata — the
    frames are delivered unrotated at v1. *)

val video_on_ended : video -> (video -> unit) -> unit
val video_has_new_frame : video -> bool
(** Whether a new frame was committed since the last {!frame_done}
    on a {!state} this video is attached to — the repaint hint. *)

val video_frame_pts : video -> float
(** Presentation timestamp (seconds) of the frame {!current_frame}
    last committed. *)

val current_frame : video -> (Lui_scene.image, string) result option
(** The decoded frame covering the current position.

    - [None]: no frame yet (empty stream, or not primed).
    - [Some (Ok img)]: the current frame. [img] is stable across
      calls — pixels are rewritten in place and [iversion] bumped, so
      an [Image] op drawn earlier keeps working and renderers notice
      the update.
    - [Some (Error e)]: the decode failed. *)

(* ------------------------------------------------------------------ *)
(* Node adapter                                                        *)

type fit = Contain | Cover | Fill

val video_node : video -> float -> float -> Lui_scene.op
(** [video_node v w h] is [video_node_at ~w ~h v] at (0,0). *)

val video_node_at :
  ?x:float -> ?y:float -> ?fit:fit -> ?opacity:float ->
  w:float -> h:float -> video -> Lui_scene.op
(** A scene [Image] op drawing the video's current frame into the
    [w]x[h] rect at ([x], [y]), fitted per [fit] (default [Contain]).
    When no frame is decoded yet it draws a transparent placeholder
    so the op list shape is stable. *)

(* ------------------------------------------------------------------ *)
(* App wiring                                                          *)

type state
(** Tracks videos an app's LUI tree is showing, for repaint hints. *)

val state_create : unit -> state
val state_attach : state -> video -> unit
val state_detach : state -> video -> unit

val want_frame : state -> bool
(** True when the app should schedule another repaint: any attached
    video is playing, or produced a new frame since {!frame_done}. *)

val frame_done : state -> unit
(** Call after repainting: clears the per-video new-frame flags. *)

val poll_events : unit -> unit
(** Deliver pending [on_ended] callbacks. Runs every registered
    player's completion check; call it from the frame loop (the
    position/frame accessors call it too). *)

(* ------------------------------------------------------------------ *)
(* Plugin service                                                      *)

val plugin : Lui_plugin.t
(** The ["media"] plugin — service name ["plugin:media"]. Methods take
    a JSON object and return a JSON object:

    - ["audio.open"] [{ "path" } | { "data_base64" }] -> [{ "player": id }]
    - ["audio.play"|"pause"|"stop"|"close"|"unload"] [{ "player": id }]
    - ["audio.seek"] [{ "player": id, "position": seconds }]
    - ["audio.volume"] [{ "player": id, "volume": 0..1 }]
    - ["audio.loop"] [{ "player": id, "loop": bool }]
    - ["audio.status"] [{ "player": id }] ->
      [{ "state","duration","position","volume","loop" }]
    - ["video.open"] [{ "path" }] -> [{ "video": id }]
    - ["video.play"|"pause"|"close"] [{ "video": id }]
    - ["video.seek"] [{ "video": id, "position": seconds }]
    - ["video.rate"] [{ "video": id, "rate": x }]
    - ["video.volume"] [{ "video": id, "volume": 0..1 }]
    - ["video.status"] [{ "video": id }] ->
      [{ "state","duration","position","rate","volume","width","height" }]
    - ["video.frame"] [{ "video": id }] ->
      [{ "pts","width","height" }] (pulls the current frame; pixels
      stay native-side)
    - ["events"] [{}] -> [{ "events": [{"kind","id","event"}, ...] }]
      (drains pending events; ends are reported as ["ended"]). *)

val register_plugin : unit -> (unit, string) result
(** [Lui_plugin.use [plugin]] — bind the service. *)

(* ------------------------------------------------------------------ *)
(* Test helpers                                                        *)

module Testing : sig
  val write_test_video : string -> w:int -> h:int -> secs:float ->
    (unit, string) result
  (** Write a deterministic H.264 MP4 at [path]: eight vertical color
      bars (red, green, blue, white, black, yellow, cyan, magenta —
      tagged BT.709, full range) at 30 fps for [secs] seconds, plus a
      moving white block so successive frames differ. Implemented via
      AVAssetWriter on macOS; unavailable platforms return an error. *)
end
