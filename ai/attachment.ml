open Lui_elements
open Model

let status_label (a : attachment) =
  match a.status with
  | `uploading -> Some "Uploading"
  | `failed -> Some "Failed"
  | `ready -> None

let file_chip (a : attachment) : t =
  let caption =
    match a.size with
    | Some size -> a.media_type ^ " · " ^ size_label size
    | None -> a.media_type
  in
  row ~gap:8 ~cross:`center ~padding:8 ~background:"secondary"
    ~corner_radius:12
    ~accessibility_identifier:("lui-ai-attachment:" ^ a.attachment_id)
    [ icon ~name:`file_text ~width:20 ~height:20 ~foreground:"muted-foreground" []
    ; column ~gap:2
        [ text ~value:a.name ~style_class:"single-line" []
        ; text ~value:caption ~foreground:"muted-foreground"
            ~style_class:"single-line caption" [] ] ]

let view (a : attachment) : t =
  let label = if String.trim a.name = "" then "Attachment" else a.name in
  let base =
    if is_image a then
      match a.path, a.url with
      | Some path, _ ->
          file_image ~path ~fit:`fit ~max_width:240 ~max_height:240
            ~corner_radius:12 ~label:("Attached image " ^ label) []
      | _, Some url ->
          image ~url ~alt:label ~max_width:240 ~max_height:240
            ~corner_radius:12 ~label:("Attached image " ^ label) []
      | None, None -> file_chip a
    else file_chip a
  in
  match status_label a with
  | None -> base
  | Some status ->
      column ~gap:2
        [ base
        ; text ~value:status ~foreground:"muted-foreground"
            ~style_class:"caption" [] ]

let chip ?(disabled = false) ?status (a : attachment) ~on_remove () : t =
  match on_remove with
  | Some on_remove ->
      Lui_element_combine.composer_attachment ~disabled ?status
        ~key:a.attachment_id
        ~path:(Option.value a.path ~default:"")
        ~title:a.name ~file_type:a.media_type ~on_remove ()
  | None -> view a
