module Name = struct
  type t = string

  let of_string name =
    let valid_segment segment =
      String.length segment > 0
      && (match segment.[0] with 'a' .. 'z' -> true | _ -> false)
      && String.for_all (function 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false) segment
    in
    if String.length name > 128 || String.starts_with ~prefix:"lui." name
       || not (List.for_all valid_segment (String.split_on_char '.' name))
    then Error "Command names must use lowercase identifier segments; lui.* is reserved"
    else Ok name

  let to_string name = name
end

module Codec = struct
  type 'a t = { encode : 'a -> string; decode : string -> ('a, string) result }
  let make ~encode ~decode = { encode; decode }
  let encode codec value = codec.encode value
  let decode codec value = codec.decode value
  let unit = make ~encode:(fun () -> "") ~decode:(function "" -> Ok () | _ -> Error "Expected unit")
  let string = make ~encode:Fun.id ~decode:(fun value -> Ok value)
  let bool = make ~encode:string_of_bool ~decode:(function
    | "true" -> Ok true | "false" -> Ok false | _ -> Error "Expected a boolean")
  let int32 = make ~encode:Int32.to_string ~decode:(fun value ->
    match Int32.of_string_opt value with
    | Some number when Int32.to_string number = value -> Ok number
    | Some _ | None -> Error "Expected a canonical signed 32-bit integer")
end

type code =
  | Unavailable | Unknown_command | Invalid_arguments | Command_failed
  | Internal_error | Busy | Closed | Timed_out | Invalid_response

type error = { code : code; message : string }
let error code message = { code; message }

let code_name = function
  | Unavailable -> "unavailable" | Unknown_command -> "unknown_command"
  | Invalid_arguments -> "invalid_arguments" | Command_failed -> "command_failed"
  | Internal_error -> "internal_error" | Busy -> "busy" | Closed -> "closed"
  | Timed_out -> "timed_out" | Invalid_response -> "invalid_response"

let code_of_name = function
  | "unavailable" -> Unavailable | "unknown_command" -> Unknown_command
  | "invalid_arguments" -> Invalid_arguments | "command_failed" -> Command_failed
  | "internal_error" -> Internal_error | "busy" -> Busy | "closed" -> Closed
  | "timed_out" -> Timed_out | "invalid_response" -> Invalid_response
  | _ -> Invalid_response

type ('a, 'b) t = { name : Name.t; request : 'a Codec.t; response : 'b Codec.t }
let v ~name ~request ~response = { name; request; response }
let name command = command.name
let encode_request command = Codec.encode command.request
let decode_request command = Codec.decode command.request
let encode_response command = Codec.encode command.response
let decode_response command = Codec.decode command.response
