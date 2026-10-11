(** Plugin registry for the native backend.

    A plugin is a named bundle of JSON-in/JSON-out methods plus
    lifecycle hooks. Each plugin is bound under the canonical service
    name ["plugin:<name>"], so a plugin named ["fetch"] answers
    [call ~service:"plugin:fetch" ~method_:"request" payload].

    Registry semantics:

    - [use] validates every descriptor up front (name shape, duplicates
      inside the batch, clashes with already-registered names), then
      runs each plugin's [setup] in list order and binds it once setup
      succeeds. If a [setup] fails, the plugins that call registered in
      this [use] are torn down in reverse order and unbound again;
      plugins bound by earlier [use] calls are unaffected.
    - [use] is idempotent for the same descriptor: re-registering the
      exact same [t] value under its name is a no-op, while binding a
      different descriptor under an already-used name is an error.
    - [call] accepts the canonical ["plugin:<name>"] form and, for
      convenience, the bare plugin name; lookup is case-insensitive
      because valid plugin names are lowercase by construction.
    - The registry is guarded by a mutex, which is all the
      synchronization single-domain callers need; handlers run outside
      the lock so a plugin may reenter [call] safely. *)

type handler = string -> (string, string) result
(** A method handler: JSON argument string in, JSON result string (or
    an error message) out. *)

type t = {
  name : string;
  (** Lowercase letters, digits and hyphens; must start with a letter.
      The name ["lui"] is reserved for the runtime itself. *)
  services : (string * handler) list;
  (** Method name -> handler. Method names are matched exactly. *)
  setup : unit -> (unit, string) result;
  (** Runs once when the plugin is bound by [use]. *)
  teardown : (unit -> unit) option;
  (** Runs when the plugin is unbound (failed [use] unwind or
      {!reset}). *)
}

val v :
  ?setup:(unit -> (unit, string) result) ->
  ?teardown:(unit -> unit) ->
  string -> (string * handler) list -> t
(** [v name services] is a plugin descriptor; absent hooks default to
    a no-op setup and no teardown. *)

val use : t list -> (unit, string) result
(** Validate and bind plugins. See the registry semantics above. *)

val call :
  service:string -> method_:string -> string -> (string, string) result
(** Dispatch [payload] to [method_] of the plugin bound under
    [service]. Errors are returned for an unbound service, an unknown
    method, or a handler that raised. *)

val service_name : t -> string
(** The canonical ["plugin:<name>"] service name of a descriptor. *)

val names : unit -> string list
(** Canonical service names of all bound plugins, in registration
    order. *)

val mem : service:string -> bool
(** Whether [service] resolves to a bound plugin. *)

val reset : unit -> unit
(** Run every bound plugin's [teardown] in reverse registration order
    and clear the registry. Mainly for shutdown and test isolation. *)
