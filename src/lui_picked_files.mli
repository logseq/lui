type file = { path : string; name : string; content_type : string }
(** Ordered results from {!Lui_elements.file_picker}. Import or copy every
    accepted file before acknowledging the request with [completion]. *)

type t = {
  request : Lui_elements.file_picker_token;
  files : file list;
  failures : int;
}

val decode : string -> (t, string) result
(** Decode the complete batch, preserving selection order. Malformed entries
    count as failures without discarding valid siblings. An invalid envelope
    returns [Error]; cancellation is delivered through [Dismiss], not here. *)
