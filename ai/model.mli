(** Generic chat transcript model: ordered items with stable identity,
    tool-call cards, attachment descriptors and pure update helpers.

    Hosts own transport and keep these values inside their own model;
    every helper preserves ordering and [id] identity so keyed rendering
    updates the same mounted row while content streams in. *)

type id = string

type kind =
  | User  (** End-user message. *)
  | Assistant  (** Agent reply. *)
  | Thinking  (** Reasoning scratchpad; rendered collapsed. *)
  | Tool_call  (** One tool invocation; [tool] carries the card. *)
  | Notice  (** System/notice line. *)
  | Host of string  (** Custom kind rendered via a host renderer. *)

type delivery =
  [ `sent  (** Server acknowledged. *)
  | `pending  (** Optimistic echo awaiting acknowledgement. *)
  | `uncertain  (** Delivery uncertain; a retry affordance is shown. *)
  ]

type attachment_status = [ `uploading | `ready | `failed ]

(** Host-owned attachment descriptor. [path] is a host-local file used
    for native previews; [url] covers remote images. The library never
    copies, imports or deletes files. *)
type attachment = {
  attachment_id : id;
  name : string;
  media_type : string;
  size : int option;
  status : attachment_status;
  path : string option;
  url : string option;
}

type tool_status =
  [ `pending | `in_progress | `completed | `failed | `unknown ]

(** One tool invocation card. [output_truncated] marks lazy payloads;
    the card then offers a "load full" action. *)
type tool_call = {
  call_id : id;
  title : string;
  tool_kind : string;
  status : tool_status;
  input : string option;
  output : string option;
  output_truncated : bool;
}

type item = {
  id : id;
  kind : kind;
  text : string;
  streaming : bool;  (** More chunks expected; a live indicator shows. *)
  delivery : delivery;
  attachments : attachment list;
  tool : tool_call option;  (** meaningful when [kind = Tool_call] *)
  payload : string option;  (** meaningful when [kind = Host _] *)
  truncated : bool;  (** Host trimmed this item's payload. *)
}

val item : id -> kind -> item
(** Bare item: empty text, [delivery `sent], no attachments. *)

val find : item list -> id -> item option
val upsert : item list -> item -> item list
(** Replace the item with the same [id], else append. *)

val append_text : item list -> id -> string -> item list
(** Append [delta] to [text] of the item with [id] (streaming chunk).
    Missing items are left unchanged — hosts upsert first. *)

val set_delivery : item list -> id -> delivery -> item list

(** Sparse tool-call update merged by [update_id] against [call_id]:
    [None] fields keep the stored value so earlier arguments/results
    are never lost. *)
type tool_update = {
  update_id : id;
  update_title : string option;
  update_kind : string option;
  update_status : tool_status option;
  update_input : string option;
  update_output : string option;
  update_output_truncated : bool option;
}

val update_tool : item list -> tool_update -> item list

(** {1 Transcript rows}

    The transcript groups runs of consecutive [Tool_call] items into one
    collapsible section. [row] is the keyed unit rendered per position;
    group keys derive from the first member so they stay stable while
    the run grows or streams. *)
type row =
  | Single of item
  | Tool_group of item list  (** non-empty *)

val group_rows : group:bool -> item list -> row list
val row_key : row -> string
val group_active : item list -> bool
(** [true] while any member is [`pending] or [`in_progress]. *)

val tool_active : tool_call -> bool
val tool_status_label : tool_status -> string
val is_image : attachment -> bool
val size_label : int -> string
