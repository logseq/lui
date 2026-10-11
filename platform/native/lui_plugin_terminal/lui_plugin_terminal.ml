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
