val request_camera :
  Webapi.Dom.Document.t ->
  Webapi.Dom.Element.t ->
  string ->
  (unit -> unit) ->
  (unit -> unit) ->
  unit

val stop_camera : Webapi.Dom.Element.t -> unit
