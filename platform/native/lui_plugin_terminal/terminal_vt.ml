(* The VT parser: a byte-driven state machine that applies sequences
   to a {!Terminal_grid} and reports outward actions (window title,
   replies to send to the pty, hyperlinks, clipboard writes). *)

module G = Terminal_grid
module A = Terminal_attrs
module W = Terminal_wcwidth

(* Actions the host may need to act on; query replies are byte strings
   to write back to the pty. *)
type action =
  | Title of int * string
  | Pwd of string
  | Bell
  | Clipboard of string
  | Reply of string
  | Palette_set of int * Lui_scene.color
  | Ink_set of Lui_scene.color
  | Paper_set of Lui_scene.color
  | Cursor_ink_set of Lui_scene.color

type state =
  | Ground | Esc | Esc_int | Csi | Osc | Osc_esc | Dcs | Dcs_esc | Skip

(* UTF-8 accumulator. *)
type u8 = { mutable need : int; mutable acc : int }

type t = {
  grid : G.t;
  mutable st : state;
  u8 : u8;
  (* grapheme cluster under construction (codepoints, reversed) *)
  mutable cluster : int list;
  mutable zwj : bool;
  (* CSI scratch: a closed item list, the open item's value/sub digits
     and whether a ':' started sub-parameters *)
  mutable priv : char;
  mutable intm : char;
  mutable pars : (int * int list) list; (* closed items, reversed *)
  mutable dig : int;                    (* digit accumulator, -1 empty *)
  mutable subs : int list;              (* subs of open item, reversed *)
  mutable in_sub : bool;
  osc : Buffer.t;
  mutable esc_arg : char;
  (* designated charsets G0..G3 (0 = ascii, 1 = dec graphics) *)
  cs : int array;
  mutable gl : int;
  mutable gl_single : int;      (* SS2/SS3 one-shot, -1 none *)
  (* hyperlinks: uri <-> id *)
  links : (string, int) Hashtbl.t;
  uris : (int, string) Hashtbl.t;
  mutable next_link : int;
  mutable cur_link : int;
  acts : action Queue.t;
}

(* ---------------------------------------------------------------- *)

let grid t = t.grid
let link_uri t id = try Hashtbl.find t.uris id with Not_found -> ""
let cur_link t = t.cur_link

let pop_actions t =
  let a = List.of_seq (Queue.to_seq t.acts) in
  Queue.clear t.acts;
  a

let emit t a = Queue.add a t.acts

(* ---------------------------------------------------------------- *)

let intern_link t uri =
  try Hashtbl.find t.links uri
  with Not_found ->
    t.next_link <- t.next_link + 1;
    Hashtbl.replace t.links uri t.next_link;
    Hashtbl.replace t.uris t.next_link uri;
    t.next_link

(* DEC special graphics (line drawing) for printable 0x5F..0x7E. *)
let dec_graphics cp =
  if cp < 0x5F || cp > 0x7E then cp
  else
    let tbl = [|
      0x0020; 0x25C6; 0x2592; 0x2409; 0x240C; 0x240D; 0x240A; 0x00B0;
      0x00B1; 0x2424; 0x240B; 0x2518; 0x2510; 0x250C; 0x2514; 0x253C;
      0x23BA; 0x23BB; 0x2500; 0x23BC; 0x23BD; 0x251C; 0x2524; 0x2534;
      0x252C; 0x2502; 0x2264; 0x2265; 0x03C0; 0x2260; 0x00A3; 0x00B7 |]
    in
    tbl.(cp - 0x5F)

let utf8_of_cps cps =
  let b = Buffer.create 8 in
  List.iter (fun cp ->
      if cp < 0x80 then Buffer.add_char b (Char.chr cp)
      else if cp < 0x800 then begin
        Buffer.add_char b (Char.chr (0xC0 lor (cp lsr 6)));
        Buffer.add_char b (Char.chr (0x80 lor (cp land 0x3F)))
      end else if cp < 0x10000 then begin
        Buffer.add_char b (Char.chr (0xE0 lor (cp lsr 12)));
        Buffer.add_char b (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
        Buffer.add_char b (Char.chr (0x80 lor (cp land 0x3F)))
      end else begin
        Buffer.add_char b (Char.chr (0xF0 lor (cp lsr 18)));
        Buffer.add_char b (Char.chr (0x80 lor ((cp lsr 12) land 0x3F)));
        Buffer.add_char b (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
        Buffer.add_char b (Char.chr (0x80 lor (cp land 0x3F)))
      end)
    cps;
  Buffer.contents b

(* Flush the pending grapheme cluster to the grid. *)
let flush_cluster t =
  match t.cluster with
  | [] -> ()
  | cps ->
    let cps = List.rev cps in
    let wide = List.exists (fun c -> W.is_wide c || W.is_ri c) cps in
    let all_zero = List.for_all (fun c -> W.width c = 0) cps in
    let s = utf8_of_cps cps in
    if all_zero then G.extend t.grid s
    else G.put t.grid s (if wide then 2 else 1);
    t.cluster <- []

(* Feed one decoded codepoint in ground state. *)
let codepoint t cp =
  match cp with
  | _ when cp < 0x20 -> (
    (* C0 controls *)
    match cp with
    | 0x07 -> emit t Bell
    | 0x08 -> G.move_cursor t.grid (-1) 0
    | 0x09 -> G.tab_forward t.grid 1
    | 0x0A | 0x0B | 0x0C ->
      flush_cluster t;
      G.index t.grid;
      if G.mode_lnm t.grid then G.cursor_col t.grid 0
    | 0x0D -> flush_cluster t; G.cursor_col t.grid 0
    | 0x0E -> t.gl <- 1
    | 0x0F -> t.gl <- 0
    | 0x1B ->
      flush_cluster t;
      t.st <- Esc; t.intm <- '\000'; t.esc_arg <- '\000'
    | _ -> ())
  | 0x7F -> ()
  | _ when cp >= 0x80 && cp <= 0x9F -> (
    (* C1 controls, arrived as a decoded codepoint *)
    flush_cluster t;
    match cp with
    | 0x84 -> G.index t.grid
    | 0x85 -> G.newline t.grid
    | 0x88 -> G.tab_set t.grid
    | 0x8D -> G.rev_index t.grid
    | 0x8E -> t.gl_single <- 2
    | 0x8F -> t.gl_single <- 3
    | 0x90 -> t.st <- Dcs; Buffer.clear t.osc
    | 0x9B ->
      t.st <- Csi; t.priv <- '\000'; t.intm <- '\000';
      t.pars <- []; t.dig <- -1; t.subs <- []; t.in_sub <- false
    | 0x9D -> t.st <- Osc; Buffer.clear t.osc
    | 0x9E | 0x9F -> t.st <- Skip
    | _ -> ())
  | _ ->
    let zwj = t.zwj in
    let ri_pair =
      match t.cluster with
      | [c] -> W.is_ri c && W.is_ri cp
      | _ -> false
    in
    if zwj || ri_pair then begin
      t.cluster <- cp :: t.cluster;
      t.zwj <- false
    end else if W.is_zwj cp then begin
      t.cluster <- cp :: t.cluster;
      t.zwj <- true
    end else if W.is_vs cp || W.width cp = 0 then begin
      (* combining/format char joins the pending cluster or the cell *)
      if t.cluster = [] then G.extend t.grid (utf8_of_cps [cp])
      else t.cluster <- cp :: t.cluster
    end else begin
      flush_cluster t;
      (* designated graphics translation applies to ASCII range *)
      let sel =
        match t.gl_single with
        | s when s >= 0 -> t.gl_single <- -1; s
        | _ -> t.gl
      in
      let cp =
        if sel < Array.length t.cs && t.cs.(sel) = 1
        then dec_graphics cp else cp
      in
      if W.is_ri cp then t.cluster <- [cp]
      else G.put t.grid (utf8_of_cps [cp]) (min 2 (max 1 (W.width cp)))
    end

(* ---------------------------------------------------------------- *)

let pars_array t =
  (* t.pars is newest-first; the fold prepends converted items so the
     accumulator already holds input order *)
  let close acc (v, subs) = (v, Array.of_list subs) :: acc in
  Array.of_list (List.fold_left close [] t.pars)

(* Close the open item and push it. *)
let close_item t =
  let item =
    if t.in_sub then
      let subs = List.rev (t.dig :: t.subs) in
      (* the first ':' moved the value into cur_v (subs.(0) slot) —
         here subs.(0) IS the value we saved; unpack *)
      match subs with
      | v :: rest -> (v, rest)
      | [] -> (-1, [])
    else (t.dig, [])
  in
  (match item with
   | v, rest -> t.pars <- (v, rest) :: t.pars);
  t.dig <- -1; t.subs <- []; t.in_sub <- false

let csi_param t b =
  match b with
  | '0' .. '9' ->
    if t.dig < 0 then t.dig <- 0;
    t.dig <- min 1_000_000 (t.dig * 10 + Char.code b - Char.code '0')
  | ':' ->
    if not t.in_sub then begin
      (* the value moves into subs.(0) so the uniform close works *)
      t.subs <- t.dig :: t.subs;
      t.in_sub <- true
    end else
      t.subs <- t.dig :: t.subs;
    t.dig <- -1
  | ';' -> close_item t
  | '<' | '>' | '=' | '?' -> t.priv <- b
  | ' ' .. '/' -> t.intm <- b
  | _ -> ()

(* ---------------------------------------------------------------- *)

let charset_of = function '0' -> 1 | _ -> 0

let do_esc t fin =
  let designated =
    match t.esc_arg with
    | '(' -> Some 0 | ')' -> Some 1 | '*' -> Some 2 | '+' -> Some 3
    | '-' -> Some 1 | '.' -> Some 2 | '/' -> Some 3 | _ -> None
  in
  match designated with
  | Some slot -> t.cs.(slot) <- charset_of fin
  | None -> (
    match t.intm, fin with
    | '\000', '7' ->
      let packed =
        t.gl lor (t.cs.(0) lsl 4) lor (t.cs.(1) lsl 5)
        lor (t.cs.(2) lsl 6) lor (t.cs.(3) lsl 7)
      in
      G.save_cursor t.grid packed
    | '\000', '8' ->
      let packed = G.restore_cursor t.grid in
      t.gl <- packed land 0xF;
      for i = 0 to 3 do t.cs.(i) <- (packed lsr (4 + i)) land 1 done
    | '\000', 'D' -> G.index t.grid
    | '\000', 'E' -> G.newline t.grid
    | '\000', 'H' -> G.tab_set t.grid
    | '\000', 'M' -> G.rev_index t.grid
    | '\000', 'N' -> t.gl_single <- 2
    | '\000', 'O' -> t.gl_single <- 3
    | '\000', 'Z' -> emit t (Reply "\x1b[?1;2c")
    | '\000', '=' -> G.set_appcursor t.grid true
    | '\000', '>' -> G.set_appcursor t.grid false
    | '\000', 'c' -> (* RIS *)
      G.erase_in_display t.grid 2;
      G.set_scroll_region t.grid 0 (G.rows t.grid);
      G.set_cursor t.grid 0 0;
      G.set_pen t.grid A.default;
      G.set_link t.grid 0;
      G.exit_alt t.grid false;
      G.sel_clear t.grid;
      G.set_view t.grid 0;
      G.set_decawm t.grid true;
      G.set_ansi_mode t.grid 4 false;
      G.set_mode t.grid 6 false;
      t.cur_link <- 0
    | '#', '8' -> G.decaln t.grid
    | _ -> ())

(* ---------------------------------------------------------------- *)

let sgr t =
  let ps = pars_array t in
  G.set_pen t.grid (A.sgr (G.pen t.grid) ps)

let color_of_spec s =
  (* xterm color spec: #rgb #rrggbb #rrrgggbbb #rrrrggggbbbb, rgb:r/g/b *)
  let hex4 str i w =
    let v = ref 0 in
    for j = 0 to w - 1 do
      let c = str.[i + j] in
      v := !v * 16 +
        (if c >= '0' && c <= '9' then Char.code c - Char.code '0'
         else if c >= 'a' && c <= 'f' then Char.code c - Char.code 'a' + 10
         else Char.code c - Char.code 'A' + 10)
    done;
    !v * 255 / ((1 lsl (4 * w)) - 1)
  in
  let n = String.length s in
  if n >= 2 && s.[0] = '#' then begin
    let w = (n - 1) / 3 in
    if w >= 1 && w <= 4 && (n - 1) mod 3 = 0 then
      Some (Lui_scene.color (hex4 s 1 w) (hex4 s (1 + w) w)
              (hex4 s (1 + 2 * w) w) 255)
    else None
  end
  else if n >= 5 && String.sub s 0 4 = "rgb:" then
    try
      let parts = String.split_on_char '/' (String.sub s 4 (n - 4)) in
      match parts with
      | [a; b; c] ->
        let h p = int_of_string ("0x" ^ p) in
        let w = String.length a in
        Some (Lui_scene.color
                (h a * 255 / ((1 lsl (4 * w)) - 1))
                (h b * 255 / ((1 lsl (4 * w)) - 1))
                (h c * 255 / ((1 lsl (4 * w)) - 1)) 255)
      | _ -> None
    with _ -> None
  else None

let osc_dispatch t s =
  let n = String.length s in
  let semi =
    match String.index_opt s ';' with
    | Some i -> i | None -> n
  in
  let num =
    try int_of_string (String.sub s 0 semi) with _ -> -1
  in
  let rest = if semi < n then String.sub s (semi + 1) (n - semi - 1) else "" in
  match num with
  | 0 | 1 | 2 -> emit t (Title (num, rest))
  | 4 ->
    (* c;spec[;c;spec]* — report which palette slots change *)
    let parts = String.split_on_char ';' rest in
    let rec loop = function
      | ci :: spec :: tl -> (
        match (try Some (int_of_string ci) with _ -> None),
              color_of_spec spec with
        | Some i, Some c when i >= 0 && i < 256 ->
          emit t (Palette_set (i, c)); loop tl
        | _ -> loop tl)
      | _ -> ()
    in
    loop parts
  | 7 -> emit t (Pwd rest)
  | 8 -> (
    (* OSC 8 ; params ; URI — the URI takes the rest verbatim *)
    match String.index_opt rest ';' with
    | Some j ->
      let uri = String.sub rest (j + 1) (String.length rest - j - 1) in
      if uri = "" then begin
        t.cur_link <- 0; G.set_link t.grid 0
      end else begin
        t.cur_link <- intern_link t uri;
        G.set_link t.grid t.cur_link
      end
    | None -> ())
  | 10 -> (match color_of_spec rest with
           | Some c -> emit t (Ink_set c) | None -> ())
  | 11 -> (match color_of_spec rest with
           | Some c -> emit t (Paper_set c) | None -> ())
  | 12 -> (match color_of_spec rest with
           | Some c -> emit t (Cursor_ink_set c) | None -> ())
  | 52 -> emit t (Clipboard rest)
  | _ -> ()

(* ---------------------------------------------------------------- *)

let da_reply_primary = "\x1b[?64;1;2;4;6;9;15;18;21;22c"

let csi_dispatch t fin =
  let ps = pars_array t in
  let p i d =
    if i < Array.length ps && fst ps.(i) >= 0 then fst ps.(i) else d
  in
  let n0 = p 0 1 in
  match fin with
  | 'A' -> G.move_cursor t.grid 0 (-(max 1 n0))
  | 'B' | 'e' -> G.move_cursor t.grid 0 (max 1 n0)
  | 'C' | 'a' -> G.move_cursor t.grid (max 1 n0) 0
  | 'D' -> G.move_cursor t.grid (-(max 1 n0)) 0
  | 'E' -> G.move_cursor t.grid 0 (max 1 n0); G.cursor_col t.grid 0
  | 'F' -> G.move_cursor t.grid 0 (-(max 1 n0)); G.cursor_col t.grid 0
  | 'G' | '`' -> G.cursor_col t.grid (p 0 1 - 1)
  | 'H' | 'f' -> G.set_cursor t.grid (p 1 1 - 1) (p 0 1 - 1)
  | 'I' -> G.tab_forward t.grid (max 1 n0)
  | 'Z' -> G.tab_backward t.grid (max 1 n0)
  | 'J' -> G.erase_in_display t.grid (min 3 (max 0 (p 0 0)))
  | 'K' -> G.erase_in_line t.grid (min 2 (max 0 (p 0 0)))
  | 'L' -> G.insert_lines t.grid (max 1 n0)
  | 'M' -> G.delete_lines t.grid (max 1 n0)
  | 'P' -> G.delete_chars t.grid (max 1 n0)
  | 'X' -> G.erase_chars t.grid (max 1 n0)
  | 'S' -> G.scroll_up t.grid (max 1 n0)
  | 'T' ->
    if Array.length ps <= 2 then G.scroll_down t.grid (max 1 n0)
    (* larger T forms are mouse/window reports: ignore *)
  | '@' -> G.insert_chars t.grid (max 1 n0)
  | 'd' -> G.cursor_row t.grid (p 0 1 - 1)
  | 'g' -> G.tab_clear t.grid (p 0 0)
  | 'h' -> (
    let apply = if t.priv = '?' then G.set_mode else G.set_ansi_mode in
    Array.iter (fun (v, _) -> if v >= 0 then apply t.grid v true) ps)
  | 'l' -> (
    let apply = if t.priv = '?' then G.set_mode else G.set_ansi_mode in
    Array.iter (fun (v, _) -> if v >= 0 then apply t.grid v false) ps)
  | 'm' -> (match t.priv with '>' -> () | _ -> sgr t)
  | 'n' -> (
    match p 0 0 with
    | 5 -> emit t (Reply "\x1b[0n")
    | 6 ->
      let cx, cy = G.cursor t.grid in
      emit t (Reply (Printf.sprintf "\x1b[%d;%dR" (cy + 1) (cx + 1)))
    | _ -> ())
  | 'q' -> (match t.intm with ' ' -> G.set_cursor_style t.grid (p 0 0)
            | _ -> ())
  | 'r' -> (
    match t.priv with
    | '?' -> () (* DECCARA and friends: ignore *)
    | _ -> G.set_scroll_region t.grid (p 0 1 - 1) (p 1 (G.rows t.grid)))
  | 's' -> (match t.intm with ' ' -> () | _ -> G.save_cursor t.grid 0)
  | 'u' -> (match t.intm with ' ' -> ()
            | _ -> ignore (G.restore_cursor t.grid))
  | 'c' -> (
    match t.priv with
    | '>' | '=' -> emit t (Reply "\x1b[>0;276;0c")
    | _ -> emit t (Reply da_reply_primary))
  | 't' -> (
    (* window ops: report plausible sizes for the queries apps make *)
    match p 0 0 with
    | 14 -> emit t (Reply (Printf.sprintf "\x1b[4;%d;%dt"
                              (G.rows t.grid * 16) (G.cols t.grid * 8)))
    | 18 -> emit t (Reply (Printf.sprintf "\x1b[8;%d;%dt"
                              (G.rows t.grid) (G.cols t.grid)))
    | _ -> ())
  | 'x' -> emit t (Reply "\x1b[?1;2;9;15x") (* DECREQTPARM *)
  | 'y' -> (
    match t.intm with
    | '$' -> (* DECRPM *)
      let mode = p 0 0 in
      let v =
        if t.priv = '?' then
          match mode with
          | 1 -> (if G.mode_appcursor t.grid then 1 else 2)
          | 7 -> (if G.mode_decawm t.grid then 1 else 2)
          | 25 -> (if G.mode_cursor_visible t.grid then 1 else 2)
          | 2004 -> (if G.mode_bracketed t.grid then 1 else 2)
          | _ -> 0
        else 0
      in
      if v > 0 then
        emit t (Reply (Printf.sprintf "\x1b[?%d;%d$y" mode v))
    | _ -> ())
  | _ -> ()

(* ---------------------------------------------------------------- *)

let rec byte t b =
  match t.st with
  | Ground ->
    let u = t.u8 in
    if u.need > 0 && (b < 0x80 || b land 0xC0 <> 0x80) then begin
      (* truncated sequence: replacement char, then reprocess the byte *)
      u.need <- 0;
      codepoint t 0xFFFD;
      byte t b
    end else if b < 0x80 then
      codepoint t b
    else if b land 0xE0 = 0xC0 && b >= 0xC2 then begin
      u.need <- 1; u.acc <- b land 0x1F
    end else if b land 0xF0 = 0xE0 then begin
      u.need <- 2; u.acc <- b land 0x0F
    end else if b land 0xF8 = 0xF0 && b <= 0xF4 then begin
      u.need <- 3; u.acc <- b land 0x07
    end else if b land 0xC0 = 0x80 && u.need > 0 then begin
      u.acc <- (u.acc lsl 6) lor (b land 0x3F);
      u.need <- u.need - 1;
      if u.need = 0 then codepoint t u.acc
    end else
      (* malformed byte: replacement char, byte consumed *)
      codepoint t 0xFFFD
  | Esc ->
    if b >= 0x20 && b <= 0x2F then begin
      t.st <- Esc_int; t.intm <- Char.chr b
    end else begin
      match b with
      | 0x5B -> t.st <- Csi; t.priv <- '\000'; t.intm <- '\000';
                t.pars <- []; t.dig <- -1; t.subs <- [];
                t.in_sub <- false
      | 0x5D -> t.st <- Osc; Buffer.clear t.osc
      | 0x50 -> t.st <- Dcs; Buffer.clear t.osc
      | 0x58 | 0x5E | 0x5F -> t.st <- Skip
      | _ when b >= 0x30 && b <= 0x7E ->
        t.st <- Ground; do_esc t (Char.chr b)
      | _ -> t.st <- Ground
    end
  | Esc_int ->
    (* intermediates 0x20-0x2F; the last one before the final byte is
       intm, the first stays in esc_arg for charset designators *)
    if b >= 0x20 && b <= 0x2F then begin
      if t.esc_arg = '\000' then t.esc_arg <- t.intm;
      t.intm <- Char.chr b
    end else if b >= 0x30 && b <= 0x7E then begin
      if t.esc_arg = '\000' then t.esc_arg <- t.intm;
      t.st <- Ground; do_esc t (Char.chr b)
    end else
      t.st <- Ground
  | Csi ->
    if b >= 0x40 && b <= 0x7E then begin
      close_item t;
      t.st <- Ground;
      csi_dispatch t (Char.chr b)
    end else
      csi_param t (Char.chr b)
  | Osc -> (
    match b with
    | 0x07 -> t.st <- Ground; osc_dispatch t (Buffer.contents t.osc)
    | 0x1B -> t.st <- Osc_esc
    | 0x9C -> t.st <- Ground; osc_dispatch t (Buffer.contents t.osc)
    | _ -> Buffer.add_char t.osc (Char.chr b))
  | Osc_esc -> (
    match b with
    | 0x5C -> t.st <- Ground; osc_dispatch t (Buffer.contents t.osc)
    | _ ->
      Buffer.add_char t.osc '\x1b';
      Buffer.add_char t.osc (Char.chr b);
      t.st <- Osc)
  | Dcs -> (
    match b with
    | 0x1B -> t.st <- Dcs_esc
    | 0x9C | 0x07 -> t.st <- Ground
    | _ -> ())
  | Dcs_esc -> (
    match b with
    | 0x5C -> t.st <- Ground
    | _ -> t.st <- Dcs)
  | Skip -> (
    match b with
    | 0x1B -> t.st <- Dcs_esc
    | 0x9C | 0x07 -> t.st <- Ground
    | _ -> ())

let create ?(max_scrollback = 10_000) ~cols ~rows () =
  {
    grid = G.create ~cols ~rows ~max_scrollback;
    st = Ground; u8 = { need = 0; acc = 0 };
    cluster = []; zwj = false;
    priv = '\000'; intm = '\000'; pars = []; dig = -1;
    subs = []; in_sub = false;
    osc = Buffer.create 64; esc_arg = '\000';
    cs = Array.make 4 0; gl = 0; gl_single = -1;
    links = Hashtbl.create 17; uris = Hashtbl.create 17;
    next_link = 0; cur_link = 0;
    acts = Queue.create ();
  }

let feed t s off len =
  for i = off to off + len - 1 do
    byte t (Char.code s.[i])
  done;
  flush_cluster t;
  pop_actions t

let feed_string t s = feed t s 0 (String.length s)
