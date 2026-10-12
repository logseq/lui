(** Shared-model multi-window applications: one signal scheduler, one
    reducer model and one shared payload observed by any number of
    window surfaces.

    Each surface owns a UI scope, a [Lui_runtime] retained tree and a
    [Lui_protocol.backend] — the presentation pipeline is per window.
    The model, the scheduler and the ['shared] payload (database
    handles, decoded-resource caches, registries) live once on the
    application. An edit dispatched through any surface reduces into
    the shared model; the next {!flush} publishes it to every open
    window, while focus, selection, scroll and component state stay
    inside each surface's own scope and backend.

    Like {!Lui_runtime}, the application is single-threaded: the same
    domain that flushes must dispatch events and open or close
    windows. *)

(** The shared application: scheduler + model + shared payload + the
    registry of open surfaces. *)
type ('model, 'action, 'shared) t

(** One window's view of the shared model. *)
type ('model, 'action, 'shared) surface

(** A view mounts a window's UI. It receives the surface being opened
    (per-window branching and access to {!surface_application}), that
    surface's UI context, the shared model signal and the shared
    action sender — the same shape as a {!Lui_app} view plus the
    surface. *)
type ('model, 'action, 'shared) view =
  ('model, 'action, 'shared) surface ->
  Lui_ui.ui_context ->
  'model Signal.signal ->
  ('action -> bool) ->
  Lui_elements.t

(** [create ?registry ~shared initial_model reducer view] builds an
    application with one scheduler and one model state. No window is
    opened yet; {!open_window} mounts [view] per backend. *)
val create :
  ?registry:Lui_extension.extension_registry ->
  shared:'shared ->
  'model ->
  ('model -> 'action -> 'model) ->
  ('model, 'action, 'shared) view ->
  ('model, 'action, 'shared) t

val shared : ('model, 'action, 'shared) t -> 'shared
val scheduler : ('model, 'action, 'shared) t -> Signal.scheduler
val model : ('model, 'action, 'shared) t -> 'model

(** The signal every surface observes — the same instance passed to
    each mounted view. *)
val model_signal : ('model, 'action, 'shared) t -> 'model Signal.signal

(** [send t action] reduces [action] into the shared model. Returns
    [false] once the application is disposed; the update publishes to
    every open surface on the next {!flush}. *)
val send : ('model, 'action, 'shared) t -> 'action -> bool

(** [open_window ?view t backend] mounts a surface on [backend]:
    a fresh [Lui_runtime], a child scope of the application's, and the
    view (the application's own, or the [?view] override for a
    different window onto the same model). The surface's scope is
    mounted before returning — the window is live. Node ids are
    per-surface: the same numeric id may exist in every window and
    means a different node in each.

    Raises [Invalid_argument] when [t] is not running. *)
val open_window :
  ?view:('model, 'action, 'shared) view ->
  ('model, 'action, 'shared) t ->
  Lui_protocol.backend ->
  ('model, 'action, 'shared) surface

(** [close_window surface] unmounts the surface: its scope is
    disposed (dynamic branches, subscriptions and per-window state
    die with it), its subtree is dropped and a final batch flushes
    those drops to its backend. Other surfaces keep running. Returns
    [false] when the surface was already closed. *)
val close_window : ('model, 'action, 'shared) surface -> bool

(** Open surfaces in open order. *)
val surfaces :
  ('model, 'action, 'shared) t -> ('model, 'action, 'shared) surface list

val surface_count : ('model, 'action, 'shared) t -> int
val surface_id : ('model, 'action, 'shared) surface -> int

val surface_application :
  ('model, 'action, 'shared) surface -> ('model, 'action, 'shared) t

val surface_runtime :
  ('model, 'action, 'shared) surface -> Lui_runtime.application

val surface_context :
  ('model, 'action, 'shared) surface -> Lui_ui.ui_context

val surface_root : ('model, 'action, 'shared) surface -> int
val surface_backend :
  ('model, 'action, 'shared) surface -> Lui_protocol.backend
val surface_closed : ('model, 'action, 'shared) surface -> bool

(** [dispatch surface event] delivers a host event (press, text
    change, …) to the surface it occurred in. Node ids resolve against
    that surface's runtime only. Returns [false] on a closed surface
    or a disposed application. Handler effects run on the next flush,
    as in {!Lui_app.dispatch_event}. *)
val dispatch :
  ('model, 'action, 'shared) surface -> Lui_protocol.event -> bool

(** Flush one surface: stabilize the shared scheduler once (which also
    recomputes every other surface's dirty view computations) and emit
    this surface's pending batch. Per-window tick loops call this. *)
val flush_surface : ('model, 'action, 'shared) surface -> bool

(** Flush every open surface in open order. The first flush stabilizes
    the shared scheduler; each surface then emits its own batch. *)
val flush : ('model, 'action, 'shared) t -> bool

(** Theme props fan out to every surface's root node, so theme changes
    reach all windows with one call. *)
val set_theme :
  ('model, 'action, 'shared) t ->
  (string * Lui_ui.theme_token_value) list ->
  unit

val set_theme_mode :
  ('model, 'action, 'shared) t -> Lui_ui.theme_mode -> unit

(** [dispose t] closes every open surface (each flushes its drops to
    its own backend), disposes the application scope and marks the
    application disposed. {!send} and {!open_window} stop working;
    {!dispose} is idempotent. *)
val dispose : ('model, 'action, 'shared) t -> bool

val disposed : ('model, 'action, 'shared) t -> bool
