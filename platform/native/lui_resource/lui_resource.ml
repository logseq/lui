(* Resource lifecycle: owning cache entries for asynchronously loaded
   values. See the .mli for the rules this enforces. *)

type key = string

type 'value state =
  | Loading
  | Ready of 'value
  | Failed of string

type task = {
  task_cancelled : bool Atomic.t;
  task_cancel_fn : (unit -> unit) option Atomic.t;
}

let task_cancelled t = Atomic.get t.task_cancelled

let task_cancel t =
  if not (Atomic.exchange t.task_cancelled true) then
    match Atomic.get t.task_cancel_fn with
    | Some f -> (try f () with _ -> ())
    | None -> ()

let task_set_on_cancel t f = Atomic.set t.task_cancel_fn (Some f)

type 'value entry = {
  key : key;
  mutable generation : int;
  mutable state : 'value state;
  mutable owner_scope : Signal.scope;
  mutable task : task option;
  (* attached owner scopes, by scope id — the entry lives while the
     table is non-empty *)
  entry_scopes : (int, Signal.scope) Hashtbl.t;
  (* (scope id, scope, callback): scope lets dead watchers be pruned
     at notify time without waiting for the cleanup to run *)
  mutable watchers : (int * Signal.scope * ('value entry -> unit)) list;
}

let key e = e.key
let generation e = e.generation
let state e = e.state
let owner_scope e = e.owner_scope
let task e = e.task

type executor = (unit -> unit) -> unit

let executor_immediate job = job ()
let executor_domain job = ignore (Domain.spawn job)

let executor_queued () =
  let q = Queue.create () in
  let m = Mutex.create () in
  let exec job =
    Mutex.lock m;
    Queue.push job q;
    Mutex.unlock m
  in
  let pump () =
    let rec go n =
      let job =
        Mutex.lock m;
        let j = Queue.take_opt q in
        Mutex.unlock m;
        j
      in
      match job with
      | Some j -> j (); go (n + 1)
      | None -> n
    in
    go 0
  in
  (exec, pump)

type 'value completion = {
  comp_entry : 'value entry;
  comp_generation : int;
  comp_result : ('value, string) result;
}

type 'value t = {
  cache_id : int;
  executor : executor;
  retire : 'value -> unit;
  entries : (key, 'value entry) Hashtbl.t;
  mailbox : 'value completion Queue.t;
  mutex : Mutex.t;
}

(* Every live cache's drain thunk, for [drain_all]. *)
let all_caches : (int * (unit -> int)) list ref = ref []
let last_cache_id = ref 0

let check_scope scope =
  if Signal.scope_is_disposed scope then
    invalid_arg "Lui_resource: scope is disposed"

let drop_entry c e =
  if
    (match Hashtbl.find_opt c.entries e.key with
     | Some cur -> cur == e
     | None -> false)
  then begin
    Hashtbl.remove c.entries e.key;
    (match e.task with Some t -> task_cancel t | None -> ());
    e.task <- None;
    (match e.state with Ready v -> (try c.retire v with _ -> ()) | _ -> ());
    e.watchers <- [];
    Hashtbl.reset e.entry_scopes
  end

(* Scope cleanup: the scope released its share; when the last owner
   goes the whole entry is dropped and its task cancelled. *)
let detach c e scope_id =
  Hashtbl.remove e.entry_scopes scope_id;
  if Hashtbl.length e.entry_scopes = 0 then drop_entry c e

let attach c e scope =
  let id = Signal.scope_id scope in
  if not (Hashtbl.mem e.entry_scopes id) then begin
    Hashtbl.replace e.entry_scopes id scope;
    (* [on_dispose] runs the detach immediately when [scope] is already
       disposed — guarded by [check_scope] at the call sites, this just
       keeps the invariant tight if a scope dies concurrently. *)
    Signal.on_dispose scope (fun () -> detach c e id)
  end

let notify e =
  (* iterate a snapshot so watchers registered inside a callback are
     not called this round, then prune dead scopes from the current
     list — which keeps those new watchers *)
  List.iter
    (fun (_, scope, f) ->
      if not (Signal.scope_is_disposed scope) then (try f e with _ -> ()))
    e.watchers;
  e.watchers <-
    List.filter
      (fun (_, scope, _) -> not (Signal.scope_is_disposed scope))
      e.watchers

(* Foreground publish of one completion. *)
let publish c comp =
  match Hashtbl.find_opt c.entries comp.comp_entry.key with
  | Some e when e == comp.comp_entry && e.generation = comp.comp_generation && e.state = Loading ->
      e.task <- None;
      (match comp.comp_result with
       | Ok v -> e.state <- Ready v
       | Error msg -> e.state <- Failed msg);
      notify e
  | _ ->
      (* stale generation, cancelled task, or dropped entry: the
         completion loses — retire the value it produced *)
      (match comp.comp_result with
       | Ok v -> (try c.retire v with _ -> ())
       | Error _ -> ())

let drain c =
  let rec take_all acc =
    match Queue.take_opt c.mailbox with
    | Some x -> take_all (x :: acc)
    | None -> List.rev acc
  in
  Mutex.lock c.mutex;
  let batch = take_all [] in
  Mutex.unlock c.mutex;
  List.iter (publish c) batch;
  List.length batch

let create ?(executor = executor_domain) ?(retire = fun _ -> ()) () =
  incr last_cache_id;
  let c =
    {
      cache_id = !last_cache_id;
      executor;
      retire;
      entries = Hashtbl.create 16;
      mailbox = Queue.create ();
      mutex = Mutex.create ();
    }
  in
  all_caches := (c.cache_id, (fun () -> drain c)) :: !all_caches;
  c

let unregister c =
  all_caches :=
    List.filter (fun (id, _) -> id <> c.cache_id) !all_caches

let drain_all () =
  List.fold_left (fun n (_, f) -> n + f ()) 0 !all_caches

let spawn c e load =
  let task =
    {
      task_cancelled = Atomic.make false;
      task_cancel_fn = Atomic.make None;
    }
  in
  let generation = e.generation in
  c.executor (fun () ->
      let result =
        try load task
        with exn -> Error (Printexc.to_string exn)
      in
      Mutex.lock c.mutex;
      Queue.push
        { comp_entry = e; comp_generation = generation; comp_result = result }
        c.mailbox;
      Mutex.unlock c.mutex);
  Some task

let add_watcher e scope = function
  | None -> ()
  | Some f ->
      e.watchers <- (Signal.scope_id scope, scope, f) :: e.watchers;
      (* already published: notify now so a late watcher cannot miss
         the value that raced its request *)
      (match e.state with
       | Loading -> ()
       | Ready _ | Failed _ -> (try f e with _ -> ()))

let request c ~scope ?on_state key ~load =
  check_scope scope;
  match Hashtbl.find_opt c.entries key with
  | Some e ->
      attach c e scope;
      add_watcher e scope on_state;
      e
  | None ->
      let e =
        {
          key;
          generation = 1;
          state = Loading;
          owner_scope = scope;
          task = None;
          entry_scopes = Hashtbl.create 4;
          watchers = [];
        }
      in
      Hashtbl.replace c.entries key e;
      attach c e scope;
      add_watcher e scope on_state;
      e.task <- spawn c e load;
      e

let reload c ~scope ?on_state key ~load =
  check_scope scope;
  match Hashtbl.find_opt c.entries key with
  | None -> request c ~scope ?on_state key ~load
  | Some e ->
      (match e.task with Some t -> task_cancel t | None -> ());
      e.task <- None;
      (* the old generation's value is superseded: release it now that
         the entry can no longer hand it out *)
      (match e.state with
       | Ready v -> (try c.retire v with _ -> ())
       | _ -> ());
      e.generation <- e.generation + 1;
      e.state <- Loading;
      e.owner_scope <- scope;
      attach c e scope;
      add_watcher e scope on_state;
      e.task <- spawn c e load;
      e

let watch ~scope e f =
  check_scope scope;
  add_watcher e scope (Some f)

let get c key =
  match Hashtbl.find_opt c.entries key with
  | Some { state = Ready v; _ } -> Some v
  | _ -> None

let entry c key = Hashtbl.find_opt c.entries key
let mem c key = Hashtbl.mem c.entries key

let invalidate c key =
  match Hashtbl.find_opt c.entries key with
  | Some e -> drop_entry c e
  | None -> ()

let clear c =
  let es = Hashtbl.fold (fun _ e acc -> e :: acc) c.entries [] in
  List.iter (drop_entry c) es

let length c = Hashtbl.length c.entries

let pending c =
  Mutex.lock c.mutex;
  let n = Queue.length c.mailbox in
  Mutex.unlock c.mutex;
  n
