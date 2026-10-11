(** Lui_cli — the [lui] developer command line for the native backend.

    One entry point, {!main}, dispatches hand-parsed argv to the
    per-command runners below. The command set covers the whole
    developer loop: {!Init} scaffolds an app, {!Dev} rebuilds and
    restarts it on change, {!Build} compiles once, {!Package} drives
    {!Lui_pkg} / {!Lui_pkg_linux} / {!Lui_pkg_windows} into a real
    distributable, {!Doctor} audits the toolchain, and {!Keygen} writes
    an update-signing key pair for {!Lui_updater} feeds.

    Everything that can be pure is exposed: argument parsing, the
    package routing plan, the doctor's probe set and version math, the
    dev watcher's line classifier and the keygen command list — so the
    test suite covers the logic without touching the network or the
    file system outside temp directories. *)

val name : string
val version : string

(** {1 Argument parsing} *)

module Args : sig
  type platform_sel = P_auto | P_mac | P_linux | P_windows
  type artifact_fmt =
    | F_auto
    | F_dmg
    | F_zip
    | F_deb
    | F_tar
    | F_appimage
    | F_msix
    | F_nsis
  type key_alg = Ed25519 | Rsa

  type init_spec = {
    i_name : string option;
    i_dir : string;   (** target directory (created when absent) *)
    i_force : bool;   (** allow a non-empty target directory *)
  }

  type dev_spec = {
    d_dir : string;
    d_exe : string;   (** exe name under [_build/default] *)
  }

  type build_spec = { b_dir : string; b_release : bool }

  type package_spec = {
    p_dir : string;
    p_platform : platform_sel;
    p_sign : string option;   (** signing identity ([--sign]) *)
    p_format : artifact_fmt;
    p_out : string;           (** output directory (default [<dir>/dist]) *)
    p_webview : bool;         (** bundle [<dir>/web] into the package *)
    p_name : string option;
    p_bundle_id : string option;
    p_version : string option;
    p_icon : string option;
    p_exe : string option;    (** override the built binary path *)
    p_build : bool;           (** run [dune build] first ([--no-build]) *)
  }

  type keygen_spec = {
    k_dir : string;
    k_name : string;   (** basename of the key files *)
    k_alg : key_alg;
    k_force : bool;
  }

  type command =
    | Init of init_spec
    | Dev of dev_spec
    | Build of build_spec
    | Package of package_spec
    | Doctor
    | Keygen of keygen_spec
    | Version
    | Help of string option  (** command name to detail, or the overview *)

  val parse : string list -> (command, string) result
  (** [parse args] interprets [args] (no program name). Errors are
      human-readable one-liners for exit code 2. *)

  val parse_platform : string -> (platform_sel, string) result
  val string_of_platform : platform_sel -> string
  val string_of_fmt : artifact_fmt -> string
  val usage : string
  (** the [lui help] overview *)

  val usage_of : string -> string option
  (** per-command detail *)
end

(** {1 Process and file helpers}

    Shared with the package libraries; re-exported so the command
    runners and the tests speak the same vocabulary. *)

module Proc : sig
  type ran = { status : int; stdout : string; stderr : string }

  val run : ?stdin:string -> string -> string list -> ran
  val which : string -> string option
end

module Fs : sig
  type kind = Dir | File | Link | Other | Absent

  val kind_of : string -> kind
  val is_dir : string -> bool
  val exists : string -> bool
  val mkdir_p : ?perm:int -> string -> unit
  val read_file : string -> string
  val write_file : ?perm:int -> string -> string -> unit
  val copy_file : src:string -> dst:string -> unit
  val install : src:string -> dst:string -> unit
  val walk : string -> (string * kind) list
  val rm_rf : string -> unit
  val temp_dir : ?prefix:string -> ?parent:string -> unit -> string
end

(** {1 lui init} *)

module Init : sig
  val sanitize_name : string -> string
  (** Lowercase slug for display and bundle ids:
      ["My App!"] -> ["my-app"], never empty. *)

  val files : name:string -> (string * string) list
  (** [files ~name] is the scaffold as [(relative path, content)] —
      [dune-project], [dune], [main.ml], [.gitignore], [README.md].
      [main.ml] follows the window-host demo idiom (model, reducer,
      view over {!Lui_app}) against a recording backend so the tree
      builds wherever [lui] is installed. *)

  val scaffold :
    dir:string -> name:string option -> force:bool ->
    (string list, string) result
  (** Writes {!files} under [dir]. [Error] when [dir] exists, is
      non-empty and [force] is unset; with [force], scaffold files are
      overwritten but unrelated files are kept. [Ok] lists the written
      paths. *)

  val run : Args.init_spec -> int
end

(** {1 lui dev} *)

module Dev : sig
  type line_kind = Built | Broken | Info

  val classify : string -> line_kind
  (** [classify line] reads one [dune build -w] status line:
      [Built] on ["Success"], [Broken] on ["error"]/["failed"], else
      [Info]. *)

  val exe_path : dir:string -> exe:string -> string
  val run : Args.dev_spec -> int
  (** Spawns [dune build -w] inside the project, (re)launches
      [exe_path] after every successful rebuild, kills it on rebuild
      failure, and tears both down on Ctrl+C or when the watcher
      exits. *)
end

(** {1 lui build} *)

module Build : sig
  val dune_args : release:bool -> string list
  val artifacts : dir:string -> string list
  (** Built executables under [<dir>/_build/default]. *)

  val run : Args.build_spec -> int
end

(** {1 lui package} *)

module Package : sig
  type pack_kind = Pk_macos | Pk_linux | Pk_windows
  type artifact =
    | A_dmg
    | A_tar
    | A_deb
    | A_appimage
    | A_zip
    | A_msix
    | A_nsis

  type plan = { pk : pack_kind; artifact : artifact }

  val string_of_artifact : artifact -> string

  val plan :
    Args.platform_sel -> Args.artifact_fmt -> (plan, string) result
  (** Maps a requested platform + format to the packager the run will
      dispatch to. [Error] names the unsupported combination —
      pure and tested without invoking any tool. *)

  val webview_resources :
    dir:string -> webview:bool -> (Lui_pkg.resource list, string) result
  (** [--webview] contributes [<dir>/web] as one [web] resource entry;
      [Error] when the flag is set but the directory is absent. *)

  val spec_of :
    Args.package_spec -> exe:string -> resources:Lui_pkg.resource list ->
    Lui_pkg.app_spec
  (** Derives the {!Lui_pkg.app_spec} from flags plus project
      defaults (name from the directory basename, version ["0.1.0"],
      bundle id ["app.lui.<name>"], adhoc identity unless [--sign]). *)

  val run : Args.package_spec -> int
  (** bundle -> sign -> artifact through the platform's library,
      printing the produced path. *)
end

(** {1 lui doctor} *)

module Doctor : sig
  type status = Ok of string | Missing | Skip of string

  (** How one check establishes presence — declarative so the report
      stays honest about what was actually probed. *)
  type probe =
    | On_path of string
    | Version_ok of string * string list * int * int * int
    (** tool, args, minimum (major, minor, patch) *)

    | Pkg_config of string
    | Brew of string
    | Cmd_ok of string * string list
    | Any of probe list

  type check = {
    c_name : string;
    c_required : bool;
    c_hint : string;    (** install hint when missing *)
    c_probe : probe;
  }

  val parse_version : string -> (int * int * int) option
  (** First three dot-separated numeric components of a version
      string; ["5.5.0~rc1"] -> [(5,5,0)], ["5.4"] -> [(5,4,0)]. *)

  val version_at_least :
    int * int * int -> int * int * int -> bool

  val first_line : string -> string
  val eval : probe -> status
  val checks_for : Lui_pkg.platform -> check list
  val report : ?platform:Lui_pkg.platform -> unit -> int
  (** Prints OK/MISSING/SKIP per check; exit code is [1] when any
      required check is missing. *)

  val run : unit -> int
end

(** {1 lui keygen} *)

module Keygen : sig
  val default_dir : unit -> string
  (** Per-user key directory: [$XDG_CONFIG_HOME/lui/update-keys],
      [$HOME/.config/lui/update-keys], or [%APPDATA%\\lui\\update-keys]
      on Windows. *)

  val commands :
    alg:Args.key_alg -> priv:string -> pub:string ->
    (string * string list) list
  (** The openssl invocations, in order — factored for testing. *)

  val run : Args.keygen_spec -> int
end

(** {1 Entry point} *)

val main : string list -> int
(** [main argv] parses and dispatches; the executable does
    [exit (main (List.tl (Array.to_list Sys.argv)))]. Exit codes: [0]
    success, [1] a command ran and failed, [2] usage error. *)
