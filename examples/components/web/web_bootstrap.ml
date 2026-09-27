let show_error host message =
  Webapi.Dom.Element.setTextContent host message;
  Webapi.Dom.Element.setAttribute "data-error" "true" host

let report host error =
  match Js.Exn.asJsExn error with
  | Some js_error -> (
      Js.Console.error js_error;
      match Js.Exn.stack js_error with
      | Some stack -> show_error host stack
      | None -> show_error host (Printexc.to_string error))
  | None -> show_error host (Printexc.to_string error)

let () =
  match Webapi.Dom.Document.querySelector "#app" Webapi.Dom.document with
  | None -> ()
  | Some host -> (
      try ignore (Web_main.main host) with error -> report host error)
