(* Key and mouse events to wire bytes: legacy sequences, the
   application-cursor variants, modifier parameters and SGR/X10 mouse
   reports.  Events use {!Lui_window.Input} so the widget can take the
   host's events unmodified. *)

open Lui_window.Input

(* xterm modifier count: 1 + shift + 2*alt + 4*ctrl (meta folds into
   alt — terminals have no meta concept). *)
let modn m =
  1 + (if m.shift then 1 else 0)
    + (if m.alt || m.meta then 2 else 0)
    + (if m.ctrl then 4 else 0)

let csi fmt = Printf.sprintf fmt

(* SDL scancode -> the character a terminal's modifier tables use. *)
let ctrl_byte_of_scancode = function
  | n when n >= 4 && n <= 29 ->   (* a..z *)
    Some (n - 3)                  (* 1..26 *)
  | 31 -> Some 0                  (* ctrl+2 -> NUL *)
  | 32 -> Some 27                 (* ctrl+3 -> ESC *)
  | 33 -> Some 28                 (* ctrl+4 -> FS *)
  | 34 -> Some 29                 (* ctrl+5 -> GS *)
  | 35 -> Some 30                 (* ctrl+6 -> RS *)
  | 36 -> Some 31                 (* ctrl+7 -> US *)
  | 37 -> Some 127                (* ctrl+8 -> DEL *)
  | 45 -> Some 31                 (* ctrl+- -> US *)
  | 46 -> Some 0                  (* ctrl+= *)
  | 47 -> Some 27                 (* ctrl+[ -> ESC *)
  | 48 -> Some 29                 (* ctrl+] -> GS *)
  | 49 -> Some 28                 (* ctrl+\ -> FS *)
  | 53 -> Some 30                 (* ctrl+` -> RS *)
  | 44 -> Some 0                  (* ctrl+space -> NUL *)
  | _ -> None

let arrow appcode modsq letter =
  if modsq = 1 then if appcode then csi "\x1bO%c" letter
                  else csi "\x1b[%c" letter
  else csi "\x1b[1;%d%c" modsq letter

let tilde modsq code = csi "\x1b[%d;%d~" code modsq

let fkey_seq scancode =
  match scancode with
  | 58 -> Some "P" | 59 -> Some "Q" | 60 -> Some "R" | 61 -> Some "S"
  | 62 -> Some "15" | 63 -> Some "17" | 64 -> Some "18" | 65 -> Some "19"
  | 66 -> Some "20" | 67 -> Some "21" | 68 -> Some "23" | 69 -> Some "24"
  | _ -> None

(* Key_down (no repeat — the caller filters) -> bytes, or None when the
   key does not map (it may still produce a Text_input event). *)
let key_bytes ~appcursor k (m : mods) =
  let mn = modn m in
  let esc_prefix s = if m.alt || m.meta then "\x1b" ^ s else s in
  match k with
  | Return -> Some (esc_prefix "\r")
  | Escape -> Some "\x1b"
  | Backspace ->
    Some (if m.ctrl then "\x08" else esc_prefix "\x7f")
  | Delete -> Some (tilde mn 3)
  | Tab -> Some (if m.shift then "\x1b[Z" else esc_prefix "\t")
  | Space ->
    if m.ctrl then Some "\x00" else Some (esc_prefix " ")
  | Arrow_up -> Some (arrow appcursor mn 'A')
  | Arrow_down -> Some (arrow appcursor mn 'B')
  | Arrow_right -> Some (arrow appcursor mn 'C')
  | Arrow_left -> Some (arrow appcursor mn 'D')
  | Home ->
    Some (if mn = 1 then (if appcursor then "\x1bOH" else "\x1b[H")
          else csi "\x1b[1;%dH" mn)
  | End ->
    Some (if mn = 1 then (if appcursor then "\x1bOF" else "\x1b[F")
          else csi "\x1b[1;%dF" mn)
  | Page_up -> Some (tilde mn 5)
  | Page_down -> Some (tilde mn 6)
  | Other sc ->
    (match fkey_seq sc with
     | Some code ->
       Some (if String.length code = 1
             then (if mn = 1 then csi "\x1bO%s" code
                   else csi "\x1b[1;%d%s" mn code)
             else tilde mn (int_of_string code))
     | None ->
       (match sc, m.ctrl with
        | 73, _ -> Some (tilde mn 2)              (* Insert *)
        | _, true -> (
          match ctrl_byte_of_scancode sc with
          | Some b ->
            let s = String.make 1 (Char.chr b) in
            Some (if m.alt || m.meta then "\x1b" ^ s else s)
          | None -> None)
        | _, false -> None))

(* Committed text (Text_input/Paste payload) goes through verbatim with
   an ESC prefix when alt/meta is held. *)
let text_bytes ?(alt = false) s =
  if s = "" then "" else if alt then "\x1b" ^ s else s

let paste_bytes ~bracketed s =
  if bracketed then "\x1b[200~" ^ s ^ "\x1b[201~" else s

let focus_bytes ~inside = if inside then "\x1b[I" else "\x1b[O"

(* ------------------------------------------------------------------ *)
(* Mouse reporting *)

type mouse_ev =
  | Btn of int          (* press; 0 left, 1 middle, 2 right *)
  | Release             (* button release *)
  | Drag of int         (* motion with a button held *)
  | Wheel of int        (* 64 up, 65 down, 66 left, 67 right *)

let mouse_bytes ~fmt ~x ~y (m : mods) ev =
  let base =
    match ev with
    | Btn b -> b | Release -> 3 | Drag b -> 32 + b | Wheel w -> w
  in
  let b =
    base lor (if m.shift then 4 else 0)
        lor (if m.alt || m.meta then 8 else 0)
        lor (if m.ctrl then 16 else 0)
  in
  match fmt with
  | 2 -> (* SGR 1006: press/move M, release m *)
    let fin = match ev with Release -> 'm' | _ -> 'M' in
    Some (csi "\x1b[<%d;%d;%d%c" b (x + 1) (y + 1) fin)
  | 3 -> (* 1016: coordinates in pixels — caller passes cell coords so
            this path multiplies by the cell size outside; here we take
            cell units and the widget scales before calling *)
    None
  | _ -> (* X10/utf8-extend: three offset bytes *)
    if x > 223 || y > 223 then None
    else
      let s = Bytes.create 6 in
      Bytes.set s 0 '\x1b'; Bytes.set s 1 '['; Bytes.set s 2 'M';
      Bytes.set s 3 (Char.chr (32 + b));
      Bytes.set s 4 (Char.chr (32 + x + 1));
      Bytes.set s 5 (Char.chr (32 + y + 1));
      Some (Bytes.unsafe_to_string s)
