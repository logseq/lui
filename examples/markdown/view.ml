(* Markdown editor view: the extension node carries the document text and
   reports edits back; a status bar shows live stats computed in the model —
   every keystroke round-trips through the OCaml reducer. *)

open Lui_protocol
open Lui_elements

let handle_editor_event send (event : Lui_protocol.event) =
  match event with
  | ExtensionEvent (_, "markdown-editor", name, values) ->
    let string name =
      match String_map.find_opt name values with
      | Some (StringValue value) -> value
      | _ -> ""
    in
    let int name =
      match String_map.find_opt name values with
      | Some (IntValue value) -> value
      | _ -> 0
    in
    (match name with
     | "text-changed" ->
       ignore (send (Model.TextChanged (string "text", int "caret")))
     | "cursor" -> ignore (send (Model.CursorMoved (int "caret")))
     | "path-changed" -> ignore (send (Model.PathChanged (string "path")))
     | _ -> ())
  | _ -> ()

let view _context model_source send : t =
  column ~gap:0
    [
      Extension_schemas.markdown_editor
        ~text:(reactive Model.text model_source)
        ~placeholder:"Start writing…"
        ~on_event:(handle_editor_event send) ();
      separator [];
      status_bar ~value:(reactive Model.status_line model_source) [];
    ]
