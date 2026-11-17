(* Terminal widget facade: VT parser + grid + renderer + PTY + input.
   No plugin registry exists yet, so this is a plain library API —
   a host creates a [t], feeds pty output with [feed], paints with
   [view] and routes input events through [handle_input]. *)

module Vt = Terminal_vt
module G = Terminal_grid
module A = Terminal_attrs
module P = Terminal_pty
module K = Terminal_keys
module L = Terminal_links
module R = Terminal_render
open Lui_window.Input

type t = {
  vt : Vt.t;
  render : Lui_text.font R.t;
  mutable pty : P.t option;
  write_buf : bytes;
  mutable pending : string list;  (* bytes queued for the pty *)
}

let create ?(cols = 80) ?(rows = 24) ?(max_scrollback = 10_000)
    ?(font_size = 13.) ?(scale = 2.) ?(theme = A.dark_theme ())
    ?(families = [ "monospace" ]) () =
  let vt = Vt.create ~cols ~rows ~max_scrollback () in
  let render =
    R.create R.engine_of_lui_text ~families ~size:font_size ~scale
      ~theme ()
  in
  { vt; render; pty = None; write_buf = Bytes.create 65536;
    pending = [] }

let grid t = Vt.grid t.vt
let renderer t = t.render

(* Apply an action the parser raised. *)
let act t = function
  | Vt.Reply s -> t.pending <- s :: t.pending
  | _ -> ()

let feed t s =
  List.iter (act t) (Vt.feed_string t.vt s)

let feed_bytes t b off len =
  feed t (Bytes.sub_string b off len)

(* ---- pty --------------------------------------------------------- *)

let spawn t ~argv ~env ~cwd =
  let g = Vt.grid t.vt in
  t.pty <- Some (P.spawn ~argv ~env ~cwd ~cols:(G.cols g) ~rows:(G.rows g))

let close_pty t =
  (match t.pty with Some p -> P.close p | None -> ());
  t.pty <- None

let pty_alive t =
  match t.pty with Some p -> P.alive p | None -> false

let pty_poll t =
  match t.pty with Some p -> P.poll p | None -> Some (-1)

(* Drain queued input + read available output; call once per frame.
   Returns the actions raised by newly-fed output. *)
let pump t =
  match t.pty with
  | None -> []
  | Some p ->
    List.iter (fun s -> ignore (P.write_string p s))
      (List.rev t.pending);
    t.pending <- [];
    let acts = ref [] in
    (try
       while true do
         let n = P.read p t.write_buf 0 (Bytes.length t.write_buf) in
         if n <= 0 then raise Exit;
         acts := !acts @ Vt.feed t.vt
                    (Bytes.unsafe_to_string t.write_buf) 0 n
       done
     with Exit -> ());
    List.iter (act t) !acts;
    !acts

let write t s = t.pending <- s :: t.pending

let resize t ~cols ~rows =
  G.resize (Vt.grid t.vt) ~cols ~rows;
  (match t.pty with Some p -> P.resize p ~cols ~rows | None -> ())

(* ---- view --------------------------------------------------------- *)

let cell_w t = R.cell_w t.render
let cell_h t = R.cell_h t.render

(* Paint the current grid into [scene]; [~blink_on] is the caller's
   blink phase for cursor/blinking text. *)
let view t ?(blink_on = true) scene ~w ~h =
  R.render ~blink_on t.render (Vt.grid t.vt) scene ~w ~h

let cols_for t w = max 1 (w / max 1 (R.cell_w t.render))
let rows_for t h = max 1 (h / max 1 (R.cell_h t.render))

let resize_pixels t ~w ~h = resize t ~cols:(cols_for t w) ~rows:(rows_for t h)

(* ---- input -------------------------------------------------------- *)

let enqueue t s = if s <> "" then t.pending <- s :: t.pending

(* Pixel position -> (viewport row, col). *)
let cell_of t ~x ~y =
  (int_of_float (y /. float (R.cell_h t.render)),
   int_of_float (x /. float (R.cell_w t.render)))

let selection_text t = G.sel_text (Vt.grid t.vt)
let clear_selection t = G.sel_clear (Vt.grid t.vt)

(* The doc row under a viewport row, for selection anchoring. *)
let doc_id_of t vy =
  let g = Vt.grid t.vt in
  match G.shown_row g vy with
  | Some (i, r) -> Some (i, r.G.id)
  | None -> None

let mouse_sel t vy vx kind =
  match doc_id_of t vy with
  | Some (_, id) -> G.sel_start (Vt.grid t.vt) ~id ~col:vx kind
  | None -> ()

let sel_extend t vy vx =
  match doc_id_of t vy with
  | Some (_, id) -> G.sel_extend (Vt.grid t.vt) ~id ~col:vx
  | None -> ()

let scroll_view t d = G.scroll_view (Vt.grid t.vt) d
let hover_link t id = R.set_hover_link t.render id
let link_uri t id = Vt.link_uri t.vt id
let link_at t ~row ~col = L.at (Vt.grid t.vt) ~row ~col

(* Route one host input event; returns true when it was consumed. *)
let handle_input t ev =
  let g = Vt.grid t.vt in
  match ev with
  | Key_down (k, m, repeat) ->
    if repeat then true
    else
      (match K.key_bytes ~appcursor:(G.mode_appcursor g) k m with
       | Some s -> enqueue t s; true
       | None -> false)
  | Text_input s -> enqueue t (K.text_bytes s); true
  | Paste s -> enqueue t (K.paste_bytes ~bracketed:(G.mode_bracketed g) s);
    true
  | Button_down (_x, _y, _b, _clicks, _m) -> false (* host handles *)
  | Wheel (_, dy) | Wheel_mods (_, dy, _) ->
    if G.mode_altscroll g then begin
      let arrow = if dy < 0. then "A" else "B" in
      for _ = 1 to 3 do enqueue t ("\x1bO" ^ arrow) done
    end else
      G.scroll_view g (int_of_float (-.dy));
    true
  | Move (x, y) ->
    (* update hover-link underline *)
    let vy, vx = cell_of t ~x ~y in
    (match G.shown_row g vy with
     | Some (_, r) ->
       let lid =
         if vx >= 0 && vx < Array.length r.G.cells
         then r.G.cells.(min vx (Array.length r.G.cells - 1)).G.link else 0
       in
       if lid <> R.hover_link t.render then
         R.set_hover_link t.render lid
     | None -> ());
    false
  | _ -> false

let has_selection t = G.has_selection (Vt.grid t.vt)

(* ---- plugin service ------------------------------------------------
   The ["plugin:terminal"] service of the {!Lui_plugin} registry:
   JSON-in/JSON-out terminals keyed by integer id.

   Methods (payloads are JSON objects):

     spawn {"argv"?: string[], "cwd"?: string, "env"?: string[],
            "cols"?: int, "rows"?: int, "max_scrollback"?: int,
            "font_size"?: number, "scale"?: number,
            "families"?: string[]}  ->  {"id": n}
           Absent [argv] defaults to the user's shell ([$SHELL] or
           [/bin/sh]).  [env] is honoured on Windows only; unix
           children inherit the process environment.  An empty [cwd]
           inherits the host's working directory.
     write {"id": n, "data": string} | {"id": n, "data64": base64}
           ->  {}
     read_events {"id": n}
           ->  {"alive": bool, "exit": int|null, "actions": [a],
                "cursor": {"x": n, "y": n, "visible": bool,
                           "style": int, "blink": bool},
                "cols": n, "rows": n, "scrollback": n}
           Pumps the terminal: flushes queued input, drains child
           output into the grid, and reports the raised actions.
     resize {"id": n, "cols": int, "rows": int}  ->  {}
     close  {"id": n}  ->  {}                                    *)

module Service = struct
  open Yojson.Safe.Util

  let terms : (int, t) Hashtbl.t = Hashtbl.create 4
  let next = ref 0

  let find j =
    match member "id" j with
    | `Int n -> (
      match Hashtbl.find_opt terms n with
      | Some t -> Ok t
      | None -> Error (Printf.sprintf "terminal: no terminal %d" n))
    | _ -> Error "terminal: \"id\" must be an integer"

  let member_str j k =
    match member k j with `String s -> Some s | _ -> None

  let member_strs j k =
    match member k j with
    | `List l -> List.filter_map (function `String s -> Some s | _ -> None) l
    | _ -> []

  let member_int j k ~default =
    match member k j with `Int n -> n | _ -> default

  let member_float j k ~default =
    match member k j with
    | `Float f -> f
    | `Int n -> float_of_int n
    | _ -> default

  let b64_decode s =
    let inv = Array.make 256 (-1) in
    String.iteri
      (fun i c -> inv.(Char.code c) <- i)
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let n = String.length s in
    let b = Buffer.create (n / 4 * 3) in
    let i = ref 0 in
    (try
       while !i < n do
         let v j =
           let c = s.[!i + j] in
           if c = '=' then -1
           else (
             let d = inv.(Char.code c) in
             if d < 0 then raise Exit;
             d)
         in
         let a, b_, c, d = v 0, v 1, v 2, v 3 in
         if a < 0 || b_ < 0 then raise Exit;
         Buffer.add_char b (Char.chr ((a lsl 2) lor (b_ lsr 4)));
         if c >= 0 then
           Buffer.add_char b (Char.chr (((b_ land 15) lsl 4) lor (c lsr 2)));
         if d >= 0 && c >= 0 then
           Buffer.add_char b (Char.chr (((c land 3) lsl 6) lor d));
         i := !i + 4
       done;
       Ok (Buffer.contents b)
     with Exit -> Error "terminal: invalid base64")
    [@@coverage off]

  let hex (c : Lui_scene.color) =
    Printf.sprintf "#%02x%02x%02x%02x" c.r c.g c.b c.a

  let action_json = function
    | Vt.Title (k, s) ->
      `Assoc [ ("type", `String "title"); ("kind", `Int k);
               ("title", `String s) ]
    | Vt.Pwd s -> `Assoc [ ("type", `String "pwd"); ("path", `String s) ]
    | Vt.Bell -> `Assoc [ ("type", `String "bell") ]
    | Vt.Clipboard s ->
      `Assoc [ ("type", `String "clipboard"); ("text", `String s) ]
    | Vt.Reply s ->
      `Assoc [ ("type", `String "reply"); ("text", `String s) ]
    | Vt.Palette_set (i, c) ->
      `Assoc [ ("type", `String "palette"); ("index", `Int i);
               ("color", `String (hex c)) ]
    | Vt.Ink_set c ->
      `Assoc [ ("type", `String "ink"); ("color", `String (hex c)) ]
    | Vt.Paper_set c ->
      `Assoc [ ("type", `String "paper"); ("color", `String (hex c)) ]
    | Vt.Cursor_ink_set c ->
      `Assoc [ ("type", `String "cursor_ink"); ("color", `String (hex c)) ]

  let ok j = Ok (Yojson.Safe.to_string j)
  let obj () = `Assoc []

  let of_json f payload =
    match (try Ok (Yojson.Safe.from_string payload)
           with Yojson.Json_error e -> Error e) with
    | Error e -> Error ("terminal: invalid JSON: " ^ e)
    | Ok (`Assoc _ as j) -> f j
    | Ok _ -> Error "terminal: service input must be a JSON object"

  let svc_spawn =
    of_json @@ fun j ->
      let argv =
        match member_strs j "argv" with
        | [] ->
          [| (match Sys.getenv_opt "SHELL" with
              | Some s when s <> "" -> s
              | _ -> "/bin/sh") |]
        | l -> Array.of_list l
      in
      let cwd = Option.value (member_str j "cwd") ~default:"" in
      let env = Array.of_list (member_strs j "env") in
      let t =
        create
          ~cols:(member_int j "cols" ~default:80)
          ~rows:(member_int j "rows" ~default:24)
          ~max_scrollback:(member_int j "max_scrollback" ~default:10_000)
          ~font_size:(member_float j "font_size" ~default:13.)
          ~scale:(member_float j "scale" ~default:2.)
          ?families:(match member_strs j "families" with
                     | [] -> None
                     | l -> Some l)
          ()
      in
      match (try Ok (spawn t ~argv ~env ~cwd)
             with Failure e -> Error e) with
      | Error e -> Error e
      | Ok () ->
        let id = !next in
        incr next;
        Hashtbl.replace terms id t;
        ok (`Assoc [ ("id", `Int id) ])

  let svc_write =
    of_json @@ fun j ->
      match find j with
      | Error _ as e -> e
      | Ok t -> (
        match member_str j "data",
              (match member "data64" j with
               | `String s -> b64_decode s
               | _ -> Error "") with
        | Some s, _ -> write t s; ok (obj ())
        | None, Ok s -> write t s; ok (obj ())
        | None, Error _ -> Error "terminal: \"data\" or \"data64\" required")

  let svc_read_events =
    of_json @@ fun j ->
      match find j with
      | Error _ as e -> e
      | Ok t ->
        let actions = List.map action_json (pump t) in
        let g = Vt.grid t.vt in
        let cx, cy = G.cursor g in
        let style, blink = G.cursor_style g in
        ok (`Assoc [ ("alive", `Bool (pty_alive t));
                     ("exit",
                      (match pty_poll t with
                       | Some c -> `Int c
                       | None -> `Null));
                     ("actions", `List actions);
                     ("cursor",
                      `Assoc [ ("x", `Int cx); ("y", `Int cy);
                               ("visible", `Bool (G.mode_cursor_visible g));
                               ("style", `Int style);
                               ("blink", `Bool blink) ]);
                     ("cols", `Int (G.cols g));
                     ("rows", `Int (G.rows g));
                     ("scrollback", `Int (G.sb_len g)) ])

  let svc_resize =
    of_json @@ fun j ->
      match find j with
      | Error _ as e -> e
      | Ok t ->
        resize t ~cols:(member_int j "cols" ~default:(G.cols (grid t)))
                 ~rows:(member_int j "rows" ~default:(G.rows (grid t)));
        ok (obj ())

  let svc_close =
    of_json @@ fun j ->
      match find j with
      | Error _ as e -> e
      | Ok t ->
        close_pty t;
        Hashtbl.remove terms
          (match member "id" j with `Int n -> n | _ -> -1);
        ok (obj ())

  let reset () =
    Hashtbl.iter (fun _ t -> close_pty t) terms;
    Hashtbl.clear terms
end

let plugin : Lui_plugin.t =
  Lui_plugin.v "terminal" ~teardown:Service.reset
    [ ("spawn", Service.svc_spawn); ("write", Service.svc_write);
      ("read_events", Service.svc_read_events);
      ("resize", Service.svc_resize); ("close", Service.svc_close) ]
