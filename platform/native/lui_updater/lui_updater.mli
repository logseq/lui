(** Lui_updater — the runtime self-update client for apps built on the
    native backend.

    The last leg of the release chain {!Lui_pkg} starts: the packager
    signs bundles and writes delta files; this module polls an update
    feed, picks a delta when one matches the running version
    (delta-first), downloads and verifies it, stages the new tree next
    to the installed one, swaps it in with a rename dance and relaunches
    the app.

    {b Feed format.} A feed is a base URL plus a channel; the manifest
    lives at [<base>/<channel>.json] (e.g. [https://x.co/u/stable.json])
    and reads:

    {[
      {
        "version": "1.2.0",
        "notes": "## What's new …",        // optional, Markdown
        "date": "2026-01-01T00:00:00Z",    // optional
        "url": "…/app-1.2.0.tar.gz",       // the full package
        "size": 123456,                    // bytes, required
        "sha256": "<64 hex>",              // required: the integrity anchor
        "signature": "…",                  // optional: verified via [verify_sig]
        "deltas": [
          { "from": "1.1.0",               // running version it patches
            "url": "…/d-1.1.0-1.2.0.delta", // a [Lui_pkg.update_pkg] file
            "size": 789, "sha256": "…", "signature": "…" }
        ]
      }
    ]}

    The full package is a gzipped tar. For a macOS [.app] target it
    holds exactly one top-level [<name>.app]; for a directory install
    (Linux/Windows layout) it holds the files of the app directory.

    {b Integrity.} Every download is checked against its published size
    and SHA-256. A feed served over HTTPS plus a correct digest is the
    baseline. Two extension points tighten it: [verify_sig] checks the
    optional [signature] field of an artifact (e.g. an Ed25519 signature
    of the digest), and [verify] inspects the fully staged tree before
    the swap (e.g. [codesign --verify] or an mtree manifest).

    {b Schemes.} [https:] always; [http:] only to loopback hosts (local
    servers); [file:] for local mirrors and tests. Everything else is
    refused before a fetcher runs, and [https] responses may only
    redirect to [https]. No raw HTTP dependency: fetching goes through
    an injected {!fetcher} that defaults to a [curl] subprocess with
    hardened flags, so tests serve canned bytes or local files.

    {b Swap.} The new tree is built in [<bundle>.update] — never inside
    the running bundle — then renamed into place: the old bundle moves
    to a backup first, the staged one takes the target name, and the
    backup path is reported for {!rollback} or {!cleanup_backup}.

    {b Relaunch.} {!spawn_detached} starts the new executable without
    waiting for it (the child is reparented once the caller exits);
    {!relaunch} spawns and exits the process. A staged update that is
    not relaunched simply runs at the next launch.

    {b Resumable downloads} are not implemented: the curl fetcher
    downloads whole artifacts; a custom fetcher may resume with
    [curl -C -] semantics of its own. *)

type channel =
  | Stable
  | Beta
  | Named of string  (** a feed directory of its own, ["<n>.json"] *)

(** App identity a feed URL derives from: what the running app is and
    which channel it follows. *)
type feed = {
  base_url : string;  (** feed root, e.g. ["https://example.com/updates"] *)
  channel : channel;
  app_id : string;    (** bundle id, e.g. ["com.example.app"] *)
  app_name : string;  (** display name, also the default executable name *)
  version : string;   (** the running version *)
}

(** One downloadable artifact: a full package or a delta file. *)
type artifact = {
  url : string;
  size : int;
  sha256 : string;       (** lowercase hex, 64 chars *)
  signature : string option;
}

(** A delta update entry: patches [from] to the manifest's version. *)
type delta = {
  from : string;
  artifact : artifact;
}

(** A manifest entry: a newer version of the app. *)
type update_info = {
  version : string;
  notes : string;
  date : string;
  archive : artifact;
  deltas : delta list;
}

type install_plan =
  | Full of artifact
  | Delta of delta

type progress = {
  received : int;
  total : int;
}

(** {1 State machine}

    A pure transition function so hosts can drive UI: check → offer →
    download → staged → swapped → relaunch. Invalid transitions are a
    documented no-op, not an error. *)

type state =
  | Idle
  | Checking
  | Available of update_info
  | Downloading of progress
  | Ready of string        (** staged path, verified, ready to swap *)
  | Applied                (** swapped into place; runs at next launch *)
  | Error of string

type event =
  | Begin_check
  | Checked of update_info option  (** [None] = already up to date *)
  | Begin_download of update_info
  | Progress of progress
  | Staged of string
  | Applied_to of string
  | Failed of string
  | Dismissed                      (** user declined/skipped *)

val step : state -> event -> state

(** {1 Versions and cadence} *)

val compare_version : string -> string -> int
(** Semver-ish ordering: a leading [v] and a [+build] suffix are
    ignored, numeric fields compare numerically, a pre-release sorts
    before its release, numbers before words. *)

val next_check : last:float -> failed:float -> interval:float ->
  now:float -> float
(** When the next automatic check is due (epoch seconds): [interval]
    after the last successful check, and when the last check failed, at
    most [min interval 3600] after the failure. A [last] in the future
    (clock set back) is treated as [now]. *)

(** {1 Fetching} *)

type fetcher = {
  get : url:string -> dest:string -> (unit, string) result;
    (** downloads [url] into the file [dest]; [Error] carries a
        human-readable reason *)
}

val curl_fetcher : ?user_agent:string -> unit -> fetcher
(** The default fetcher: a [curl] subprocess
    [curl -fsSL --proto-redir =https -o dest url] with connect and total
    timeouts. Reports no incremental progress — [progress] callbacks get
    the start and end marks. *)

val url_allowed : string -> bool
(** Whether the scheme policy lets a URL be fetched: [https], loopback
    [http], or [file]. *)

val user_agent : feed -> string
(** ["Lui_updater/1 <app_name>/<version>"], sent as the fetcher's
    User-Agent. *)

(** {1 Check} *)

val feed_url : feed -> string
(** [<base>/<channel>.json]. *)

val manifest_of_string : string -> (update_info, string) result
(** Parses a manifest; requires [version], a complete [archive]
    ([url], positive [size], 64-hex [sha256]). Malformed delta entries
    are skipped; a missing top field fails the whole manifest. *)

val check : ?fetch:fetcher -> feed -> (update_info option, string) result
(** Fetches [feed_url], parses the manifest and returns [Some info]
    when its version is newer than [feed.version], [None] when the app
    is up to date. *)

(** {1 Plan} *)

val plan : update_info -> current:string -> install_plan
(** Delta-first: the delta whose [from] is [current], else the full
    archive. *)

(** {1 Download} *)

val max_manifest : int
(** 1 MiB *)

val max_package : int
(** 1 GiB *)

val download :
  ?fetch:fetcher ->
  ?verify_sig:(sha256:string -> signature:string -> bool) ->
  ?progress:(received:int -> total:int -> unit) ->
  artifact -> dest:string -> (unit, string) result
(** Downloads [artifact] to [dest] and verifies size and SHA-256; when
    the artifact carries a [signature] and [verify_sig] is given, it
    must accept or the download fails. Bounds: [0 < size <= max_package]. *)

(** {1 Apply and swap} *)

type layout =
  | App_bundle  (** target is a [<name>.app] bundle directory *)
  | Dir         (** target is a plain directory of files *)

type staged = {
  stage_dir : string;   (** the [<bundle>.update] work dir *)
  new_root : string;    (** the new tree: the staged bundle or dir *)
  layout : layout;
}

val stage_dir_of : string -> string
(** [<bundle>.update], the conventional staging dir next to the target. *)

val apply :
  ?verify:(string -> unit Lui_pkg.outcome) ->
  info:update_info ->
  plan:install_plan ->
  package:string ->
  bundle:string ->
  stage_dir:string -> unit -> (staged, string) result
(** Builds the new tree inside [stage_dir], never in place: [Delta]
    calls {!Lui_pkg.apply_delta} ([old_dir] = the installed bundle,
    [new_dir] = the staged bundle, named after the target); [Full]
    untars the package under [stage_dir]. The staged result must shape
    like the target — one [.app] for [App_bundle] — and pass [verify]
    when given. [stage_dir] is expected absent or owned by the updater. *)

val swap : staged -> target:string -> (string, string) result
(** Renames [target] to a backup ([.<name>.old-<pid>] next to it) then
    the staged tree to [target]; on failure the backup is moved back.
    Returns the backup path — the rollback anchor. For [Dir] targets
    the entries are swapped one by one with mid-failure undo and the
    asides are cleaned on success (no backup). *)

val rollback : backup:string -> target:string -> (unit, string) result
(** Moves a swapped-in [target] aside and renames [backup] back to
    [target]. *)

val cleanup_backup : string -> unit
(** Removes a backup left by {!swap} once the new version is confirmed
    running. *)

(** {1 Install} *)

type install_report =
  | Up_to_date
  | Installed of {
      version : string;
      backup : string;        (** rollback anchor; [""] for Dir swaps *)
      exe : string;           (** the new executable's absolute path *)
    }
  | Install_failed of string

val install :
  ?fetch:fetcher ->
  ?verify:(string -> unit Lui_pkg.outcome) ->
  ?verify_sig:(sha256:string -> signature:string -> bool) ->
  ?progress:(received:int -> total:int -> unit) ->
  ?on_state:(state -> unit) ->
  ?stage_dir:string ->
  feed -> bundle:string -> exe:string -> install_report
(** The full pipeline short of relaunch: {!check} → {!plan} →
    {!download} → {!apply} → {!swap}. A failed delta falls back to the
    full archive once (the new download restarts progress). [exe] is
    the executable's path inside the bundle (["Contents/MacOS/x"] on
    macOS, ["x"] for a directory install), reported so the caller can
    relaunch it. [on_state] observes the {!state} transitions. *)

val install_and_relaunch :
  ?fetch:fetcher ->
  ?verify:(string -> unit Lui_pkg.outcome) ->
  ?verify_sig:(sha256:string -> signature:string -> bool) ->
  ?progress:(received:int -> total:int -> unit) ->
  ?on_state:(state -> unit) ->
  ?stage_dir:string ->
  feed -> bundle:string -> exe:string -> args:string list -> install_report
(** {!install}, then on [Installed] spawns [bundle/exe] detached and
    exits the process ([exit 0]) — this call never returns on success.
    On any other outcome it returns the report without exiting. *)

(** {1 Target and relaunch} *)

val install_target_of : exe:string -> (string, string) result
(** What an update replaces: on macOS the [.app] bundle containing
    [exe] (great-grandparent dir), elsewhere [exe]'s directory. *)

val spawn_detached : string -> string list -> int
(** Starts [path args] without waiting: stdin is [/dev/null], stdout
    and stderr are inherited, and the returned pid is never waited on,
    so the child outlives the caller. *)

val relaunch : exe:string -> args:string list -> unit -> 'a
(** [spawn_detached exe args] then [exit 0]. Never returns. *)
