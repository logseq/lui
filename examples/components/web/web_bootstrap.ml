let show_error host message =
  Webapi.Dom.Element.setTextContent host message;
  Webapi.Dom.Element.setAttribute "data-error" "true" host

let () =
  Printexc.record_backtrace true;
  match Webapi.Dom.Document.querySelector "#app" Webapi.Dom.document with
  | None -> ()
  | Some host -> (
      try ignore (Web_main.main host)
      with error ->
        show_error host
          (Printexc.to_string error ^ "\n" ^ Printexc.get_backtrace ()))
