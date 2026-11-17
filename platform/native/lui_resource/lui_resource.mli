(* Resource lifecycle: owning cache entries for asynchronously loaded
   values (images, fonts, svg documents, network responses, media,
   plugin calls).

   Modelled after GPUI's owning cache entry: every cached value lives
   in a [ResourceEntry] carrying its [key], [generation], [state],
   [owner_scope] and [task]. The rules the whole module enforces:

   - scope dispose cancels the task and drops the entry;
   - a new generation supersedes the old one: {!reload} bumps
     [generation] and cancels the previous in-flight task;
   - a stale asynchronous completion never overwrites a newer entry —
     completions arrive tagged with the generation they loaded for and
     are discarded (the value {!create}'s [~retire] hook releases) when
     the entry has moved on;
   - results are always published on the foreground: workers only push
     into a mutex-guarded mailbox and {!drain} applies them, so the
     entry table and watcher callbacks are single-threaded.

   Ownership: an entry is attached to every {!Signal.scope} that
   {!request}s it; it survives while at least one attached scope is
   alive. Disposing the last attached scope cancels the in-flight task
   (if any), drops the entry and retires a [Ready] value it held.
   [owner_scope] records the scope that started the current
   generation — the one {!reload} was last called with. *)

type key = string

type 'value state =
  | Loading          (* a task for the current generation is in flight *)
  | Ready of 'value  (* the current generation published a value *)
  | Failed of string (* the current generation published an error *)

(* A cancellable handle for one in-flight load. Cancellation is
   cooperative: {!task_cancel} flips [task_cancelled] and runs the
   registered cancel hook; a running loader is expected to poll
   {!task_cancelled} and bail out — its result is discarded at publish
   time either way. *)
type task

val task_cancelled : task -> bool
val task_cancel : task -> unit

(* [task_set_on_cancel t f] registers [f] to run once inside
   {!task_cancel} — for loaders that hold a cancellable primitive
   (a socket, a decoder handle). Best-effort: [f]'s exceptions are
   swallowed. *)
val task_set_on_cancel : task -> (unit -> unit) -> unit

(* The owning cache entry. The plan's [ResourceEntry] record: [key],
   [generation], [state], [owner_scope], [task] — readable through the
   accessors below; the record itself is abstract. *)
type 'value entry

val key : 'value entry -> key
val generation : 'value entry -> int
val state : 'value entry -> 'value state
val owner_scope : 'value entry -> Signal.scope
val task : 'value entry -> task option

(* An executor schedules one closed job. {!spawn} hands the executor a
   [unit -> unit] that runs the load and pushes its completion into the
   cache's mailbox; the executor may run it inline, on a {!Domain}, or
   later — dropping a job is permitted (the cache then stays [Loading]
   until reloaded or dropped). *)
type executor = (unit -> unit) -> unit

(* Runs the job inline, on the caller's thread. The completion still
   goes through the mailbox and needs {!drain} to publish. *)
val executor_immediate : executor

(* Runs each job on a fresh {!Domain}. Loaders' C stubs that release
   the runtime system (e.g. libcurl) run truly in parallel. *)
val executor_domain : executor

(* [executor_queued ()] is [(exec, pump)]: [exec] queues jobs and
   [pump] runs every queued job, returning how many it ran. For tests
   and single-threaded hosts that want deterministic load timing. *)
val executor_queued : unit -> executor * (unit -> int)

type 'value t

(* [create ?executor ?retire ()] is an empty cache. [executor] defaults
   to {!executor_domain}. [retire v] releases a discarded value on the
   foreground — called for stale/cancelled completions, for a [Ready]
   value replaced by a newer publish, and for [Ready] values dropped by
   {!invalidate}/{!clear}/scope dispose; use it to free external
   resources (GPU handles, decoder state). Best-effort: [retire]'s
   exceptions are swallowed. *)
val create :
  ?executor:executor -> ?retire:('value -> unit) -> unit -> 'value t

(* [request c ~scope key ~load] is the entry for [key], loading it with
   [load] when absent:

   - absent: creates a generation-1 [Loading] entry owned by [scope]
     and spawns [load];
   - present: attaches [scope] to the existing entry (sharing a pending
     load and any [Ready] value) — a [Failed] entry is returned as-is;
     {!reload} retries it.

   [load task] is called by the executor, possibly on another domain;
   it must not touch the cache. It should poll [task_cancelled task]
   between expensive phases and bail with [Error "cancelled"] when set.

   [~on_state] watches the entry from [scope]: it runs on the
   foreground (inside {!drain}, or immediately when the entry is
   already published) on every publish until [scope] is disposed or the
   entry is dropped. Raises [Invalid_argument] when [scope] is already
   disposed. *)
val request :
  'value t -> scope:Signal.scope -> ?on_state:('value entry -> unit) ->
  key -> load:(task -> ('value, string) result) -> 'value entry

(* [reload c ~scope key ~load] starts a new generation for [key]:
   cancels the in-flight task (if any), retires a [Ready] value the
   entry held, bumps [generation], sets [owner_scope] to [scope] and
   spawns [load]. Completions the superseded task still deliver are
   discarded at {!drain}. Like {!request} when the key is absent. *)
val reload :
  'value t -> scope:Signal.scope -> ?on_state:('value entry -> unit) ->
  key -> load:(task -> ('value, string) result) -> 'value entry

(* [watch ~scope e f] registers [f] on [e] — same semantics as
   {!request}'s [~on_state]. A watcher does not keep the entry alive:
   when the last owning scope is disposed the entry is dropped and no
   watcher fires. *)
val watch : scope:Signal.scope -> 'value entry -> ('value entry -> unit) -> unit

(* [get c key] is [Some v] when the entry published [Ready v]. *)
val get : 'value t -> key -> 'value option

val entry : 'value t -> key -> 'value entry option
val mem : 'value t -> key -> bool

(* [invalidate c key] drops the entry: cancels the task, retires a
   [Ready] value. In-flight completions for it are discarded later. *)
val invalidate : 'value t -> key -> unit

(* Drops every entry. *)
val clear : 'value t -> unit

val length : 'value t -> int

(* Number of completions sitting in the mailbox, waiting for {!drain}. *)
val pending : 'value t -> int

(* Applies every queued completion on the calling (foreground) thread:
   publishes into entries still [Loading] at the matching generation,
   discards and retires the rest, then runs the watchers. Returns the
   number of completions processed. Call it once per frame/tick — this
   is the "foreground publish". *)
val drain : 'value t -> int

(* Drains every live cache built with {!create}; returns the total
   processed. Lets a host publish all resource kinds in one call. *)
val drain_all : unit -> int

(* Removes [c] from the {!drain_all} registry (a shutdown cache's drain
   thunk is not retained). *)
val unregister : 'value t -> unit
