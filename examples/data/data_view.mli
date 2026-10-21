module Edn = Melange_edn
module Contract = Data_contract
module Sources = Data_sources

type t

val parse : id:string -> string -> (Sources.document, string) result
val compile_document : contract:Contract.t -> Sources.document -> (t, string) result
val compile_graph : contract:Contract.t -> Sources.graph -> (t, string) result
val compile : contract:Contract.t -> string -> (t, string) result
val compile_files :
  ?cache:Sources.cache -> contract:Contract.t -> load:Sources.loader ->
  entry:string -> unit -> (t, string) result

val render :
  t ->
  model:'model Signal.signal ->
  project:('model -> Edn.any) ->
  dispatch:(string -> Edn.any list -> Lui_protocol.event -> unit) ->
  Lui_elements.t
