(** Controllable application clock.

    Time is a float in milliseconds and moves only when someone moves it:
    the host calls {!tick} with its wall clock when a wakeup it scheduled
    from {!next_delay} fires, and tests or agents call {!advance}. Timers
    fire in deadline order, ties in scheduling order, with {!now} set to
    each timer's deadline while it runs, so a run is reproducible no matter
    how late the host wakes up.

    {!pause} detaches the clock from host ticks so a driver can step time
    without racing the host; {!resume} reattaches it at the clock's current
    time instead of jumping to the host's. *)

type t
type timer

(** [create ?start ()] is a running clock reading [start] (default [0.])
    until the first host tick. *)
val create : ?start:float -> unit -> t

val now : t -> float

(** [after clock delay action] runs [action] once, [delay] ms from now.
    Raises [Invalid_argument] for a negative or non-finite delay. *)
val after : t -> float -> (unit -> unit) -> timer

(** [every clock interval action] runs [action] each [interval] ms,
    starting one interval from now. Raises [Invalid_argument] unless
    [interval] is positive and finite. *)
val every : t -> float -> (unit -> unit) -> timer

(** [cancel timer] stops a pending timer; idempotent. *)
val cancel : timer -> unit

(** [active timer] is [true] until a one-shot timer fires or any timer is
    cancelled. *)
val active : timer -> bool

(** [subscription timer] cancels [timer] when disposed, so a
    [Signal.scope] can own it. *)
val subscription : timer -> Signal.subscription

(** Number of pending timers. *)
val pending : t -> int

(** [next_delay clock] is how long the host should wait before its next
    {!tick}: [Some 0.] when a timer is already due, [None] when nothing is
    pending or the clock is paused. *)
val next_delay : t -> float option

(** [tick clock ~now] maps the host clock [now] onto the clock and fires
    every timer that became due. The first tick after {!create} or
    {!resume} anchors the mapping at the clock's current time and fires
    only timers already due. Ignored while paused; a host clock
    that steps backwards never moves the clock back. Returns the number of
    timers fired. *)
val tick : t -> now:float -> int

(** [advance clock ms] moves the clock forward by [ms] whether or not it
    is paused, firing every timer that falls due on the way, including
    timers those timers schedule. Host ticks keep their mapping, so a
    running clock does not fire the same window twice. Returns the number
    of timers fired. Raises [Invalid_argument] for a negative or
    non-finite [ms] or when called from a timer action. *)
val advance : t -> float -> int

(** [settle ?limit clock] advances to each next deadline until no timer is
    pending and returns the number fired. Raises [Failure] once more than
    [limit] (default [10_000]) timers fire, which also catches a repeating
    timer that keeps the clock from settling. *)
val settle : ?limit:int -> t -> int

val pause : t -> unit
val resume : t -> unit
val paused : t -> bool
