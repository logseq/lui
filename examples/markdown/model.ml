(* Markdown editor model: the document lives here; the native editing
   surface reports text/caret/path changes as extension events. *)

type t = {
  text : string;
  caret : int;
  path : string;
}

type action =
  | TextChanged of string * int
  | CursorMoved of int
  | PathChanged of string

let starter_document =
  "# LUI Markdown\n\n\
   A *seamless* editor — the document **is** the preview.\n\n\
   ## Highlights\n\n\
   - Type `## `, `**bold**`, `*italic*`, `~~strike~~`, `==mark==`, `code` \
   and watch it render\n\
   - Lists continue on `Return`; `Tab` / `Shift-Tab` indent\n\
   - `Cmd-B` `Cmd-I` `Cmd-E` `Cmd-K` wrap the selection\n\n\
   > Blocks get a live quote bar, fenced code a panel,\n\
   > and syntax markers fade when you leave the line.\n\n\
   ```\n\
   fenced { code: block }\n\
   ```\n\n\
   | Col | Rendered |\n\
   | --- | --- |\n\
   | 1   | live   |\n\n\
   ---\n\n\
   $E = mc^2$\n"

let initial = { text = starter_document; caret = 0; path = "" }

let update model action =
  match action with
  | TextChanged (text, caret) ->
    if text = model.text then { model with caret }
    else { model with text; caret }
  | CursorMoved caret ->
    if caret = model.caret then model else { model with caret }
  | PathChanged path ->
    if path = model.path then model else { model with path }

let text model = model.text

let is_word_char = function
  | '0' .. '9' | 'a' .. 'z' | 'A' .. 'Z' | '\128' .. '\255' -> true
  | _ -> false

(* Words are maximal runs that contain at least one word character, so
   markdown punctuation ("**", "---", "|") never inflates the count. *)
let word_count text =
  let count = ref 0 in
  let in_word = ref false in
  String.iter
    (fun c ->
       if is_word_char c then begin
         if not !in_word then incr count;
         in_word := true
       end
       else in_word := false)
    text;
  !count

let filename model =
  match String.rindex_opt model.path '/' with
  | Some index when index + 1 < String.length model.path ->
    String.sub model.path (index + 1)
      (String.length model.path - index - 1)
  | _ ->
    if model.path = "" then "untitled.md"
    else model.path

(* caret is a UTF-16 offset reported by the host; line/col tracking only
   needs newline counting so the unit skew never matters for ASCII. *)
let line_and_column model =
  let prefix = String.sub model.text 0 (min model.caret (String.length model.text)) in
  let line = ref 1 and column = ref 1 in
  String.iter
    (fun c ->
       if c = '\n' then begin
         incr line;
         column := 1
       end
       else incr column)
    prefix;
  (!line, !column)

let status_line model =
  let line, column = line_and_column model in
  let words = word_count model.text in
  Printf.sprintf "Ln %d, Col %d · %d word%s · %s" line column words
    (if words = 1 then "" else "s")
    (filename model)
