(** Opt-in crash reporting and renderer-loss recovery for the native
    backend.

    {b Crash reporter.} [install ~app_name ~renderer ()] enables
    [Printexc.record_backtrace] and returns a reporter handle. Fatal
    signal handlers (SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE) are
    {b opt-in}: pass [~enable_signals:true] or set [LUI_CRASH_SIGNALS=1].
    Without that, callers can still use {!write_crash_report} /
    {!log} for caught exceptions. On a handled fatal signal the handler
    writes a crash file — timestamp, app and renderer identity,
    OS/OCaml versions, the OCaml backtrace and the last lifecycle lines
    recorded through {!log} — then re-raises the signal so the process
    still dies with its real cause (core dumps and debuggers are
    unaffected). The next launch picks the report up through
    {!pending_crash_report}; {!mark_report_handled} clears it once the
    app has shown its relaunch UX or uploaded it.

    The handler is {b best-effort only}: OCaml code is not
    async-signal-safe, so the file write can hang or double-fault — it
    is wrapped so the original signal always wins, but this must not be
    treated as reliable crash telemetry. The report path is computed
    once at install time and the ring buffer is preallocated, keeping
    the work done inside the handler as small as possible.

    {b Recovery seam.} {!Recovery} is the policy half of renderer-loss
    recovery: the platform ladder (macOS Metal>GL>CPU, Windows
    D3D11>GL>CPU, Linux Vulkan>GL>CPU) previously fell back only at
    creation time. Drivers keep a [Recovery.t] next to their renderer
    cell; when the active backend reports loss (SDL reset events, a
    device-removed error, a render exception) [lost] hands back the
    next rung to create. The scene store is untouched, so the next
    repaint re-uploads a full scene to the new backend. *)

type t
(** A crash-reporter installation. *)

val install :
  ?dir:string -> ?enable_signals:bool -> app_name:string -> renderer:string ->
  unit -> t
(** [install ~app_name ~renderer ()] returns the reporter handle.
    Signal handlers install only when [~enable_signals] is true or
    [LUI_CRASH_SIGNALS=1]. [dir] is where crash files are written
    (default: a per-app directory under the OS temp dir). *)

val set_renderer : t -> string -> unit
(** Update the renderer name stamped into future crash files and append
    the change to the lifecycle log. *)

val log : t -> string -> unit
(** Append a lifecycle line to the preallocated ring buffer (last 64
    lines, each truncated to 240 chars, kept with a UTC timestamp). *)

val write_crash_report : t -> signal:string -> backtrace:string -> string option
(** Write the crash file now; returns its path, or [None] if writing
    failed. Exposed so callers can also report caught OCaml exceptions
    through the same path the signal handler uses. *)

val report_path : t -> string
(** The fixed path this reporter's crash file is written to. *)

val pending_crash_report : ?dir:string -> app_name:string -> unit -> string option
(** The contents of the crash file left by a previous run of
    [app_name], if one exists. *)

val mark_report_handled : ?dir:string -> app_name:string -> unit -> unit
(** Delete a previous run's crash file once the app has surfaced it. *)

module Recovery : sig
  type t
  (** Ladder state: the rung names, best first. *)

  val create : string list -> t
  (** [create rungs] starts on the first rung. The list should end at
      the always-available rung (the CPU or no-op renderer). *)

  val current : t -> string
  val index : t -> int
  val ladder : t -> string list

  val lost : t -> reason:string -> string option
  (** The active backend was lost: [Some name] of the next rung to
      create, [None] when the ladder is exhausted. *)

  val demotions : t -> int
  val history : t -> (int * string * string) list
  (** Demotion log: [(time index, from rung, reason)] — oldest first. *)

  val exhausted : t -> bool
end
