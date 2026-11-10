(** One agent protocol for every host.

    A request is a flat JSON object naming an [op]; the reply is one JSON
    object with ["ok"]. Hosts only carry request and reply strings: the
    operations, selectors and node lookups are answered here, against the
    runtime's retained tree, so a script that drives one backend drives all
    of them. Selectors use the Drive scenario grammar ([id:N], [kind:name],
    [ext:identifier], [text:needle], [prop:name=value], [prop:name=prefix*],
    conjunctions joined with [&]; a bare number is an id and a bare word is
    a text needle).

    A request the agent cannot satisfy (malformed JSON, unknown op, no
    matching node, an event the node does not handle) is answered with
    [{"ok":false,"error":...}] and changes nothing. An exception raised by
    an application handler while an action runs is not caught: it reaches
    the host as a refused call, exactly like a refused native event. *)

val protocol : string
val version : int

(** Every operation [hello] advertises, in a stable order. *)
val operations : string list

type target = {
  host : string;
  runtime : Lui_runtime.application;
  dispatch : Lui_protocol.event -> unit;
  flush : unit -> unit;
}

(** A target that dispatches through [Lui_app.dispatch_event] and flushes
    after every action and before every query. *)
val app_target : ?host:string -> ('model, 'action) Lui_app.reducer_app -> target

val handle : target -> string -> string
