(* Opt-in crash reporting + renderer-loss recovery policy.

   The signal handler is best-effort: OCaml code is not
   async-signal-safe. The work inside it is kept to a minimum — the
   report path is computed at install time, the ring buffer is
   preallocated, and the write is wrapped so the original signal
   always wins. *)

type t = {
  app_name : string;
  dir : string;
  mutable renderer : string;
  ring : string array;
  mutable ring_pos : int;
  mutable ring_len : int;
  crash_path : string;
}

let ring_cap = 64
let line_cap = 240

let mkdir_p dir =
  let rec loop d =
    if d <> "" && not (Sys.file_exists d) then begin
      loop (Filename.dirname d);
      try Unix.mkdir d 0o700 with Unix.Unix_error _ -> ()
    end
  in
  loop dir

let crash_dir ?dir ~app_name () =
  match dir with
  | Some d -> d
  | None ->
    Filename.concat (Filename.get_temp_dir_name ())
      (app_name ^ "-lui-crashes")

let crash_path ?dir ~app_name () =
  Filename.concat (crash_dir ?dir ~app_name ()) (app_name ^ ".crash")

let timestamp () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (tm.tm_year + 1900)
    (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let clock () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%02d:%02d:%02d.%03d" tm.tm_hour tm.tm_min tm.tm_sec
    (int_of_float (mod_float (Unix.gettimeofday ()) 1. *. 1000.))

let log t line =
  let line =
    if String.length line > line_cap then String.sub line 0 line_cap
    else line
  in
  t.ring.(t.ring_pos) <- clock () ^ " " ^ line;
  t.ring_pos <- (t.ring_pos + 1) mod ring_cap;
  t.ring_len <- min (t.ring_len + 1) ring_cap

let set_renderer t name =
  t.renderer <- name;
  log t ("renderer: " ^ name)

let signal_name = function
  | s when s = Sys.sigabrt -> "SIGABRT"
  | s when s = Sys.sigbus -> "SIGBUS"
  | s when s = Sys.sigfpe -> "SIGFPE"
  | s when s = Sys.sigill -> "SIGILL"
  | s when s = Sys.sigsegv -> "SIGSEGV"
  | _ -> "signal"

let write_crash_report t ~signal ~backtrace =
  try
    mkdir_p t.dir;
    let oc = open_out_bin t.crash_path in
    let put fmt = Printf.fprintf oc (fmt ^^ "\n") in
    put "LUI-CRASH 1";
    put "app: %s" t.app_name;
    put "utc: %s" (timestamp ());
    put "os: %s" Sys.os_type;
    put "ocaml: %s" Sys.ocaml_version;
    put "renderer: %s" t.renderer;
    put "signal: %s" signal;
    put "--- backtrace ---";
    if backtrace = "" then put "(none)"
    else begin
      output_string oc backtrace;
      if not (String.ends_with ~suffix:"\n" backtrace) then
        output_char oc '\n'
    end;
    put "--- log (last %d) ---" ring_cap;
    (* Oldest first: the ring's oldest slot is ring_pos when full,
       0 while still filling. *)
    let start = if t.ring_len = ring_cap then t.ring_pos else 0 in
    for i = 0 to t.ring_len - 1 do
      put "%s" t.ring.((start + i) mod ring_cap)
    done;
    close_out oc;
    Some t.crash_path
  with _ -> None

let signals_env_enabled () =
  match Sys.getenv_opt "LUI_CRASH_SIGNALS" with
  | Some ("1" | "true" | "yes" | "YES" | "TRUE") -> true
  | _ -> false

(* Signal handlers are opt-in: OCaml is not async-signal-safe, so the
   crash file write is best-effort and can hang or double-fault. Callers
   that want handlers pass [~enable_signals:true] or set
   LUI_CRASH_SIGNALS=1. [install] without that still returns a reporter
   usable via {!write_crash_report}/{!log}. *)
let install ?dir ?(enable_signals = false) ~app_name ~renderer () =
  Printexc.record_backtrace true;
  let dir = crash_dir ?dir ~app_name () in
  let t =
    { app_name; dir; renderer;
      ring = Array.make ring_cap ""; ring_pos = 0; ring_len = 0;
      crash_path = crash_path ?dir:(Some dir) ~app_name () }
  in
  let enable = enable_signals || signals_env_enabled () in
  if enable then begin
    let handler signo =
      (* Best-effort: the write may fail or re-fault; the re-raise below
         must still deliver the original signal. *)
      (try
         ignore
           (write_crash_report t
              ~signal:(Printf.sprintf "%s (%d)" (signal_name signo) signo)
              ~backtrace:(Printexc.get_backtrace ()))
       with _ -> ());
      (try Sys.set_signal signo Sys.Signal_default with _ -> ());
      (try Unix.kill (Unix.getpid ()) signo with _ -> ())
    in
    List.iter
      (fun s ->
         try Sys.set_signal s (Sys.Signal_handle handler) with _ -> ())
      [ Sys.sigabrt; Sys.sigbus; Sys.sigfpe; Sys.sigill; Sys.sigsegv ]
  end;
  log t
    (Printf.sprintf "install: app=%s renderer=%s signals=%b" app_name
       renderer enable);
  t

let report_path t = t.crash_path

let pending_crash_report ?dir ~app_name () =
  let path = crash_path ?dir ~app_name () in
  if not (Sys.file_exists path) then None
  else
    try
      let ic = open_in_bin path in
      let n = in_channel_length ic in
      let s = really_input_string ic n in
      close_in ic;
      Some s
    with _ -> None

let mark_report_handled ?dir ~app_name () =
  let path = crash_path ?dir ~app_name () in
  try Sys.remove path with _ -> ()

module Recovery = struct
  type t = {
    rungs : string array;
    mutable index : int;
    mutable demotions : int;
    mutable history : (int * string * string) list;
  }

  let create = function
    | [] -> invalid_arg "Lui_resilience.Recovery.create: empty ladder"
    | rungs ->
      { rungs = Array.of_list rungs; index = 0; demotions = 0;
        history = [] }

  let ladder t = Array.to_list t.rungs
  let index t = t.index
  let current t = t.rungs.(t.index)
  let demotions t = t.demotions
  let exhausted t = t.index >= Array.length t.rungs - 1
  let history t = List.rev t.history

  let lost t ~reason =
    if exhausted t then None
    else begin
      t.history <- (t.index, current t, reason) :: t.history;
      t.index <- t.index + 1;
      t.demotions <- t.demotions + 1;
      Some (current t)
    end
end
