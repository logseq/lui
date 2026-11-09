(* Controllable application clock: a deadline-ordered timer queue whose
   time moves only through host ticks or explicit advances. *)

module Key = struct
  type t = float * int

  let compare (deadline_a, seq_a) (deadline_b, seq_b) =
    match Float.compare deadline_a deadline_b with
    | 0 -> Int.compare seq_a seq_b
    | order -> order
end

module Queue = Map.Make (Key)

type t = {
  mutable current : float;
  mutable queue : timer Queue.t;
  mutable count : int;
  mutable next_seq : int;
  mutable is_paused : bool;
  (* host time minus clock time; [None] until the next tick anchors it *)
  mutable host_offset : float option;
  mutable firing : bool;
}

and timer = {
  owner : t;
  interval : float option;
  action : unit -> unit;
  mutable key : Key.t;
  mutable live : bool;
}

let create ?(start = 0.) () =
  if not (Float.is_finite start) then invalid_arg "Lui_clock.create: start";
  {
    current = start;
    queue = Queue.empty;
    count = 0;
    next_seq = 0;
    is_paused = false;
    host_offset = None;
    firing = false;
  }

let now clock = clock.current

let enqueue clock timer deadline =
  let key = (deadline, clock.next_seq) in
  clock.next_seq <- clock.next_seq + 1;
  timer.key <- key;
  clock.queue <- Queue.add key timer clock.queue;
  clock.count <- clock.count + 1

let schedule clock delay interval action =
  let timer = {owner = clock; interval; action; key = (0., 0); live = true} in
  enqueue clock timer (clock.current +. delay);
  timer

let after clock delay action =
  if not (Float.is_finite delay && delay >= 0.) then
    invalid_arg "Lui_clock.after: delay must be finite and >= 0";
  schedule clock delay None action

let every clock interval action =
  if not (Float.is_finite interval && interval > 0.) then
    invalid_arg "Lui_clock.every: interval must be finite and > 0";
  schedule clock interval (Some interval) action

let dequeue clock timer =
  clock.queue <- Queue.remove timer.key clock.queue;
  clock.count <- clock.count - 1

let cancel timer =
  if timer.live then begin
    timer.live <- false;
    dequeue timer.owner timer
  end

let active timer = timer.live

let subscription timer = Signal.make_subscription (fun () -> cancel timer)

let pending clock = clock.count

let next_deadline clock =
  match Queue.min_binding_opt clock.queue with
  | Some ((deadline, _), _) -> Some deadline
  | None -> None

let next_delay clock =
  if clock.is_paused then None
  else
    Option.map
      (fun deadline -> Float.max 0. (deadline -. clock.current))
      (next_deadline clock)

let fire_through clock target =
  if clock.firing then invalid_arg "Lui_clock: time cannot move inside a timer";
  clock.firing <- true;
  let rec loop fired =
    match Queue.min_binding_opt clock.queue with
    | Some ((deadline, _), timer) when deadline <= target ->
      dequeue clock timer;
      clock.current <- Float.max clock.current deadline;
      (match timer.interval with
       | Some interval -> enqueue clock timer (deadline +. interval)
       | None -> timer.live <- false);
      timer.action ();
      loop (fired + 1)
    | _ -> fired
  in
  match loop 0 with
  | fired ->
    clock.current <- Float.max clock.current target;
    clock.firing <- false;
    fired
  | exception failure ->
    clock.firing <- false;
    raise failure

let tick clock ~now:host_now =
  if clock.is_paused || not (Float.is_finite host_now) then 0
  else
    match clock.host_offset with
    | None ->
      clock.host_offset <- Some (host_now -. clock.current);
      fire_through clock clock.current
    | Some offset -> fire_through clock (host_now -. offset)

let advance clock ms =
  if not (Float.is_finite ms && ms >= 0.) then
    invalid_arg "Lui_clock.advance: ms must be finite and >= 0";
  clock.host_offset <- Option.map (fun offset -> offset -. ms) clock.host_offset;
  fire_through clock (clock.current +. ms)

let settle ?(limit = 10_000) clock =
  let rec loop fired =
    match next_deadline clock with
    | None -> fired
    | Some _ when fired > limit ->
      failwith
        (Printf.sprintf "Lui_clock.settle: more than %d timers fired" limit)
    | Some deadline ->
      loop (fired + advance clock (Float.max 0. (deadline -. clock.current)))
  in
  loop 0

let pause clock = clock.is_paused <- true

let resume clock =
  if clock.is_paused then begin
    clock.is_paused <- false;
    clock.host_offset <- None
  end

let paused clock = clock.is_paused
