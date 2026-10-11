(* The updater UI's orchestrator over [Lui_updater].

   Two layers:

   - a pure reducer {!update} over {!model}: the UI-facing state
     machine the view renders —
     [idle → checking → available → downloading → verifying → staged →
     ready_to_restart], plus [up_to_date], [error] and [closed];
   - {!t}, the effectful driver: each user intent ({!check},
     {!download}, {!install}, {!cancel}, {!retry}, {!relaunch},
     {!dismiss}) feeds the reducer and runs the matching step of the
     {!Lui_updater} pipeline — check → plan → download → apply → swap —
     through an injected {!core} so tests substitute fakes without
     touching the network or the disk.

   Cancellation is cooperative: {!cancel} sets a flag the session's
   progress callback and wrapped fetcher poll, raising [Cancelled]
   which unwinds to the driver; the session then returns to the offer
   (the download can be retried) or [idle]. A fetcher that reports
   progress mid-transfer aborts promptly; the bundled curl fetcher
   reports at the ends, so cancellation lands at the next report. *)

module P = Lui_pkg.Private

(* ------------------------------------------------------------------ *)
(* The UI-facing state machine. *)

type error_kind =
  | Check_failed
  | Download_failed
  | Verify_failed
  | Stage_failed
  | Swap_failed
  | Cancelled
  | Internal

(** What an available update offers. *)
type offer = {
  version : string;
  notes : string;
  size : int;
  date : string;
  info : Lui_updater.update_info;
}

(** A transfer in flight, with the smoothed rate the ETA derives from. *)
type download = {
  bytes_done : int;
  total : int;
  eta : float option;      (* seconds remaining, once the rate is known *)
  offer : offer;
  rate : float;            (* bytes/sec, exponential moving average *)
  last : (int * float) option;  (* last report: bytes, at *)
}

(** The staged tree, between verify and swap. *)
type staged_view = { st : Lui_updater.staged; offer : offer }

(** The swapped update: installed, runs at next launch. *)
type ready = { version : string; exe : string; backup : string }

type error = {
  kind : error_kind;
  message : string;
  retryable : bool;
  offer : offer option;  (** the update install was working on, for retry *)
  foreground : bool;     (** a user-initiated op failed: show it *)
}

type phase =
  | Idle
  | Checking
  | Up_to_date
  | Available of offer
  | Downloading of download
  | Verifying of offer
  | Staged of staged_view
  | Ready_to_restart of ready
  | Error of error
  | Closed

type model = {
  phase : phase;
  text : Strings.text;          (** resolved locale *)
  app_name : string;
  current_version : string;
  auto_downloads : bool;        (** the offer's checkbox *)
  skipped_version : string option;
  user_initiated : bool;        (** the active check came from the user *)
}

(** User intents and driver reports into the reducer. *)
type action =
  | Check of { user : bool }
  | Checked of (Lui_updater.update_info option, string) result
  | Install_now
  | Skip_version
  | Remind_later
  | Set_auto_downloads of bool
  | Progress of { received : int; total : int; at : float }
  | Begin_verify
  | Staged_ok of Lui_updater.staged * offer
  | Swapped of ready
  | Cancel_download              (** the intent: ask to abort *)
  | Cancelled_now                (** the report: abort landed *)
  | Failed of error_kind * string
  | Retry
  | Dismiss
  | Relaunch
  | Relaunched
  | Close_requested              (** the window closed mid-flight *)

exception Cancelled

let offer_of (i : Lui_updater.update_info) : offer =
  { version = i.version; notes = i.notes; size = i.archive.size;
    date = i.date; info = i }

let kind_retryable = function
  | Check_failed | Download_failed | Cancelled -> true
  | Verify_failed | Stage_failed | Swap_failed | Internal -> false

let err kind message ~offer ~foreground =
  { kind; message; offer; foreground; retryable = kind_retryable kind }

let dl_start o =
  { bytes_done = 0; total = o.size; eta = None; offer = o;
    rate = 0.; last = None }

let dl_progress d ~received ~total ~at =
  let rate, last =
    match d.last with
    | Some (prev, t0) when at > t0 && received > prev ->
      let inst = Float.of_int (received - prev) /. (at -. t0) in
      (0.7 *. d.rate +. 0.3 *. inst, Some (received, at))
    | None -> (d.rate, Some (received, at))
    | Some _ -> (d.rate, d.last)
  in
  let eta =
    if rate > 0. && total > received then
      Some (Float.of_int (total - received) /. rate)
    else None
  in
  { d with bytes_done = received; total; eta; rate; last }

let offer_of_phase = function
  | Available o -> Some o
  | Downloading d -> Some d.offer
  | Verifying o -> Some o
  | Staged s -> Some s.offer
  | _ -> None

(** Phases that may start a check: any quiescent one. *)
let may_check = function
  | Idle | Up_to_date | Available _ | Error _ -> true
  | Checking | Downloading _ | Verifying _ | Staged _
  | Ready_to_restart _ | Closed -> false

let update m a : model =
  match a with
  | Check { user } -> (
    match m.phase with
    | Idle | Up_to_date | Available _ | Error _ ->
      { m with phase = Checking; user_initiated = user }
    | Checking | Downloading _ | Verifying _ | Staged _
    | Ready_to_restart _ | Closed -> m)
  | Checked r -> (
    match (m.phase, r) with
    | Checking, Stdlib.Ok (Some i) ->
      let phase =
        (* a background check honors a skipped version and the
           auto-download choice; a user's always shows the offer *)
        if (not m.user_initiated) && m.skipped_version = Some i.version then
          Idle
        else if (not m.user_initiated) && m.auto_downloads then
          Downloading (dl_start (offer_of i))
        else Available (offer_of i)
      in
      { m with phase }
    | Checking, Stdlib.Ok None ->
      { m with phase = (if m.user_initiated then Up_to_date else Idle) }
    | Checking, Stdlib.Error message ->
      { m with
        phase =
          Error
            (err Check_failed message ~offer:None
               ~foreground:m.user_initiated) }
    | _ -> m)
  | Install_now -> (
    match m.phase with
    | Available o -> { m with phase = Downloading (dl_start o) }
    (* retry of a failed download re-enters the same offer *)
    | Error { offer = Some o; _ } ->
      { m with phase = Downloading (dl_start o) }
    | _ -> m)
  | Skip_version -> (
    match m.phase with
    | Available o ->
      { m with phase = Closed; skipped_version = Some o.version }
    | _ -> m)
  | Remind_later -> (
    match m.phase with
    | Available _ -> { m with phase = Closed }
    | _ -> m)
  | Set_auto_downloads b -> { m with auto_downloads = b }
  | Progress { received; total; at } -> (
    match m.phase with
    | Downloading d ->
      let d = dl_progress d ~received ~total ~at in
      if total > 0 && received >= total then
        { m with phase = Verifying d.offer }
      else { m with phase = Downloading d }
    | _ -> m)
  | Begin_verify -> (
    match m.phase with
    | Downloading d -> { m with phase = Verifying d.offer }
    | _ -> m)
  | Staged_ok (st, o) -> (
    match m.phase with
    | Verifying _ | Downloading _ ->
      { m with phase = Staged { st; offer = o } }
    | _ -> m)
  | Swapped r -> (
    match m.phase with
    | Staged _ | Verifying _ | Downloading _ ->
      { m with phase = Ready_to_restart r }
    | _ -> m)
  | Cancel_download | Cancelled_now -> (
    match m.phase with
    | Checking -> { m with phase = Idle }
    | Downloading d -> { m with phase = Available d.offer }
    | Verifying o -> { m with phase = Available o }
    | Staged s -> { m with phase = Available s.offer }
    | _ -> m)
  | Failed (kind, message) -> (
    match m.phase with
    | Idle | Up_to_date | Closed | Error _ -> m
    | _ ->
      let offer = offer_of_phase m.phase in
      { m with
        phase =
          Error
            (err kind message ~offer
               ~foreground:(m.user_initiated || offer <> None)) })
  | Retry -> m  (* the effect is the driver's *)
  | Dismiss -> (
    match m.phase with
    | Idle | Up_to_date | Available _ | Ready_to_restart _ | Error _ ->
      { m with phase = Closed }
    | Checking | Downloading _ | Verifying _ | Staged _ | Closed -> m)
  | Relaunch -> m  (* the effect is the driver's *)
  | Relaunched -> { m with phase = Closed }
  | Close_requested -> { m with phase = Closed }

let initial_model ~app_name ~current_version ~text =
  {
    phase = Idle;
    text;
    app_name;
    current_version;
    auto_downloads = false;
    skipped_version = None;
    user_initiated = false;
  }

let phase_name = function
  | Idle -> "idle"
  | Checking -> "checking"
  | Up_to_date -> "up_to_date"
  | Available _ -> "available"
  | Downloading _ -> "downloading"
  | Verifying _ -> "verifying"
  | Staged _ -> "staged"
  | Ready_to_restart _ -> "ready_to_restart"
  | Error _ -> "error"
  | Closed -> "closed"

(* ------------------------------------------------------------------ *)
(* The injectable core — [lui_core] binds Lui_updater wholesale; tests
   substitute a fake to drive the same transitions without the network. *)

type core = {
  check :
    fetch:Lui_updater.fetcher ->
    Lui_updater.feed ->
    (Lui_updater.update_info option, string) result;
  plan :
    Lui_updater.update_info -> current:string -> Lui_updater.install_plan;
  download :
    fetch:Lui_updater.fetcher ->
    verify_sig:(sha256:string -> signature:string -> bool) option ->
    progress:(received:int -> total:int -> unit) ->
    Lui_updater.artifact ->
    dest:string ->
    (unit, string) result;
  apply :
    verify:(string -> unit Lui_pkg.outcome) option ->
    info:Lui_updater.update_info ->
    plan:Lui_updater.install_plan ->
    package:string ->
    bundle:string ->
    stage_dir:string ->
    unit ->
    (Lui_updater.staged, string) result;
  swap : Lui_updater.staged -> target:string -> (string, string) result;
  relaunch : exe:string -> args:string list -> unit;
}

let lui_core =
  {
    check = (fun ~fetch f -> Lui_updater.check ~fetch f);
    plan = (fun i ~current -> Lui_updater.plan i ~current);
    download =
      (fun ~fetch ~verify_sig ~progress a ~dest ->
        Lui_updater.download ~fetch ?verify_sig ~progress a ~dest);
    apply =
      (fun ~verify ~info ~plan ~package ~bundle ~stage_dir () ->
        Lui_updater.apply ?verify ~info ~plan ~package ~bundle ~stage_dir
          ());
    swap = (fun st ~target -> Lui_updater.swap st ~target);
    relaunch = (fun ~exe ~args -> Lui_updater.relaunch ~exe ~args ());
  }

type t = {
  feed : Lui_updater.feed;
  bundle : string;
  exe : string;
  args : string list;
  stage_dir : string;
  work_dir : string;
  core : core;
  fetch : Lui_updater.fetcher;
  verify : (string -> unit Lui_pkg.outcome) option;
  verify_sig : (sha256:string -> signature:string -> bool) option;
  now : unit -> float;
  mutable model : model;
  mutable cancelled : bool;
  mutable verify_failed : bool;
  listeners : (model -> unit) list ref;
}

let create ?(locale = "en") ?(extra_strings = []) ?(core = lui_core)
    ?fetch ?verify ?verify_sig ?(now = Unix.gettimeofday) ?(args = [])
    ?stage_dir ?work_dir ~feed ~bundle ~exe () =
  let stage_dir =
    Option.value stage_dir ~default:(Lui_updater.stage_dir_of bundle)
  in
  {
    feed;
    bundle;
    exe;
    args;
    stage_dir;
    work_dir =
      Option.value work_dir ~default:(stage_dir ^ ".download");
    core;
    fetch =
      Option.value fetch
        ~default:(Lui_updater.curl_fetcher
                    ~user_agent:(Lui_updater.user_agent feed)
                    ());
    verify;
    verify_sig;
    now;
    model =
      initial_model ~app_name:feed.Lui_updater.app_name
        ~current_version:feed.Lui_updater.version
        ~text:(Translations.for_locale ~extra:extra_strings locale);
    cancelled = false;
    verify_failed = false;
    listeners = ref [];
  }

let model t = t.model
let status t = t.model.phase

let on_change t fn =
  t.listeners := fn :: !(t.listeners);
  fun () ->
    t.listeners := List.filter (fun f -> not (f == fn)) !(t.listeners)

let notify t = List.iter (fun f -> f t.model) !(t.listeners)

let send t a =
  let before = t.model in
  t.model <- update t.model a;
  if t.model <> before then notify t

(* ------------------------------------------------------------------ *)
(* Driver. *)

let cancellable_fetch t (base : Lui_updater.fetcher) : Lui_updater.fetcher =
  {
    get =
      (fun ~url ~dest ->
        if t.cancelled then raise Cancelled else base.get ~url ~dest);
  }

let artifact_of_plan = function
  | Lui_updater.Full a -> a
  | Lui_updater.Delta d -> d.Lui_updater.artifact

let can_check t = may_check t.model.phase

let rec check ?(user = false) t =
  if can_check t then begin
    t.cancelled <- false;
    send t (Check { user });
    match
      (try `R (t.core.check ~fetch:(cancellable_fetch t t.fetch) t.feed)
       with
       | Cancelled -> `cancelled
       | e -> `failed (Printexc.to_string e))
    with
    | `R r ->
      send t (Checked r);
      (* an auto-download check proceeds to the install *)
      (match t.model.phase with
       | Downloading d -> install_offer ~swap:true t d.offer
       | _ -> ())
    | `failed m -> send t (Checked (Stdlib.Error m))
    | `cancelled -> send t Cancelled_now
  end

and download_to_pkg t pl =
  let pkg = Filename.concat t.work_dir "pkg" in
  P.Fs.mkdir_p t.work_dir;
  let progress ~received ~total =
    if t.cancelled then raise Cancelled;
    send t (Progress { received; total; at = t.now () })
  in
  try
    match
      t.core.download ~fetch:(cancellable_fetch t t.fetch)
        ~verify_sig:t.verify_sig ~progress (artifact_of_plan pl) ~dest:pkg
    with
    | Stdlib.Ok () -> `ok pkg
    | Stdlib.Error m -> `failed (Download_failed, m)
  with
  | Cancelled -> `cancelled
  | e -> `failed (Download_failed, Printexc.to_string e)

and apply_pkg t o pl ~pkg =
  send t Begin_verify;
  t.verify_failed <- false;
  let verify =
    Option.map
      (fun v root ->
        match v root with
        | Lui_pkg.Ok () as ok -> ok
        | (Lui_pkg.Skipped _ | Lui_pkg.Unsupported _ | Lui_pkg.Failed _)
          as out ->
          t.verify_failed <- true;
          out)
      t.verify
  in
  try
    match
      t.core.apply ~verify ~info:o.info ~plan:pl ~package:pkg
        ~bundle:t.bundle ~stage_dir:t.stage_dir ()
    with
    | Stdlib.Ok st -> `ok st
    | Stdlib.Error m ->
      `failed ((if t.verify_failed then Verify_failed else Stage_failed), m)
  with
  | Cancelled -> `cancelled
  | e -> `failed (Stage_failed, Printexc.to_string e)

and swap_staged t (st : Lui_updater.staged) (o : offer) =
  try
    match t.core.swap st ~target:t.bundle with
    | Stdlib.Ok backup ->
      send t
        (Swapped
           { version = o.version;
             exe = Filename.concat t.bundle t.exe;
             backup });
      `ok
    | Stdlib.Error m -> `failed (Swap_failed, m)
  with
  | Cancelled -> `cancelled
  | e -> `failed (Swap_failed, Printexc.to_string e)

(* The pipeline mirroring [Lui_updater.install]: download → verify →
   stage → (optionally) swap, with a failed delta falling back to the
   full archive once. [~swap:false] leaves the session [Staged]. *)
and install_offer ~swap t o =
  let run pl =
    match download_to_pkg t pl with
    | `cancelled -> `cancelled
    | `failed (k, m) -> `failed (k, m)
    | `ok pkg -> (
      match apply_pkg t o pl ~pkg with
      | `cancelled -> `cancelled
      | `failed (k, m) -> `failed (k, m)
      | `ok st ->
        send t (Staged_ok (st, o));
        if swap then swap_staged t st o else `ok)
  in
  let pl = t.core.plan o.info ~current:t.feed.version in
  let outcome =
    match run pl with
    | `failed _ as f -> (
      match pl with
      | Lui_updater.Delta _ -> run (Lui_updater.Full o.info.Lui_updater.archive)
      | Lui_updater.Full _ -> f)
    | r -> r
  in
  (match outcome with
   | `ok -> ()
   | `cancelled -> send t Cancelled_now
   | `failed (k, m) -> send t (Failed (k, m)));
  if P.Fs.exists t.work_dir then P.Fs.rm_rf t.work_dir

and install_staged t s =
  t.cancelled <- false;
  match swap_staged t s.st s.offer with
  | `ok -> ()
  | `cancelled -> send t Cancelled_now
  | `failed (k, m) -> send t (Failed (k, m))

let download t =
  match t.model.phase with
  | Available o ->
    t.cancelled <- false;
    send t Install_now;
    install_offer ~swap:false t o
  | _ -> ()

let install t =
  match t.model.phase with
  | Available o ->
    t.cancelled <- false;
    send t Install_now;
    install_offer ~swap:true t o
  | Staged s -> install_staged t s
  | _ -> ()

let cancel t =
  t.cancelled <- true;
  send t Cancel_download

let retry t =
  match t.model.phase with
  | Error e when e.retryable -> (
    t.cancelled <- false;
    match e.kind with
    | Check_failed -> check ~user:t.model.user_initiated t
    | _ -> (
      match e.offer with
      | Some o ->
        send t Install_now;
        install_offer ~swap:true t o
      | None -> ()))
  | _ -> ()

let relaunch t =
  match t.model.phase with
  | Ready_to_restart r ->
    t.core.relaunch ~exe:r.exe ~args:t.args;
    send t Relaunched
  | _ -> ()

let dismiss t = send t Dismiss
let close t =
  t.cancelled <- true;
  send t Close_requested

let skip t = send t Skip_version
let remind_later t = send t Remind_later
let set_auto_downloads t b = send t (Set_auto_downloads b)
