(* OCaml side of the native web view: the ABI is a flat nativeint
   handle plus a queued event channel, identical on every platform. *)

type rect = { x : float; y : float; w : float; h : float }

let rect x y w h = { x; y; w; h }

type host_window = nativeint

type source =
  | Url of string
  | Html of string * string
  | File of string
  | Empty

type opts = {
  source : source;
  user_agent : string;
  zoom : float;
  transparent : bool;
}

let opts ?(user_agent = "") ?(zoom = 1.0) ?(transparent = false) source =
  { source; user_agent; zoom; transparent }

type event =
  | Did_navigate of string
  | Did_commit of string
  | Did_finish of string
  | Load_error of string * string
  | Script_message of string

(* Event tags pushed by the stubs: 0 navigate, 1 commit, 2 finish,
   3 load error (url, msg), 4 async-eval result (token, json),
   5 script message. *)
type t = {
  native : nativeint;
  mutable destroyed : bool;
  mutable on_event : event -> unit;
  pending : (int, string -> unit) Hashtbl.t;
  mutable tok : int;
  mutable ua : string;
}

external c_backend_name : unit -> string = "lui_wv_backend_name"
external c_host_of_sdl : nativeint -> nativeint = "lui_wv_host_of_sdl"
external c_host_main : unit -> nativeint = "lui_wv_host_main"
external c_create : nativeint -> float -> float -> float -> float -> nativeint
  = "lui_wv_create_bc" "lui_wv_create"
external c_destroy : nativeint -> unit = "lui_wv_destroy"
external c_load_url : nativeint -> string -> unit = "lui_wv_load_url"
external c_load_html : nativeint -> string -> string -> unit
  = "lui_wv_load_html"
external c_load_file : nativeint -> string -> unit = "lui_wv_load_file"
external c_nav : nativeint -> int -> unit = "lui_wv_nav"
external c_can_nav : nativeint -> int = "lui_wv_can_nav"
external c_url : nativeint -> string = "lui_wv_url"
external c_is_loading : nativeint -> bool = "lui_wv_is_loading"
external c_eval : nativeint -> string -> unit = "lui_wv_eval"
external c_call_async : nativeint -> int -> string -> unit
  = "lui_wv_call_async"
external c_set_zoom : nativeint -> float -> unit = "lui_wv_set_zoom"
external c_zoom : nativeint -> float = "lui_wv_zoom"
external c_set_user_agent : nativeint -> string -> unit
  = "lui_wv_set_user_agent"
external c_user_agent : nativeint -> string = "lui_wv_user_agent"
external c_set_transparent : nativeint -> bool -> unit
  = "lui_wv_set_transparent"
external c_set_frame : nativeint -> float -> float -> float -> float -> unit
  = "lui_wv_set_frame_bc" "lui_wv_set_frame"
external c_frame : nativeint -> float * float * float * float
  = "lui_wv_frame"
external c_set_visible : nativeint -> bool -> unit = "lui_wv_set_visible"
external c_capture : nativeint -> string = "lui_wv_capture"
external c_next_event : nativeint -> (int * string * string) option
  = "lui_wv_next_event"
external c_pump : unit -> unit = "lui_wv_pump"

let backend_name = c_backend_name

let host_of_sdl_window p : host_window = c_host_of_sdl p

let host_main_window () : host_window = c_host_main ()

let host_of_native p : host_window = p

let check t = if t.destroyed then invalid_arg "lui_webview: destroyed"

let live t = (not t.destroyed) && not (Nativeint.equal t.native 0n)

let create host frame o =
  let native = c_create (host :> nativeint) frame.x frame.y frame.w frame.h in
  let t =
    { native;
      destroyed = false;
      on_event = ignore;
      pending = Hashtbl.create 8;
      tok = 0;
      ua = o.user_agent }
  in
  Gc.finalise
    (fun t -> if not t.destroyed then (try c_destroy t.native with _ -> ()))
    t;
  if o.user_agent <> "" then c_set_user_agent native o.user_agent;
  if o.zoom <> 1.0 then c_set_zoom native o.zoom;
  if o.transparent then c_set_transparent native true;
  (match o.source with
   | Url u -> c_load_url native u
   | Html (h, b) -> c_load_html native h b
   | File p -> c_load_file native p
   | Empty -> ());
  t

let destroy t =
  check t;
  t.destroyed <- true;
  c_destroy t.native

let load_url t u = check t; c_load_url t.native u
let load_html t ?(base_url = "") h = check t; c_load_html t.native h base_url
let load_file t p = check t; c_load_file t.native p
let reload t = check t; c_nav t.native 2
let stop t = check t; c_nav t.native 3
let go_back t = check t; c_nav t.native 0
let go_forward t = check t; c_nav t.native 1

let can_go_back t = live t && c_can_nav t.native land 1 <> 0

let can_go_forward t = live t && c_can_nav t.native land 2 <> 0

let url t = if live t then c_url t.native else ""

let is_loading t = live t && c_is_loading t.native
let eval t js = check t; c_eval t.native js

let call_async t js cb =
  check t;
  t.tok <- t.tok + 1;
  let tok = t.tok in
  Hashtbl.replace t.pending tok cb;
  (try c_call_async t.native tok js
   with e ->
     Hashtbl.remove t.pending tok;
     raise e)

let set_zoom t z = check t; c_set_zoom t.native z
let zoom t = if live t then c_zoom t.native else 1.0

let set_user_agent t u =
  check t;
  t.ua <- u;
  c_set_user_agent t.native u

let user_agent t =
  if live t then
    let u = c_user_agent t.native in
    if u = "" then t.ua else u
  else t.ua

let set_visible t v = check t; c_set_visible t.native v

let layout_webview t r =
  if live t then c_set_frame t.native r.x r.y r.w r.h

let set_frame = layout_webview

let frame t =
  if live t then
    let x, y, w, h = c_frame t.native in
    { x; y; w; h }
  else { x = 0.; y = 0.; w = 0.; h = 0. }

let capture_page t =
  if live t then
    match c_capture t.native with
    | "" -> None
    | s -> Some (Bytes.of_string s)
  else None

let set_on_event t f = t.on_event <- f

(* Decodes one queued triple; tag 4 resolves a pending call_async and
   produces no event. *)
let decode t (tag, a, b) =
  match tag with
  | 0 -> Some (Did_navigate a)
  | 1 -> Some (Did_commit a)
  | 2 -> Some (Did_finish a)
  | 3 -> Some (Load_error (a, b))
  | 4 ->
    (match int_of_string_opt a with
     | Some tok ->
       (match Hashtbl.find_opt t.pending tok with
        | Some cb ->
          Hashtbl.remove t.pending tok;
          (try cb b with _ -> ())
        | None -> ())
     | None -> ());
    None
  | 5 -> Some (Script_message a)
  | _ -> None

let drain t =
  let rec loop acc =
    match (if live t then c_next_event t.native else None) with
    | None -> List.rev acc
    | Some triple ->
      (match decode t triple with
       | Some ev ->
         (try t.on_event ev with _ -> ());
         loop (ev :: acc)
       | None -> loop acc)
  in
  loop []

let pump = c_pump
