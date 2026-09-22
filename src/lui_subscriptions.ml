(* Subscription coordinator: reconciles desired subscriptions against the
   active set, keeping matching fingerprints mounted. *)

type 'dispatch subscription_spec = {
  subscription_key : string;
  subscription_fingerprint : string;
  start_subscription : 'dispatch -> Signal.subscription;
}

type active_subscription = {
  active_subscription_fingerprint : string;
  active_subscription_value : Signal.subscription;
}

type 'dispatch subscription_coordinator = {
  subscription_dispatch : 'dispatch;
  active_subscriptions : (string, active_subscription) Hashtbl.t;
  subscription_completed_generation : int ref;
}

type reconcile_status =
  | SubscriptionsStale of int
  | SubscriptionsRejected of int * string
  | SubscriptionsUnchanged of int
  | SubscriptionsApplied of int

type prepare_result =
  | SubscriptionsPrepareRejected of string
  | SubscriptionsPrepared of (string, active_subscription) Hashtbl.t

let create dispatch =
  {
    subscription_dispatch = dispatch;
    active_subscriptions = Hashtbl.create 16;
    subscription_completed_generation = ref 0;
  }

let reject coordinator generation message =
  coordinator.subscription_completed_generation := generation;
  SubscriptionsRejected (generation, message)

let validate_unique_keys specs =
  let rec loop specs seen =
    match specs with
    | [] -> None
    | spec :: rest ->
      let key = spec.subscription_key in
      if List.mem key seen then Some ("duplicate subscription key " ^ key)
      else loop rest (key :: seen)
  in
  loop specs []

let same_active active spec =
  active.active_subscription_fingerprint = spec.subscription_fingerprint

let unchanged active specs =
  List.length specs = Hashtbl.length active
  && List.for_all
       (fun spec ->
          match Hashtbl.find_opt active spec.subscription_key with
          | Some current -> same_active current spec
          | None -> false)
       specs

let dispose_started started =
  List.iter Signal.dispose_subscription !started

let build_desired active specs dispatch =
  let started = ref [] in
  try
    let desired = Hashtbl.create 16 in
    List.iter
      (fun spec ->
         let key = spec.subscription_key in
         match Hashtbl.find_opt active key with
         | Some current ->
           if same_active current spec then
             Hashtbl.replace desired key current
           else begin
             let subscription =
               spec.start_subscription dispatch
             in
             started := subscription :: !started;
             Hashtbl.replace desired key
               {
                 active_subscription_fingerprint =
                   spec.subscription_fingerprint;
                 active_subscription_value = subscription;
               }
           end
         | None ->
           let subscription = spec.start_subscription dispatch in
           started := subscription :: !started;
           Hashtbl.replace desired key
             {
               active_subscription_fingerprint =
                 spec.subscription_fingerprint;
               active_subscription_value = subscription;
             })
      specs;
    SubscriptionsPrepared desired
  with Invalid_argument message ->
    dispose_started started;
    SubscriptionsPrepareRejected message

let reconcile coordinator generation specs =
  let completed = !(coordinator.subscription_completed_generation) in
  if generation <= completed then SubscriptionsStale generation
  else
    match validate_unique_keys specs with
    | Some message -> reject coordinator generation message
    | None ->
      let active = coordinator.active_subscriptions in
      if unchanged active specs then begin
        coordinator.subscription_completed_generation := generation;
        SubscriptionsUnchanged generation
      end
      else
        match
          build_desired active specs coordinator.subscription_dispatch
        with
        | SubscriptionsPrepareRejected message ->
          reject coordinator generation message
        | SubscriptionsPrepared desired ->
          Hashtbl.iter
            (fun key current ->
               match Hashtbl.find_opt desired key with
               | Some replacement ->
                 if
                   current.active_subscription_fingerprint
                   <> replacement.active_subscription_fingerprint
                 then
                   Signal.dispose_subscription
                     current.active_subscription_value
               | None ->
                 Signal.dispose_subscription
                   current.active_subscription_value)
            active;
          Hashtbl.reset active;
          Hashtbl.iter (Hashtbl.replace active) desired;
          coordinator.subscription_completed_generation := generation;
          SubscriptionsApplied generation

let dispose coordinator =
  Hashtbl.iter
    (fun _key active ->
       Signal.dispose_subscription active.active_subscription_value)
    coordinator.active_subscriptions;
  Hashtbl.reset coordinator.active_subscriptions

let count coordinator = Hashtbl.length coordinator.active_subscriptions
