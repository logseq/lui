(* The screen model: the visible grid, the scrollback ring, cursor and
   mode state, damage tracking, reflow on resize and the selection. *)

module A = Terminal_attrs

(* A cell holds a whole grapheme cluster; the second cell of a wide
   cluster is a spacer with empty text. *)
type cell = {
  mutable text : string;
  mutable attrs : A.t;
  mutable wide : bool;
  mutable spacer : bool;
  mutable link : int; (* hyperlink id; 0 = none *)
}

let blank_cell () = { text = ""; attrs = A.default; wide = false;
                      spacer = false; link = 0 }

(* [id] is stable across scrolling: rows keep the id they were created
   with, so selections anchored to a line follow it through scrollback. *)
type row = { cells : cell array; mutable wrapped : bool; mutable id : int }

let blank_row cols id =
  { cells = Array.init cols (fun _ -> blank_cell ()); wrapped = false; id }

(* A position in document space: the scrollback occupies lines
   [first_id .. first_id+sb_len), the screen follows. *)
type pos = { id : int; col : int }

type sel_kind = Sel_char | Sel_word | Sel_line

type selection = {
  kind : sel_kind;
  anchor : pos;       (* where the drag started *)
  head : pos;         (* where the drag is now *)
}

type saved = {
  sx : int; sy : int;
  spen : A.t;
  sorigin : bool;
  sextra : int;       (* opaque parser state (charset designations) *)
  swrap : bool;
}

type t = {
  mutable cols : int;
  mutable rows : int;
  mutable screen : row array;
  (* scrollback ring: sb_start is the slot of the oldest line *)
  sb : row array;
  mutable sb_start : int;
  mutable sb_len : int;
  mutable next_id : int;
  mutable cx : int;
  mutable cy : int;
  mutable pen : A.t;
  mutable link : int;
  mutable wrap_pending : bool;
  mutable top : int;             (* scroll region, row indices *)
  mutable bot : int;
  tabs : bool array;             (* fixed 512 stop slots *)
  mutable saved : saved;
  mutable alt : bool;
  mutable saved_screen : row array option; (* main grid while alt is up *)
  mutable view : int;            (* scrollback rows shown above viewport *)
  mutable sel : selection option;
  mutable dirty : bool array;    (* per screen row *)
  mutable dirty_all : bool;
  mutable sb_dirty : bool;       (* scrollbar needs repainting *)
  (* modes *)
  mutable m_appcursor : bool;
  mutable m_decawm : bool;
  mutable m_cursor_visible : bool;
  mutable m_focus : bool;
  mutable m_altscroll : bool;
  mutable m_sync : bool;
  mutable m_graphemes : bool;
  mutable m_insert : bool;
  mutable m_origin : bool;
  mutable m_bracketed : bool;
  mutable m_mouse : int;         (* 0 none / 1 click / 2 drag / 3 motion *)
  mutable m_mouse_fmt : int;     (* 0 x10 / 1 utf8 / 2 sgr / 3 urxvt / 4 px *)
  mutable m_lnm : bool;          (* LNM: linefeed implies carriage return *)
  mutable cursor_style : int;    (* DECSCUSR 0..6 *)
  mutable cursor_blink : bool;
}

let rows_max = 512

let create ~cols ~rows ~max_scrollback =
  let sb = Array.init (max 0 max_scrollback) (fun _ -> blank_row 0 (-1)) in
  let screen = Array.init rows (fun i -> blank_row cols i) in
  {
    cols; rows; screen; sb; sb_start = 0; sb_len = 0;
    next_id = rows;
    cx = 0; cy = 0; pen = A.default; link = 0; wrap_pending = false;
    top = 0; bot = rows;
    tabs = Array.init rows_max (fun i -> i > 0 && i mod 8 = 0);
    saved = { sx = 0; sy = 0; spen = A.default; sorigin = false;
              sextra = 0; swrap = false };
    alt = false; saved_screen = None;
    view = 0; sel = None;
    dirty = Array.make rows false; dirty_all = true; sb_dirty = false;
    m_appcursor = false; m_decawm = true; m_cursor_visible = true;
    m_focus = false; m_altscroll = false; m_sync = false;
    m_graphemes = false; m_insert = false; m_origin = false;
    m_bracketed = false; m_mouse = 0; m_mouse_fmt = 0;
    m_lnm = false;
    cursor_style = 1; cursor_blink = true;
  }

let cols t = t.cols and rows t = t.rows
let sb_len t = t.sb_len
let cursor t = (t.cx, t.cy)
let pen t = t.pen
let is_alt t = t.alt
let view t = t.view
let has_selection t = t.sel <> None
let cursor_style t = (t.cursor_style, t.cursor_blink)
let tabs t = t.tabs

let mode_appcursor t = t.m_appcursor
let mode_decawm t = t.m_decawm
let mode_cursor_visible t = t.m_cursor_visible
let mode_focus t = t.m_focus
let mode_altscroll t = t.m_altscroll
let mode_sync t = t.m_sync
let mode_graphemes t = t.m_graphemes
let mode_bracketed t = t.m_bracketed
let mode_mouse t = t.m_mouse
let mode_mouse_fmt t = t.m_mouse_fmt
let mode_lnm t = t.m_lnm

let mark_row t y = if y >= 0 && y < t.rows then t.dirty.(y) <- true
let mark_all t = t.dirty_all <- true

(* ---- row access -------------------------------------------------- *)

let sb_row t i = t.sb.((t.sb_start + i) mod Array.length t.sb)

let screen_row t y = t.screen.(y)

(* A document row: i in [0, sb_len + rows). *)
let doc_row t i =
  if i < t.sb_len then sb_row t i else t.screen.(i - t.sb_len)

let cell_at t i x =
  let r = doc_row t i in
  if x >= 0 && x < Array.length r.cells then Some r.cells.(x) else None

let screen_cell t y x =
  if y >= 0 && y < t.rows && x >= 0 && x < t.cols
  then Some t.screen.(y).cells.(x) else None

let row_text t i =
  let r = doc_row t i in
  let b = Buffer.create (Array.length r.cells) in
  Array.iter (fun c -> if not c.spacer then Buffer.add_string b c.text)
    r.cells;
  Buffer.contents b

(* ---- scrollback --------------------------------------------------- *)

let push_sb t (r : row) =
  if Array.length t.sb > 0 then begin
    if t.sb_len = Array.length t.sb then begin
      (* evict the oldest; a selection pointing at it is clamped later *)
      t.sb_start <- (t.sb_start + 1) mod Array.length t.sb;
      t.sb_len <- t.sb_len - 1
    end;
    t.sb.((t.sb_start + t.sb_len) mod Array.length t.sb) <- r;
    t.sb_len <- t.sb_len + 1;
    t.sb_dirty <- true
  end

(* ---- cursor moves ------------------------------------------------- *)

let clamp_cursor t =
  t.cx <- min (max 0 t.cx) (t.cols - 1);
  let lo, hi =
    if t.m_origin then (t.top, t.bot - 1) else (0, t.rows - 1) in
  t.cy <- min (max lo t.cy) hi;
  t.wrap_pending <- false

let set_cursor t x y =
  t.cx <- x;
  t.cy <- (if t.m_origin then y + t.top else y);
  clamp_cursor t

let move_cursor t dx dy =
  t.cx <- t.cx + dx;
  t.cy <- t.cy + dy;
  clamp_cursor t

let cursor_col t x = t.cx <- x; clamp_cursor t
let cursor_row t y =
  t.cy <- (if t.m_origin then y + t.top else y); clamp_cursor t

(* ---- scrolling ---------------------------------------------------- *)

(* Scroll region [top,bot) up n lines; lines leaving at the top land in
   scrollback only when the region is the full screen.  Rows that leave
   the region on a partial scroll are recycled into the blanks at the
   bottom; on a full scroll they are in scrollback and fresh rows are
   allocated. *)
let scroll_up t ?(top = t.top) ?(bot = t.bot) n =
  let n = min n (bot - top) in
  if n > 0 then begin
    let full = top = 0 && bot = t.rows in
    let leaving = Array.init n (fun i -> t.screen.(top + i)) in
    if full then Array.iter (push_sb t) leaving;
    for y = top to bot - n - 1 do
      t.screen.(y) <- t.screen.(y + n)
    done;
    for i = 0 to n - 1 do
      let r =
        if not full && Array.length leaving.(i).cells = t.cols
        then leaving.(i)
        else blank_row t.cols t.next_id
      in
      r.id <- t.next_id; t.next_id <- t.next_id + 1;
      Array.iter (fun c -> c.text <- ""; c.attrs <- t.pen;
                           c.wide <- false; c.spacer <- false; c.link <- 0)
        r.cells;
      r.wrapped <- false;
      t.screen.(bot - 1 - i) <- r
    done;
    mark_all t
  end

let scroll_down t ?(top = t.top) ?(bot = t.bot) n =
  let n = min n (bot - top) in
  if n > 0 then begin
    for y = bot - 1 downto top + n do
      t.screen.(y) <- t.screen.(y - n)
    done;
    for i = 0 to n - 1 do
      let r = blank_row t.cols t.next_id in
      t.next_id <- t.next_id + 1;
      Array.iter (fun c -> c.attrs <- t.pen) r.cells;
      t.screen.(top + i) <- r
    done;
    mark_all t
  end

(* Line feed: move down or scroll the region. *)
let index t =
  t.wrap_pending <- false;
  if t.cy = t.bot - 1 then scroll_up t ~top:t.top ~bot:t.bot 1
  else if t.cy = t.rows - 1 then ()
  else t.cy <- t.cy + 1

let rev_index t =
  t.wrap_pending <- false;
  if t.cy = t.top then scroll_down t ~top:t.top ~bot:t.bot 1
  else if t.cy > 0 then t.cy <- t.cy - 1

let newline t = index t; t.cx <- 0

let insert_lines t n =
  if t.cy >= t.top && t.cy < t.bot then
    scroll_down t ~top:t.cy ~bot:t.bot n

let delete_lines t n =
  if t.cy >= t.top && t.cy < t.bot then
    scroll_up t ~top:t.cy ~bot:t.bot n

(* ---- erase -------------------------------------------------------- *)

let fill t r x0 x1 =
  for x = max 0 x0 to min (t.cols - 1) (x1 - 1) do
    let c = r.cells.(x) in
    c.text <- ""; c.attrs <- t.pen; c.wide <- false;
    c.spacer <- false; c.link <- 0
  done

let erase_in_line t mode =
  let r = t.screen.(t.cy) in
  (match mode with
   | 0 -> fill t r t.cx t.cols
   | 1 -> fill t r 0 (t.cx + 1)
   | _ -> fill t r 0 t.cols; r.wrapped <- false);
  mark_row t t.cy

let erase_in_display t mode =
  match mode with
  | 0 ->
    erase_in_line t 0;
    for y = t.cy + 1 to t.rows - 1 do
      fill t t.screen.(y) 0 t.cols; t.screen.(y).wrapped <- false;
      mark_row t y
    done
  | 1 ->
    erase_in_line t 1;
    for y = 0 to t.cy - 1 do
      fill t t.screen.(y) 0 t.cols; t.screen.(y).wrapped <- false;
      mark_row t y
    done
  | 2 ->
    for y = 0 to t.rows - 1 do
      fill t t.screen.(y) 0 t.cols; t.screen.(y).wrapped <- false;
      mark_row t y
    done
  | 3 -> (* clear scrollback *)
    t.sb_len <- 0; t.sb_start <- 0;
    t.sb_dirty <- true;
    (match t.sel with
     | Some s when s.anchor.id < t.screen.(0).id -> t.sel <- None
     | _ -> ())
  | _ -> ()

let erase_chars t n =
  fill t t.screen.(t.cy) t.cx (t.cx + max 1 n);
  mark_row t t.cy

(* ---- insert/delete chars ------------------------------------------ *)

let insert_chars t n =
  let r = t.screen.(t.cy) in
  let n = min n (t.cols - t.cx) in
  if n > 0 then begin
    for x = t.cols - 1 downto t.cx + n do
      let d = r.cells.(x) and s = r.cells.(x - n) in
      d.text <- s.text; d.attrs <- s.attrs; d.wide <- s.wide;
      d.spacer <- s.spacer; d.link <- s.link
    done;
    fill t r t.cx (t.cx + n);
    mark_row t t.cy
  end

let delete_chars t n =
  let r = t.screen.(t.cy) in
  let n = min n (t.cols - t.cx) in
  if n > 0 then begin
    for x = t.cx to t.cols - n - 1 do
      let d = r.cells.(x) and s = r.cells.(x + n) in
      d.text <- s.text; d.attrs <- s.attrs; d.wide <- s.wide;
      d.spacer <- s.spacer; d.link <- s.link
    done;
    fill t r (t.cols - n) t.cols;
    mark_row t t.cy
  end

(* ---- printing ------------------------------------------------------ *)

let set_link t id = t.link <- id
let set_pen t p = t.pen <- p

let blank_with_pen t (c : cell) =
  c.text <- ""; c.attrs <- t.pen; c.wide <- false;
  c.spacer <- false; c.link <- t.link

(* write a cluster of width 1 or 2 at the cursor *)
let put t text width =
  if t.wrap_pending && width > 0 then begin
    t.wrap_pending <- false;
    t.screen.(t.cy).wrapped <- true;
    newline t
  end;
  if t.m_insert then insert_chars t width;
  if t.cx >= t.cols then t.cx <- t.cols - 1;
  let r = t.screen.(t.cy) in
  let c = r.cells.(t.cx) in
  (* replacing the head or tail of a wide pair clears the partner *)
  if c.spacer && t.cx > 0 then blank_with_pen t r.cells.(t.cx - 1);
  if c.wide && t.cx + 1 < t.cols then blank_with_pen t r.cells.(t.cx + 1);
  c.text <- text; c.attrs <- t.pen; c.link <- t.link;
  c.spacer <- false;
  if width = 2 && t.cx = t.cols - 1 then begin
    (* a wide char in the last column wraps: blank it and go down *)
    c.wide <- false;
    blank_with_pen t c;
    if t.m_decawm then begin
      t.screen.(t.cy).wrapped <- true;
      newline t;
      let r' = t.screen.(t.cy) in
      let c' = r'.cells.(0) in
      c'.text <- text; c'.attrs <- t.pen; c'.link <- t.link;
      c'.wide <- true; c'.spacer <- false;
      let s = r'.cells.(1) in
      s.text <- ""; s.attrs <- t.pen; s.link <- t.link;
      s.wide <- false; s.spacer <- true;
      t.cx <- 1; t.wrap_pending <- true
    end else begin
      c.text <- text; c.attrs <- t.pen; c.wide <- false; c.link <- t.link
    end
  end else if width = 2 then begin
    c.wide <- true;
    let s = r.cells.(t.cx + 1) in
    s.text <- ""; s.attrs <- t.pen; s.link <- t.link;
    s.wide <- false; s.spacer <- true;
    if t.cx + 1 = t.cols - 1 then begin
      t.cx <- t.cols - 1;
      t.wrap_pending <- t.m_decawm
    end else
      t.cx <- t.cx + 2
  end else begin
    c.wide <- false;
    if t.cx = t.cols - 1 then begin
      if t.m_decawm then t.wrap_pending <- true
      else () (* cursor stays; the next char overwrites *)
    end else
      t.cx <- t.cx + 1
  end;
  mark_row t t.cy

(* append combining text to the cluster under the cursor's left
   neighbour (xterm behaviour for marks with no base pending) *)
let extend t text =
  let x, y =
    if t.cx > 0 then (t.cx - 1, t.cy)
    else if t.cy > 0 then (t.cols - 1, t.cy - 1)
    else (0, t.cy)
  in
  let r = t.screen.(y) in
  let c = if r.cells.(x).spacer && x > 0 then r.cells.(x - 1)
          else r.cells.(x) in
  c.text <- c.text ^ text;
  mark_row t y

(* ---- tabs ---------------------------------------------------------- *)

let tab_forward t n =
  let rec next x i =
    if x >= t.cols || x >= rows_max || i = 0 then min x (t.cols - 1)
    else if t.tabs.(x) then next (x + 1) (i - 1)
    else next (x + 1) i
  in
  t.cx <- next (t.cx + 1) n; t.wrap_pending <- false

let tab_backward t n =
  let rec prev x i =
    if x < 0 || i = 0 then max 0 x
    else if t.tabs.(x) then prev (x - 1) (i - 1)
    else prev (x - 1) i
  in
  t.cx <- prev (t.cx - 1) n; t.wrap_pending <- false

let tab_set t = if t.cx < rows_max then t.tabs.(t.cx) <- true
let tab_clear t mode =
  (match mode with
   | 0 -> if t.cx < rows_max then t.tabs.(t.cx) <- false
   | _ -> Array.fill t.tabs 0 rows_max false)

(* ---- scroll region -------------------------------------------------- *)

let set_scroll_region t top bot =
  if top >= 0 && bot <= t.rows && bot - top > 1 then begin
    t.top <- top; t.bot <- bot;
    set_cursor t 0 0
  end

let scroll_region t = (t.top, t.bot)

(* ---- save/restore ---------------------------------------------------- *)

let save_cursor t extra =
  t.saved <- { sx = t.cx; sy = t.cy; spen = t.pen;
               sorigin = t.m_origin; sextra = extra;
               swrap = t.wrap_pending }

let restore_cursor t =
  let s = t.saved in
  t.cx <- s.sx; t.cy <- s.sy; t.pen <- s.spen;
  t.m_origin <- s.sorigin; t.wrap_pending <- s.swrap;
  clamp_cursor t;
  s.sextra

(* ---- alt screen ------------------------------------------------------- *)

let enter_alt t save =
  if not t.alt then begin
    if save then save_cursor t 0;
    t.saved_screen <- Some t.screen;
    t.screen <- Array.init t.rows (fun i -> blank_row t.cols (t.next_id + i));
    t.next_id <- t.next_id + t.rows;
    t.alt <- true;
    t.view <- 0;
    mark_all t
  end

let exit_alt t restore =
  if t.alt then begin
    (match t.saved_screen with
     | Some s -> t.screen <- s
     | None -> ());
    t.saved_screen <- None;
    t.alt <- false;
    t.view <- 0;
    if restore then ignore (restore_cursor t);
    mark_all t
  end

(* ---- modes ------------------------------------------------------------- *)

let set_mode t n v =
  match n with
  | 1 -> t.m_appcursor <- v
  | 4 -> t.m_insert <- v
  | 6 -> t.m_origin <- v; set_cursor t 0 0
  | 25 -> t.m_cursor_visible <- v; mark_all t
  | 47 | 1047 -> if v then enter_alt t false else exit_alt t false
  | 1048 -> if v then save_cursor t 0 else ignore (restore_cursor t)
  | 1049 -> if v then enter_alt t true else exit_alt t true
  | 1000 -> t.m_mouse <- (if v then 1 else 0)
  | 1002 -> t.m_mouse <- (if v then 2 else 0)
  | 1003 -> t.m_mouse <- (if v then 3 else 0)
  | 1004 -> t.m_focus <- v
  | 1005 -> t.m_mouse_fmt <- (if v then 1 else t.m_mouse_fmt)
  | 1006 -> t.m_mouse_fmt <- (if v then 2 else t.m_mouse_fmt)
  | 1015 -> t.m_mouse_fmt <- (if v then 3 else t.m_mouse_fmt)
  | 1016 -> t.m_mouse_fmt <- (if v then 4 else t.m_mouse_fmt)
  | 1007 -> t.m_altscroll <- v
  | 2004 -> t.m_bracketed <- v
  | 2026 -> t.m_sync <- v
  | 2027 -> t.m_graphemes <- v
  | _ -> ()

let set_ansi_mode t n v =
  match n with
  | 4 -> t.m_insert <- v
  | 20 -> t.m_lnm <- v
  | _ -> ()

(* DECALN: screen alignment pattern — fill every cell with 'E'. *)
let decaln t =
  for y = 0 to t.rows - 1 do
    let r = t.screen.(y) in
    Array.iter (fun c ->
        c.text <- "E"; c.attrs <- A.default; c.wide <- false;
        c.spacer <- false; c.link <- 0)
      r.cells;
    r.wrapped <- false
  done;
  mark_all t

let set_decawm t v = t.m_decawm <- v
let set_appcursor t v = t.m_appcursor <- v
let set_cursor_style t n =
  t.cursor_style <- (match n with 0 | 1 | 2 -> 1 | 3 | 4 -> 3 | _ -> 5);
  t.cursor_blink <- n mod 2 = 1 || n = 0;
  mark_all t

(* ---- resize / reflow ----------------------------------------------------- *)

(* logical lines: a row plus its wrapped continuations *)
let logical_lines t =
  let groups = ref [] and cur = ref [] in
  for i = 0 to t.sb_len + t.rows - 1 do
    let r = doc_row t i in
    if r.wrapped && !cur <> [] then cur := r :: !cur
    else begin
      if !cur <> [] then groups := List.rev !cur :: !groups;
      cur := [r]
    end
  done;
  if !cur <> [] then groups := List.rev !cur :: !groups;
  List.rev !groups

(* reflow one logical line to width [w]; returns new rows (rev order
   inside each logical line is natural order here) *)
let reflow t w line =
  let cps = List.concat_map (fun r -> Array.to_list r.cells) line in
  (* drop trailing blanks of the last row only *)
  let cells = Array.of_list cps in
  let n = Array.length cells in
  let last_nonblank =
    let rec f i =
      if i < 0 then -1
      else if cells.(i).text = "" && not cells.(i).spacer then f (i - 1)
      else i
    in
    f (n - 1)
  in
  let used = last_nonblank + 1 in
  let wrapped = List.length line > 1 || (List.hd line).wrapped in
  if used <= w && not wrapped then
    (* fits on one row *)
    let r = blank_row w (List.hd line).id in
    for x = 0 to used - 1 do r.cells.(x) <- cells.(x) done;
    for x = used to w - 1 do r.cells.(x).attrs <- cells.(min x (n-1)).attrs done;
    [r]
  else begin
    (* lay cells out; a wide char split at the edge pushes to next row *)
    let rows = ref [] in
    let cur = ref (blank_row w (List.hd line).id) in
    let cx = ref 0 in
    let newrow () =
      !cur.wrapped <- !rows <> [];
      rows := !cur :: !rows;
      cur := blank_row w t.next_id; t.next_id <- t.next_id + 1;
      cx := 0
    in
    let i = ref 0 in
    while !i < used do
      let c = cells.(!i) in
      if c.spacer then incr i
      else begin
        let wide = c.wide in
        if wide && !cx = w - 1 then newrow ();
        if !cx >= w then newrow ();
        let d = (!cur).cells.(!cx) in
        d.text <- c.text; d.attrs <- c.attrs; d.wide <- c.wide;
        d.spacer <- false; d.link <- c.link;
        if wide then begin
          let s = (!cur).cells.(!cx + 1) in
          s.text <- ""; s.attrs <- c.attrs; s.spacer <- true;
          s.wide <- false; s.link <- c.link;
          cx := !cx + 2
        end else incr cx;
        incr i
      end
    done;
    !cur.wrapped <- !rows <> [];
    rows := !cur :: !rows;
    List.rev !rows
  end

let resize t ~cols ~rows =
  if cols <> t.cols || rows <> t.rows then begin
    (* cursor's logical position: which line and offset within it *)
    let lines = logical_lines t in
    let cur_li, cur_off =
      let target = t.sb_len + t.cy in
      let rec find acc li = function
        | [] -> (0, 0)
        | l :: rest ->
          let len = List.length l in
          if target >= acc && target < acc + len then
            (li, (target - acc) * t.cols + t.cx)
          else find (acc + len) (li + 1) rest
      in
      find 0 0 lines
    in
    let reflowed = List.map (reflow t cols) lines in
    let flat = List.concat reflowed in
    let total = List.length flat in
    (* keep as much scrollback as fits; the screen takes the last rows *)
    let arr = Array.of_list flat in
    let keep = min total (max 0 (Array.length t.sb) + rows) in
    let start = total - keep in
    let body = Array.sub arr start keep in
    let sb_n = max 0 (keep - rows) in
    (* rewrite scrollback ring *)
    t.sb_len <- 0; t.sb_start <- 0;
    for i = 0 to sb_n - 1 do
      t.sb.(i) <- body.(i); t.sb_len <- t.sb_len + 1
    done;
    (* fill the screen; pad top if the content shrank *)
    let sc = Array.init rows (fun _ -> blank_row cols (-1)) in
    let have = keep - sb_n in
    for y = 0 to rows - 1 do
      if y >= rows - have then
        sc.(y) <- body.(sb_n + y - (rows - have))
    done;
    t.screen <- sc;
    t.cols <- cols; t.rows <- rows;
    t.dirty <- Array.make rows true;
    t.dirty_all <- true;
    (* cursor position in the reflowed layout *)
    let before =
      let rec sum acc i = function
        | [] -> acc
        | l :: rest ->
          if i >= cur_li then acc
          else sum (acc + List.length l) (i + 1) rest
      in
      sum 0 0 reflowed
    in
    let crow = before + cur_off / cols in
    let ccol = cur_off mod cols in
    t.cy <- min crow (rows - 1);
    t.cx <- min ccol (cols - 1);
    t.top <- 0; t.bot <- rows;
    t.wrap_pending <- false;
    (* the alt grid, if any, is rebuilt blank at the new size *)
    (match t.saved_screen with
     | Some s when Array.length s <> rows ||
                   (Array.length s > 0 &&
                    Array.length s.(0).cells <> cols) ->
       t.saved_screen <- Some (Array.init rows
                                 (fun i -> blank_row cols (-i - 1)))
     | _ -> ());
    t.view <- 0;
    t.sb_dirty <- true
  end

(* ---- viewport -------------------------------------------------------- *)

let scroll_view t delta =
  let v = min (max 0 (t.view + delta)) t.sb_len in
  if v <> t.view then begin t.view <- v; mark_all t end

let set_view t v =
  let v = min (max 0 v) t.sb_len in
  if v <> t.view then begin t.view <- v; mark_all t end

(* the document row shown at viewport row y *)
let shown_row t y =
  let i = t.sb_len - t.view + y in
  if i < 0 || i >= t.sb_len + t.rows then None
  else Some (i, doc_row t i)

(* ---- selection -------------------------------------------------------- *)

let sel_start t ~id ~col kind =
  t.sel <- Some { kind; anchor = { id; col }; head = { id; col } };
  mark_all t

let sel_extend t ~id ~col =
  match t.sel with
  | None -> ()
  | Some s -> t.sel <- Some { s with head = { id; col } }; mark_all t

let sel_clear t =
  if t.sel <> None then begin t.sel <- None; mark_all t end

(* word characters for double-click selection *)
let is_word_byte b =
  Char.code b > 0x7F ||
  (match b with
   | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
   | '-' | '.' | '_' | '~' | ':' | '/' | '?' | '#' | '@' | '!' | '$'
   | '&' | '*' | '+' | '=' | '%' | ',' -> true
   | _ -> false)

let row_id_at t i =
  if i < 0 || i >= t.sb_len + t.rows then None else Some (doc_row t i).id

let id_to_index t id =
  (* row ids are stable per row but not dense (reflow re-ids), so a
     linear scan is the reliable lookup; selections are rare *)
  let rec f i =
    if i >= t.sb_len + t.rows then None
    else if (doc_row t i).id = id then Some i
    else f (i + 1)
  in
  f 0

(* normalize selection to ordered (r0,c0)-(r1,c1) document coords;
   word/line kinds expand the range *)
let sel_range t =
  match t.sel with
  | None -> None
  | Some s ->
    (match id_to_index t s.anchor.id, id_to_index t s.head.id with
     | Some ai, Some hi ->
       let (r0, c0), (r1, c1) =
         if (ai, s.anchor.col) <= (hi, s.head.col)
         then ((ai, s.anchor.col), (hi, s.head.col))
         else ((hi, s.head.col), (ai, s.anchor.col))
       in
       (match s.kind with
        | Sel_char -> Some (r0, c0, r1, c1)
        | Sel_line ->
          Some (r0, 0, r1, max 0 (t.cols - 1))
        | Sel_word ->
          let word_bounds r c =
            let row = doc_row t r in
            let txt x =
              let cell = row.cells.(min (max 0 x) (Array.length row.cells - 1)) in
              cell.text
            in
            let isw x =
              let s = txt x in
              String.length s > 0 && is_word_byte s.[0]
            in
            let lo = ref c and hi = ref c in
            while !lo > 0 && isw (!lo - 1) do decr lo done;
            while !hi < t.cols - 1 && isw (!hi + 1) do incr hi done;
            (!lo, !hi)
          in
          let c0, _ = word_bounds r0 c0 in
          let _, c1 = word_bounds r1 c1 in
          Some (r0, c0, r1, c1))
     | _ ->
       (* an endpoint scrolled out of history: clamp to the far edge *)
       let last = t.sb_len + t.rows - 1 in
       Some (0, 0, last, t.cols - 1))

let sel_covers t ~row ~col =
  match sel_range t with
  | None -> false
  | Some (r0, c0, r1, c1) ->
    (row, col) >= (r0, c0) && (row, col) <= (r1, c1)

let sel_text t =
  match sel_range t with
  | None -> ""
  | Some (r0, c0, r1, c1) ->
    let b = Buffer.create 256 in
    for r = r0 to r1 do
      let row = doc_row t r in
      let x0 = if r = r0 then c0 else 0 in
      let x1 = if r = r1 then c1 else t.cols - 1 in
      let last = ref x0 in
      for x = x0 to min x1 (Array.length row.cells - 1) do
        let c = row.cells.(x) in
        if not c.spacer && c.text <> "" then begin
          (* pad skipped blanks *)
          for _ = !last + 1 to x - 1 do Buffer.add_char b ' ' done;
          Buffer.add_string b c.text;
          last := x
        end
      done;
      if r < r1 then
        if not row.wrapped then Buffer.add_char b '\n'
    done;
    Buffer.contents b

(* ---- damage -------------------------------------------------------- *)

let dirty_row t y =
  t.dirty_all || (y >= 0 && y < t.rows && t.dirty.(y))

let damaged t = t.dirty_all || Array.exists (fun x -> x) t.dirty

let sb_dirty t = t.sb_dirty

let clear_damage t =
  Array.fill t.dirty 0 t.rows false;
  t.dirty_all <- false;
  t.sb_dirty <- false
