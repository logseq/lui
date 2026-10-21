(** Attachment presentation: composer-strip cards and in-message blocks.
    Files stay host-owned — the library renders descriptors only. *)

open Lui_elements

val chip :
  ?disabled:bool ->
  ?status:string ->
  Model.attachment ->
  on_remove:(Lui_protocol.event -> unit) option ->
  unit -> t
(** Composer-strip card: a 120pt image/document preview. With
    [on_remove] an accessible removal control is shown (draft context);
    without it the card is a static preview (sent-message context). *)

val view : Model.attachment -> t
(** In-message block: image descriptors render from [path]/[url], other
    media types render a labelled file chip with name and size. *)
