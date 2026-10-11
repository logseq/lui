(* The update window's texts in one language, plus the lookup and
   formatting machinery the session and view share.

   Every text of the UI is a [key]; views reference keys, never inline
   strings. A locale ships a [t] record; [for_locale] resolves the
   user's language tag (POSIX locale or BCP-47) to the best shipped
   locale, filling missing fields from English. Format fields use
   [%[N]s] (1-indexed, reorderable — languages order their arguments as
   they need) and sequential [%s]; [%%] is a literal percent. *)

type key =
  | Title  (** window title: "Software Update" *)
  | Menu_item  (** "Check for Updates…" *)
  | Checking
  | Cancel
  | Ok
  | Up_to_date
  | Up_to_date_message  (** %[1]s app name, %[2]s version *)
  | Unavailable
  | Unavailable_message  (** %[1]s app name *)
  | Development_build
  | Error
  | Check_error
  | Install_error
  | Available  (** %[1]s app name *)
  | Available_message  (** %[1]s app, %[2]s new version, %[3]s current *)
  | Release_notes
  | Automatic_downloads
  | Skip
  | Remind_later
  | Install
  | Downloading
  | Progress  (** %[1]s downloaded size, %[2]s total size *)
  | Megabytes  (** %s decimal-megabyte number *)
  | Verifying
  | Installing
  | Ready
  | Ready_message  (** %[1]s app name, %[2]s new version *)
  | Later
  | Relaunch
  | Retry
  | Time_remaining  (** %s ETA as mm:ss *)

let all_keys =
  [ Title; Menu_item; Checking; Cancel; Ok; Up_to_date; Up_to_date_message;
    Unavailable; Unavailable_message; Development_build; Error; Check_error;
    Install_error; Available; Available_message; Release_notes;
    Automatic_downloads; Skip; Remind_later; Install; Downloading;
    Progress; Megabytes; Verifying; Installing; Ready; Ready_message;
    Later; Relaunch; Retry; Time_remaining ]

(** Stable names, state.field where the key belongs to one state. *)
let key_name = function
  | Title -> "window.title"
  | Menu_item -> "menu.item"
  | Checking -> "checking.title"
  | Cancel -> "button.cancel"
  | Ok -> "button.ok"
  | Up_to_date -> "up_to_date.title"
  | Up_to_date_message -> "up_to_date.message"
  | Unavailable -> "unavailable.title"
  | Unavailable_message -> "unavailable.message"
  | Development_build -> "unavailable.development_build"
  | Error -> "error.title"
  | Check_error -> "error.check"
  | Install_error -> "error.install"
  | Available -> "available.title"
  | Available_message -> "available.message"
  | Release_notes -> "available.release_notes"
  | Automatic_downloads -> "available.automatic_downloads"
  | Skip -> "button.skip"
  | Remind_later -> "button.remind_later"
  | Install -> "button.install"
  | Downloading -> "downloading.title"
  | Progress -> "downloading.progress"
  | Megabytes -> "downloading.megabytes"
  | Verifying -> "verifying.title"
  | Installing -> "installing.title"
  | Ready -> "ready.title"
  | Ready_message -> "ready.message"
  | Later -> "button.later"
  | Relaunch -> "button.relaunch"
  | Retry -> "button.retry"
  | Time_remaining -> "downloading.time_remaining"

(** The whole table in one language; an empty field falls back to
    English when the locale resolves. *)
type t = {
  title : string;
  menu_item : string;
  checking : string;
  cancel : string;
  ok : string;
  up_to_date : string;
  up_to_date_message : string;
  unavailable : string;
  unavailable_message : string;
  development_build : string;
  error : string;
  check_error : string;
  install_error : string;
  available : string;
  available_message : string;
  release_notes : string;
  automatic_downloads : string;
  skip : string;
  remind_later : string;
  install : string;
  downloading : string;
  progress : string;
  megabytes : string;
  verifying : string;
  installing : string;
  ready : string;
  ready_message : string;
  later : string;
  relaunch : string;
  retry : string;
  time_remaining : string;
}

let empty =
  {
    title = ""; menu_item = ""; checking = ""; cancel = ""; ok = "";
    up_to_date = ""; up_to_date_message = ""; unavailable = "";
    unavailable_message = ""; development_build = ""; error = "";
    check_error = ""; install_error = ""; available = "";
    available_message = ""; release_notes = ""; automatic_downloads = "";
    skip = ""; remind_later = ""; install = ""; downloading = "";
    progress = ""; megabytes = ""; verifying = ""; installing = "";
    ready = ""; ready_message = ""; later = ""; relaunch = "";
    retry = ""; time_remaining = "";
  }

let get (s : t) = function
  | Title -> s.title
  | Menu_item -> s.menu_item
  | Checking -> s.checking
  | Cancel -> s.cancel
  | Ok -> s.ok
  | Up_to_date -> s.up_to_date
  | Up_to_date_message -> s.up_to_date_message
  | Unavailable -> s.unavailable
  | Unavailable_message -> s.unavailable_message
  | Development_build -> s.development_build
  | Error -> s.error
  | Check_error -> s.check_error
  | Install_error -> s.install_error
  | Available -> s.available
  | Available_message -> s.available_message
  | Release_notes -> s.release_notes
  | Automatic_downloads -> s.automatic_downloads
  | Skip -> s.skip
  | Remind_later -> s.remind_later
  | Install -> s.install
  | Downloading -> s.downloading
  | Progress -> s.progress
  | Megabytes -> s.megabytes
  | Verifying -> s.verifying
  | Installing -> s.installing
  | Ready -> s.ready
  | Ready_message -> s.ready_message
  | Later -> s.later
  | Relaunch -> s.relaunch
  | Retry -> s.retry
  | Time_remaining -> s.time_remaining

let set (s : t) k v : t =
  match k with
  | Title -> { s with title = v }
  | Menu_item -> { s with menu_item = v }
  | Checking -> { s with checking = v }
  | Cancel -> { s with cancel = v }
  | Ok -> { s with ok = v }
  | Up_to_date -> { s with up_to_date = v }
  | Up_to_date_message -> { s with up_to_date_message = v }
  | Unavailable -> { s with unavailable = v }
  | Unavailable_message -> { s with unavailable_message = v }
  | Development_build -> { s with development_build = v }
  | Error -> { s with error = v }
  | Check_error -> { s with check_error = v }
  | Install_error -> { s with install_error = v }
  | Available -> { s with available = v }
  | Available_message -> { s with available_message = v }
  | Release_notes -> { s with release_notes = v }
  | Automatic_downloads -> { s with automatic_downloads = v }
  | Skip -> { s with skip = v }
  | Remind_later -> { s with remind_later = v }
  | Install -> { s with install = v }
  | Downloading -> { s with downloading = v }
  | Progress -> { s with progress = v }
  | Megabytes -> { s with megabytes = v }
  | Verifying -> { s with verifying = v }
  | Installing -> { s with installing = v }
  | Ready -> { s with ready = v }
  | Ready_message -> { s with ready_message = v }
  | Later -> { s with later = v }
  | Relaunch -> { s with relaunch = v }
  | Retry -> { s with retry = v }
  | Time_remaining -> { s with time_remaining = v }

(** [merge s fallback] fills the empty fields of [s] from [fallback]:
    a partial locale extends a complete one. *)
let merge s fallback =
  List.fold_left
    (fun acc k ->
      if get acc k = "" then set acc k (get fallback k) else acc)
    s all_keys

(* ------------------------------------------------------------------ *)
(* Format expansion: %[N]s picks argument N (1-indexed), %s the next
   one in order, %% a literal percent. Anything else is literal. *)

let expand fmt args : (string, string) result =
  let n = String.length fmt in
  let b = Buffer.create (n + 32) in
  let args_of i =
    if i < 0 || i >= Array.length args then
      Stdlib.Error (Printf.sprintf "argument %%%d out of range" (i + 1))
    else Stdlib.Ok args.(i)
  in
  let rec loop i next_arg =
    if i >= n then Stdlib.Ok (Buffer.contents b)
    else if fmt.[i] <> '%' then begin
      Buffer.add_char b fmt.[i];
      loop (i + 1) next_arg
    end
    else if i + 1 >= n then
      Stdlib.Error "trailing % at end of format"
    else
      match fmt.[i + 1] with
      | '%' ->
        Buffer.add_char b '%';
        loop (i + 2) next_arg
      | '[' -> (
        let close = ref (i + 2) in
        while !close < n && fmt.[!close] <> ']' do
          close := !close + 1
        done;
        if !close >= n || !close + 1 >= n || fmt.[!close + 1] <> 's' then
          Stdlib.Error "malformed %[N]s verb"
        else
          match int_of_string_opt (String.sub fmt (i + 2) (!close - i - 2)) with
          | Some k when k >= 1 -> (
            match args_of (k - 1) with
            | Stdlib.Ok s ->
              Buffer.add_string b s;
              loop (!close + 2) next_arg
            | Stdlib.Error _ as e -> e)
          | _ -> Stdlib.Error "malformed %[N]s verb")
      | 's' -> (
        match args_of next_arg with
        | Stdlib.Ok s ->
          Buffer.add_string b s;
          loop (i + 2) (next_arg + 1)
        | Stdlib.Error _ as e -> e)
      | c -> Stdlib.Error (Printf.sprintf "unsupported verb %%%c" c)
  in
  loop 0 0

(* ------------------------------------------------------------------ *)
(* Resolved texts: the table plus the format conventions of the
   language. *)

(** The resolved strings of one language plus its conventions:
    [decimal_comma] languages print a comma decimal mark ("12,3 MB"),
    [rtl] those written right-to-left. *)
type text = {
  s : t;
  lang : string;
  decimal_comma : bool;
  rtl : bool;
}

(** [cut s c] splits [s] at the first [c]: [(before, true, after)] or
    [(s, false, "")]. *)
let cut s c =
  match String.index_opt s c with
  | Some i ->
    (String.sub s 0 i, true,
     String.sub s (i + 1) (String.length s - i - 1))
  | None -> (s, false, "")

(** Format keys and their arity — used to validate a locale table. *)
let formats =
  [ (Up_to_date_message, 2); (Unavailable_message, 1); (Available, 1);
    (Available_message, 3); (Progress, 2); (Megabytes, 1);
    (Ready_message, 2); (Time_remaining, 1) ]

(** [check s] reports the first bad format: a non-empty format field
    whose verbs its declared arguments cannot fill. *)
let check s : (unit, string) result =
  let rec go = function
    | [] -> Stdlib.Ok ()
    | (k, arity) :: rest -> (
      let text = get s k in
      if text = "" then go rest
      else
        let args = Array.init arity (fun i -> Printf.sprintf "\x00%d" i) in
        match expand text args with
        | Stdlib.Ok _ -> go rest
        | Stdlib.Error m ->
          Stdlib.Error (Printf.sprintf "%s %S: %s" (key_name k) text m))
  in
  go formats

let get_text (x : text) k = get x.s k

(** [format x k args] expands the format field [k]; a malformed template
    comes back verbatim rather than crashing the UI — [check] catches it
    at setup. *)
let format (x : text) k args =
  match expand (get x.s k) args with
  | Stdlib.Ok s -> s
  | Stdlib.Error _ -> get x.s k

let decimal_bytes ~(comma : bool) n =
  let s = Printf.sprintf "%.1f" (Float.of_int n /. 1e6) in
  if comma then String.map (fun c -> if c = '.' then ',' else c) s else s

(** A byte size in decimal megabytes, as the platform shows them. *)
let megabytes (x : text) n =
  format x Megabytes [| decimal_bytes ~comma:x.decimal_comma n |]

(** A duration as mm:ss — neutral across the shipped languages. *)
let duration secs =
  let s = int_of_float (Float.round (Float.max 0. secs)) in
  Printf.sprintf "%d:%02d" (s / 60) (s mod 60)

(** "about 1:23 left" in the resolved language. *)
let time_remaining (x : text) secs =
  format x Time_remaining [| duration secs |]
