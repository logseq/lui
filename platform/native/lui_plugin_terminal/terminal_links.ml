(* Link detection inside row text: URLs, filesystem paths and
   file:line[:col] references, following the reference regexes. *)

module G = Terminal_grid

type kind = Url | Path | File_line of int * int (* line, col *)

type hit = { x0 : int; x1 : int; kind : kind; text : string }

(* https?/ftp/file URIs and mailto:. *)
let url_re =
  Str.regexp
    "\\(https?\\|ftp\\|file\\)://[^ \t\r\n\"'<>`\x00-\x1f]+\\|mailto:[^ \t\r\n\"'<>`]+"

(* ~ or . or .. anchored paths, absolute paths with a name char after
   the slash, and file.ext:line[:col]. *)
let path_re =
  Str.regexp
    "\\(~\\|\\.\\.?\\)/[^ \t\r\n\"'<>`|]+\\|/[A-Za-z0-9._~+@%=-][^ \t\r\n\"'<>`|]*\
    \\|[A-Za-z0-9_][A-Za-z0-9_.-]*\\.[A-Za-z0-9][A-Za-z0-9._-]*:[0-9]+\\(:[0-9]+\\)?"

(* Trim characters that cling to a link: trailing punctuation and
   closers whose openers never occurred inside the match. *)
let trim s =
  let n = String.length s in
  let opens = ref 0 and closes = ref 0 in
  String.iter (function
    | '(' | '[' | '{' -> incr opens
    | ')' | ']' | '}' -> incr closes
    | _ -> ()) s;
  let rec last i =
    if i <= 0 then 0
    else
      match s.[i - 1] with
      | '.' | ',' | ';' | ':' | '!' | '?' | '\'' -> last (i - 1)
      | ')' | ']' | '}' ->
        (* strip an unbalanced closer *)
        let opens' = ref 0 and closes' = ref 0 in
        String.iter (function
          | '(' | '[' | '{' -> incr opens'
          | ')' | ']' | '}' -> incr closes'
          | _ -> ()) (String.sub s 0 i);
        if !closes' > !opens' then last (i - 1) else i
      | _ -> i
  in
  String.sub s 0 (last n)

let haspfx p s =
  let n = String.length s and m = String.length p in
  n >= m && String.sub s 0 m = p

let classify s =
  let n = String.length s in
  if haspfx "http://" s || haspfx "https://" s || haspfx "ftp://" s
     || haspfx "file://" s || haspfx "mailto:" s then Url
  else
    match String.index_opt s ':' with
    | Some i ->
      let digit_after j =
        j < n && s.[j] >= '0' && s.[j] <= '9'
      in
      if i > 0 && i + 1 < n && digit_after (i + 1) then begin
        (* file.ext:line[:col] *)
        let rest = String.sub s (i + 1) (n - i - 1) in
        match String.split_on_char ':' rest with
        | l :: c :: _ ->
          (try File_line (int_of_string l, int_of_string c)
           with _ -> File_line (int_of_string l, 0))
        | [l] -> (try File_line (int_of_string l, 0) with _ -> Path)
        | [] -> Path
      end else Path
    | None -> Path

let scan re s =
  let hits = ref [] in
  let pos = ref 0 in
  (try
     while true do
       let i = Str.search_forward re s !pos in
       let m = Str.matched_string s in
       let m' = trim m in
       let x1 = i + String.length m' in
       if x1 > i then
         hits := { x0 = i; x1; kind = classify m'; text = m' } :: !hits;
       pos := max (i + 1) x1
     done
   with Not_found -> ());
  List.rev !hits

let find_in_row s =
  let us = scan url_re s in
  us @ List.filter (fun h ->
      (* path matches that overlap a url hit are dropped *)
      not (List.exists (fun (u : hit) -> h.x0 >= u.x0 && h.x0 < u.x1)
             us))
    (scan path_re s)

let find g ~row =
  let doc_row_idx =
    (* [row] is a viewport row; translate through the view offset *)
    match G.shown_row g row with
    | Some (i, _) -> i
    | None -> -1
  in
  if doc_row_idx < 0 then [] else find_in_row (G.row_text g doc_row_idx)

let at g ~row ~col =
  List.find_opt (fun h -> col >= h.x0 && col < h.x1) (find g ~row)
