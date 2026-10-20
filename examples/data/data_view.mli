module Edn = Melange_edn

type t

val compile : actions:string list -> string -> (t, string) result

val render :
  t ->
  model:'model Signal.signal ->
  project:('model -> Edn.any) ->
  dispatch:(string -> Edn.any list -> Lui_protocol.event -> unit) ->
  Lui_elements.t
