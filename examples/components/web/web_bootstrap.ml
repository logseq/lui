let show_error host message =
  Webapi.Dom.Element.setTextContent host message;
  Webapi.Dom.Element.setAttribute "data-error" "true" host

let () =
  match Webapi.Dom.Document.querySelector "#app" Webapi.Dom.document with
  | None -> ()
  | Some host -> (
      try
        ignore
          (Lui_components_web.components_web_main_main host
             Lui_web_media.request_camera Lui_web_media.stop_camera)
      with error -> show_error host (Printexc.to_string error))
