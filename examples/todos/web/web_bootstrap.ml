let show_error host message =
  Webapi.Dom.Element.setTextContent host message;
  Webapi.Dom.Element.setAttribute "data-error" "true" host

let () =
  Web_dialog.install ();
  match Webapi.Dom.Document.querySelector "#app" Webapi.Dom.document with
  | None -> ()
  | Some host -> (
      try ignore (Lui_web.todos_web_main_main host)
      with error -> show_error host (Printexc.to_string error))
