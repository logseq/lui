(* ns lui.subscriptions *)

type subscription_reload_status =
  | SubscriptionsApplied of int
  | SubscriptionsUnchanged of int
  | SubscriptionsRejected of int * string
  | SubscriptionsStale of int

type 'message subscription_spec = { subscription_key : string ; subscription_fingerprint : string ; start_subscription : ('message -> bool) -> subscription }

type active_subscription = { active_subscription_fingerprint : string ; active_subscription_value : subscription }

type subscription_build_result =
  | SubscriptionsPrepared of (string, active_subscription) Lg_runtime.Runtime_map.t
  | SubscriptionsPrepareRejected of string

type 'message subscription_coordinator = { subscription_dispatch : 'message -> bool ; active_subscriptions : (string, active_subscription) Lg_runtime.Runtime_map.t ref ; subscription_completed_generation : int ref }

val create : ('message -> bool) -> 'message subscription_coordinator

val reject_bang : 'message subscription_coordinator -> int -> string -> subscription_reload_status

val validate_unique_keys_bang : 'message subscription_spec Rrbvec.t -> string option

val same_active_ : active_subscription -> 'message subscription_spec -> bool

val unchanged_ : (string, active_subscription) Lg_runtime.Runtime_map.t -> 'message subscription_spec Rrbvec.t -> bool

val dispose_started_bang : subscription Rrbvec.t ref -> bool

val build_desired : (string, active_subscription) Lg_runtime.Runtime_map.t -> 'message subscription_spec Rrbvec.t -> ('message -> bool) -> subscription_build_result

val reconcile_bang : 'message subscription_coordinator -> int -> 'message subscription_spec Rrbvec.t -> subscription_reload_status

val dispose_bang : 'message subscription_coordinator -> bool

val count : 'message subscription_coordinator -> int

