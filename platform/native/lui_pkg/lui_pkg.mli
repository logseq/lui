(** Lui_pkg — packaging and distribution for LUI native apps.

    macOS first: build a .app, sign it, notarize it, wrap it in a DMG,
    and produce/apply file-level deltas between versions. The design is
    platform-agnostic: a {!packager} record per platform, one real
    implementation (macOS), declared stubs elsewhere that answer
    [Unsupported] so other backends can fill them in.

    Every operation returns an {!outcome}: [Ok] on success, [Failed] when
    a tool ran and failed or input was invalid, [Skipped] when a
    precondition is absent (credentials, an optional tool) and nothing
    was attempted, [Unsupported] when the platform has no implementation.

    Credentials are never API parameters. Signing uses an identity name
    or ad-hoc; notarization uses a keychain profile stored with
    [xcrun notarytool store-credentials] or the names of environment
    variables read at submit time. *)

(** {1 Results} *)

type platform = Macos | Linux | Windows | Unknown of string

type failure =
  | Tool_failed of {
      tool : string;
      args : string list;
      status : int;
      output : string;
    }
  | Missing of string  (** A required file or tool is absent. *)
  | Invalid of string  (** Input violates the format or the API. *)

type 'a outcome =
  | Ok of 'a
  | Skipped of string  (** A precondition is absent; nothing attempted. *)
  | Unsupported of string  (** No implementation on this platform yet. *)
  | Failed of failure

val string_of_failure : failure -> string
val string_of_outcome : ('a -> string) -> 'a outcome -> string
val string_of_platform : platform -> string
val host_platform : unit -> platform
val host_arch : unit -> string
(** ["arm64"], ["x86_64"], or the raw [uname -m]. *)

(** {1 Property-list values} *)

type pvalue =
  | P_string of string
  | P_bool of bool
  | P_int of int
  | P_real of float
  | P_data of string
  | P_array of pvalue list
  | P_dict of (string * pvalue) list

(** {1 Application specification} *)

type signing_identity =
  | Adhoc  (** ad-hoc signature ("-"); runs anywhere, no notarization *)
  | Certificate of string  (** keychain identity, e.g.
                               "Developer ID Application: X" *)

(** Notarization credentials. Raw secrets are never API parameters:
    [Apple_id_env] names the environment variables read at submit time,
    [Keychain_profile] is a profile stored with
    [xcrun notarytool store-credentials]. *)
type notarization =
  | Keychain_profile of { profile : string; keychain : string option }
  | Apple_id_env of {
      apple_id_var : string;  (** e.g. "LUI_PKG_APPLE_ID" *)
      password_var : string;  (** app-specific password env var *)
      team_id : string;
    }

type doc_type = {
  doc_name : string option;  (** default: "<EXT> file" of the first ext *)
  role : string;             (** default "Editor" *)
  extensions : string list;
  mime : string list;
}

type resource = {
  res_name : string;  (** install path relative to Contents/Resources *)
  res_src : string;   (** source file, directory or link *)
}

type app_spec = {
  name : string;
  bundle_id : string;
  version : string;            (** semver for CFBundleShortVersionString *)
  build : string option;       (** CFBundleVersion; default [version] *)
  icon : string option;        (** source PNG (square) *)
  executable : string;         (** the built binary *)
  resources : resource list;
  entitlements : (string * pvalue) list;
  helper_entitlements : (string * (string * pvalue) list) list;
    (** per-path overrides for nested code, keyed by path inside the
        bundle (e.g. "Resources/bin/helper"). *)
  identity : signing_identity;
  notarization : notarization option;
  min_system : string;         (** LSMinimumSystemVersion *)
  url_schemes : string list;
  doc_types : doc_type list;
  copyright : string option;
  info_extra : (string * pvalue) list;
  production : bool;           (** hardened runtime + secure timestamp
                                   when signing with a real identity *)
}

type tool_check_unit = {
  tc_tool : string;
  tc_ran : bool;
  tc_ok : bool;
  tc_output : string;
}

type sign_report = {
  signed : string list;       (** bundle-relative paths signed *)
  codesign_verify : tool_check_unit;
  spctl : tool_check_unit option;
}

type notarize_report = {
  nz_submission_id : string option;
  nz_status : string;
  nz_stapled : bool;
  nz_log : string;
}

(** The per-platform packager record: one real implementation, declared
    stubs elsewhere. [pkg_disk_image] is macOS's DMG step. *)
type packager = {
  pkg_platform : platform;
  pkg_bundle : app_spec -> string -> string outcome;
    (** spec -> output dir -> path of the built .app *)
  pkg_sign : app_spec -> string -> sign_report outcome;
    (** spec -> .app path -> report *)
  pkg_notarize : app_spec -> string -> notarize_report outcome;
    (** spec -> dmg/zip path -> report *)
  pkg_disk_image : app_spec -> string -> string -> string outcome;
    (** spec -> .app path -> output dir -> image path *)
}

(** [v_spec ...] assembles an {!app_spec} with the fields a CLI or a
    build script usually leaves alone defaulted. *)
val v_spec :
  name:string ->
  bundle_id:string ->
  version:string ->
  ?build:string ->
  ?icon:string ->
  executable:string ->
  ?resources:resource list ->
  ?entitlements:(string * pvalue) list ->
  ?helper_entitlements:(string * (string * pvalue) list) list ->
  ?identity:signing_identity ->
  ?notarization:notarization ->
  ?min_system:string ->
  ?url_schemes:string list ->
  ?doc_types:doc_type list ->
  ?copyright:string ->
  ?info_extra:(string * pvalue) list ->
  ?production:bool ->
  unit ->
  app_spec

(** {1 Packagers} *)

val macos_packager : packager
val stub_packager : platform -> packager
val packager_for : platform -> packager
val host_packager : unit -> packager

(** {1 Top-level API}

    These dispatch on the host platform's packager. *)

val bundle : app_spec -> dir:string -> string outcome
val sign : app_spec -> string -> sign_report outcome
val notarize : app_spec -> string -> notarize_report outcome
val dmg : app_spec -> string -> dir:string -> string outcome

(** {1 Delta updates}

    Platform-independent: a delta is a file format ("lui delta 1\n" +
    uvarint index length + DEFLATE-compressed JSON index + per-entry
    data). The index lists the new tree — directories, links and files
    with size and SHA-256; each file copies an old file, binary-patches
    it, or is new. *)

val update_pkg :
  from:string ->
  to_:string ->
  old_dir:string ->
  new_dir:string ->
  string ->
  unit outcome
(** [update_pkg ~from ~to_ ~old_dir ~new_dir out] writes the delta file
    [out] updating version [from]'s tree at [old_dir] to [to_]'s at
    [new_dir]. *)

val apply_delta :
  delta:string ->
  from:string ->
  to_:string ->
  old_dir:string ->
  new_dir:string ->
  unit outcome
(** Rebuilds [to_]'s tree at [new_dir] (must not exist), verifying size
    and SHA-256 of every produced file. *)

val delta_info : string -> (string * string * int) outcome
(** (from, to, entry-count) of a delta file. *)

(** Internals exposed to the test suite; not part of the API contract. *)
module Private : sig
  module Fs : sig
    type kind = Dir | File | Link | Other | Absent

    val kind_of : string -> kind
    val is_dir : string -> bool
    val exists : string -> bool
    val mkdir_p : ?perm:int -> string -> unit
    val rm_rf : string -> unit
    val read_file : string -> string
    val write_file : ?perm:int -> string -> string -> unit
    val copy_file : src:string -> dst:string -> unit
    val install : src:string -> dst:string -> unit
    val walk : string -> (string * kind) list
    val file_size : string -> int option
    val temp_dir : ?prefix:string -> ?parent:string -> unit -> string
  end

  module Proc : sig
    type ran = { status : int; stdout : string; stderr : string }

    val run : ?stdin:string -> string -> string list -> ran
    val which : string -> string option
    val check : string -> string list -> (ran, failure) result
    val check_o : string -> string list -> string outcome
  end

  module Sha256 : sig
    val string : string -> string
    val digest_string : string -> string
    val file : string -> string
  end

  module Crc32 : sig
    val string : string -> int32
  end

  module Adler32 : sig
    val string : string -> int32
  end

  module Varint : sig
    val append_uvarint : Buffer.t -> int -> unit
    val append_varint : Buffer.t -> int -> unit
    val uvarint : string -> int -> (int * int) option
    val varint : string -> int -> (int * int) option
  end

  module Deflate : sig
    exception Bad_stream of string

    val deflate : string -> string
    val inflate : ?off:int -> ?len:int -> string -> string
    val zlib : string -> string
  end

  module Bsdiff : sig
    exception Bad_patch

    val diff : string -> string -> string
    val patch : old_data:string -> patch_data:string -> int -> string
  end

  module Plist : sig
    type value = pvalue

    val xml : (string * value) list -> string
    val binary : (string * value) list -> string
  end

  module Ds_store : sig
    type record

    val dmg_store : string -> string
  end

  module Mach_o : sig
    val is_macho : string -> bool
    val is_signed : string -> bool
  end

  module Info_plist : sig
    val build : app_spec -> exe_name:string -> icon_name:string option ->
      (string * pvalue) list
    val plist : app_spec -> exe_name:string -> icon_name:string option ->
      string
  end

  module Iconset : sig
    val icns : src:string -> dst:string -> string outcome
  end

  module Bundle : sig
    val bundle_icon : string
    val write : app_spec -> dir:string -> string outcome
  end

  module Sign : sig
    type signable = {
      s_path : string;
      s_rel : string;
      s_bundle : bool;
      s_signed : bool;
    }

    val bundle_extensions : string list
    val is_bundle_dir : string -> bool
    val enumerate : string -> signable list
    val identity_string : signing_identity -> string
    val codesign_args :
      identity:signing_identity ->
      entitlements:string option ->
      production:bool ->
      string ->
      string list
    val nested_args :
      identity:signing_identity ->
      entitlements:string option ->
      production:bool ->
      string list
    val sign : app_spec -> string -> sign_report outcome
  end

  module Notarize : sig
    val creds_args :
      notarization option -> (string list, [ `No_creds | `Missing_env of string list ]) result
    val submission_payload : string -> string outcome
    val payload_valid : string -> bool
    val parse_submission : string -> string * string * string
    val notarize : app_spec -> string -> notarize_report outcome
  end

  module Dmg : sig
    val fs_name : string -> string
    val dmg_name : app_spec -> arch:string -> string
    val hdiutil_busy : string -> bool
    val contains_sub : string -> string -> bool
    val create : app_spec -> string -> dir:string -> arch:string -> string outcome
  end

  module Delta : sig
    exception Damaged of string

    type entry = {
      path : string;
      dir : bool;
      link : string;
      mode : int;
      size : int;
      sha256 : string;
      from : string;
      data : int;
    }

    val magic : string
    val max_diff : int
    val max_index : int
    val is_file : entry -> bool
    val valid_rel_path : string -> bool
    val entry_json : entry -> Yojson.Safe.t
    val write :
      from:string -> to_:string -> old_dir:string -> new_dir:string ->
      string -> entry list
    val parse_index : string -> string * string * entry list * int
    val check_index : entry list -> data_start:int -> size:int -> unit
    val apply :
      delta:string -> from:string -> to_:string -> old_dir:string ->
      new_dir:string -> unit outcome
  end
end
