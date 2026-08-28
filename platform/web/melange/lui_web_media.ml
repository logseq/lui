type media_devices
type media_stream
type media_stream_track
type facing_mode
type video_constraints
type media_constraints

external media_devices :
  Webapi.Dom.Window.navigator -> media_devices Js.Nullable.t = "mediaDevices"
  [@@mel.get]

external facing_mode : ideal:string -> unit -> facing_mode = "" [@@mel.obj]

external video_constraints :
  facingMode:facing_mode -> unit -> video_constraints = ""
  [@@mel.obj]

external media_constraints :
  audio:bool -> video:video_constraints -> unit -> media_constraints = ""
  [@@mel.obj]

external get_user_media :
  media_devices -> media_constraints -> media_stream Js.Promise.t = "getUserMedia"
  [@@mel.send]

external source_object :
  Webapi.Dom.Element.t -> media_stream Js.Nullable.t = "srcObject"
  [@@mel.get]

external set_source_object :
  Webapi.Dom.Element.t -> media_stream Js.Nullable.t -> unit = "srcObject"
  [@@mel.set]

external tracks : media_stream -> media_stream_track array = "getTracks"
  [@@mel.send]

external stop_track : media_stream_track -> unit = "stop" [@@mel.send]

let stop_camera video =
  (match source_object video |> Js.Nullable.toOption with
  | Some stream -> Array.iter stop_track (tracks stream)
  | None -> ());
  set_source_object video Js.Nullable.null

let request_camera document video facing on_live on_denied =
  let html_document = Webapi.Dom.Document.unsafeAsHtmlDocument document in
  match Webapi.Dom.HtmlDocument.defaultView html_document with
  | None -> on_denied ()
  | Some window -> (
      let navigator = Webapi.Dom.Window.navigator window in
      match media_devices navigator |> Js.Nullable.toOption with
      | None -> on_denied ()
      | Some devices ->
          let constraints =
            media_constraints ~audio:false
              ~video:(
                video_constraints ~facingMode:(facing_mode ~ideal:facing ()) ())
              ()
          in
          get_user_media devices constraints
          |> Js.Promise.then_ (fun stream ->
                 stop_camera video;
                 set_source_object video (Js.Nullable.return stream);
                 on_live ();
                 Js.Promise.resolve ())
          |> Js.Promise.catch (fun _error ->
                 on_denied ();
                 Js.Promise.resolve ())
          |> ignore)
