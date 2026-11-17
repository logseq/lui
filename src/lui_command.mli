(** Portable command descriptions shared by native OCaml and Melange clients. *)
module Name : sig
  type t
  val of_string : string -> (t, string) result
  val to_string : t -> string
end

module Codec : sig
  type 'a t
  val make : encode:('a -> string) -> decode:(string -> ('a, string) result) -> 'a t
  val encode : 'a t -> 'a -> string
  val decode : 'a t -> string -> ('a, string) result
  val unit : unit t
  val string : string t
  val bool : bool t
  val int32 : int32 t
end

type code =
  | Unavailable | Unknown_command | Invalid_arguments | Command_failed
  | Internal_error | Busy | Closed | Timed_out | Invalid_response

type error = { code : code; message : string }
val error : code -> string -> error
val code_name : code -> string
val code_of_name : string -> code

type ('request, 'response) t
val v : name:Name.t -> request:'a Codec.t -> response:'b Codec.t -> ('a, 'b) t
val name : ('a, 'b) t -> Name.t
val encode_request : ('a, 'b) t -> 'a -> string
val decode_request : ('a, 'b) t -> string -> ('a, string) result
val encode_response : ('a, 'b) t -> 'b -> string
val decode_response : ('a, 'b) t -> string -> ('b, string) result
