(** Lui_pkg_windows — Windows implementation of the {!Lui_pkg.packager}
    contract.

    The unit of installation is a portable app directory: the
    executable, a generated sidecar manifest, its icon and every
    resource side by side, the layout the reference flow calls the
    stage. Packages distribute that directory as a zip archive written
    by a pure-OCaml writer (the DEFLATE and CRC-32 primitives already
    live in {!Lui_pkg}; no archiver, shell or runtime dependency is
    needed — see {!Private.Zip}). An .msix is produced through makeappx
    and an installer through makensis when those tools are installed;
    both answer {!Lui_pkg.Skipped} with the reason otherwise.

    Signing goes through signtool from the Windows SDK. A
    {!Lui_pkg.Certificate} identity names a .pfx path, a certificate
    SHA-1 thumbprint, or an environment variable holding one of those —
    the password is only ever read from the
    [LUI_PKG_WINDOWS_CERT_PASSWORD] environment variable, never from an
    API parameter. Windows has no notarization equivalent.

    {b Deltas and file locks.} Update manifests reuse
    {!Lui_pkg.update_pkg} / {!Lui_pkg.apply_delta} unchanged: the delta
    wire format is platform-independent. On Windows a running app's
    files cannot be overwritten, so an update is never applied in
    place — {!apply_delta} already insists that its target does not
    exist. Apply the delta into a staging directory beside the install
    (the [<install>.update] convention {!Lui_updater} uses) and swap
    top-level entries with renames, the same recovery path
    {!Lui_updater}'s [Dir] layout performs. *)

type package_format =
  | Zip  (** pure-OCaml zip writer; always available *)
  | Msix  (** makeappx from the Windows SDK *)
  | Nsis  (** makensis installer compiler *)

val string_of_package_format : package_format -> string

(** {1 The packager} *)

val windows_packager : Lui_pkg.packager
(** The Windows slot of the contract:

    - [pkg_bundle]: {!bundle} — the portable directory
    - [pkg_sign]: {!sign} — signtool over unsigned PE images
    - [pkg_notarize]: always [Skipped]; Windows has no notarization
    - [pkg_disk_image]: [package ~fmt:Zip] — the zip is the
      distributable and the update payload alike *)

(** {1 Bundling} *)

val bundle : Lui_pkg.app_spec -> dir:string -> string Lui_pkg.outcome
(** [bundle spec ~dir] writes [<dir>/<name>-<version>-windows-<arch>]
    and returns its path. The directory holds [<name>.exe] (a copy of
    [spec.executable]), [<name>.exe.manifest] ({!manifest}),
    [<name>.ico] when [spec.icon] is set, and every resource of
    [spec.resources] installed at its [res_name] relative to the
    directory root. *)

val portable_dir_name : Lui_pkg.app_spec -> arch:string -> string
(** The directory name [bundle] produces. *)

val manifest : Lui_pkg.app_spec -> string
(** The sidecar application manifest: assemblyIdentity, common
    controls v6, Windows 10+ compatibility, PerMonitorV2 DPI awareness
    and UTF-8 as the active code page — everything a self-drawn app
    needs without a resource-embedded manifest. *)

(** {1 Packaging} *)

val package :
  ?fmt:package_format ->
  ?arch:string ->
  Lui_pkg.app_spec ->
  string ->
  dir:string ->
  string Lui_pkg.outcome
(** [package ~fmt spec bundle ~dir] writes the distributable of
    [bundle] (a directory {!bundle} made) into [dir] and returns its
    path. [Zip] is the default and always succeeds; [Msix] and [Nsis]
    answer [Skipped] when makeappx/makensis is absent or — for [Msix]
    — the spec has no icon (a package logo is required). *)

val zip_name : Lui_pkg.app_spec -> arch:string -> string
val msix_name : Lui_pkg.app_spec -> arch:string -> string
val installer_name : Lui_pkg.app_spec -> arch:string -> string

val appx_manifest : Lui_pkg.app_spec -> arch:string -> string
(** The AppxManifest.xml {!package ~fmt:Msix} stages next to the app.
    The publisher is a placeholder ([CN=<name>]); a real package is
    re-signed anyway, and signing rewrites the subject requirement to
    the certificate's publisher. *)

val nsis_script :
  Lui_pkg.app_spec -> src:string -> out:string -> arch:string -> string
(** The .nsi {!package ~fmt:Nsis} feeds makensis: per-user install
    into [$LOCALAPPDATA\Programs], MUI2 pages, start-menu shortcut,
    Add/Remove Programs registration and document-type associations
    from [spec.doc_types]. *)

(** {1 Signing} *)

val sign : Lui_pkg.app_spec -> string -> Lui_pkg.sign_report Lui_pkg.outcome
(** [sign spec bundle] signs every unsigned PE image (.exe, .dll, …)
    inside [bundle] with signtool, then verifies the main executable
    with [signtool verify /pa]. Already-signed images keep their
    publisher signature. [Skipped] when signtool is not installed,
    when [spec.identity] is [Adhoc], or when the certificate does not
    resolve. [spctl] of the report is always [None] — no equivalent. *)

(** {1 Tool discovery} *)

val find_tool : string -> string option
(** [find_tool "signtool"] searches PATH with PATHEXT extensions and
    returns the resolved path. *)

val sdk_tool : string -> string option
(** [sdk_tool "signtool.exe"] searches the newest Windows Kits bin
    directory for the host architecture, as the SDK leaves its tools
    off PATH. *)

val powershell : unit -> string option
(** powershell.exe, used for the optional Compress-Archive path. *)

val powershell_run : string -> Lui_pkg.Private.Proc.ran
(** [powershell_run script] runs a script through
    [powershell -NoProfile -NonInteractive -EncodedCommand]; the
    UTF-16LE/base64 encoding keeps quoting out of the command line. *)

(** {1 Delta updates}

    Shared with every platform; see the module comment for the
    staging-only apply discipline Windows file locking demands. *)

val update_pkg :
  from:string -> to_:string -> old_dir:string -> new_dir:string ->
  string -> unit Lui_pkg.outcome

val apply_delta :
  delta:string -> from:string -> to_:string -> old_dir:string ->
  new_dir:string -> unit Lui_pkg.outcome

val stage_dir_for : string -> string
(** [stage_dir_for install_dir] names the staging directory beside an
    install — [<install>.update], the {!Lui_updater} convention. *)

(** Internals exposed to the test suite; not part of the API contract. *)
module Private : sig
  module Proc : sig
    type ran = Lui_pkg.Private.Proc.ran

    val dev_null : string
    val run : ?stdin:string -> string -> string list -> ran
    val which : string -> string option
    val check : string -> string list -> (ran, Lui_pkg.failure) result
    val check_o : string -> string list -> string Lui_pkg.outcome
  end

  module Zip : sig
    exception Bad of string

    type entry = {
      name : string;
      dir : bool;
      mode : int;
      mtime : float;
      crc : int32;
      data : string;
    }

    val max_size : int
    val write : entries:entry list -> out:string -> unit
    val write_dir : src:string -> out:string -> unit
    val dos_time : float -> int * int
    (* [list z] returns (name, uncompressed size, method) per entry. *)
    val list : string -> (string * int * int) list
    val extract : string -> string -> string option
    val extract_all : src:string -> dst:string -> unit
  end

  module Pe : sig
    (** [inspect path] returns [(is_pe, signed)] — an MZ/PE image
        whose certificate table is non-empty counts as signed. *)
    val inspect : string -> bool * bool
    val is_pe : string -> bool
    val is_signed : string -> bool
  end

  module Ico : sig
    (** Wrap a PNG into an .ico container (PNG-in-ICO, Windows Vista+). *)
    val of_png : string -> string Lui_pkg.outcome
    val png_dimensions : string -> (int * int) option
  end

  module Bundle : sig
    val write : Lui_pkg.app_spec -> dir:string -> string Lui_pkg.outcome
    val exe_name : Lui_pkg.app_spec -> string
  end

  module Manifest : sig
    val identity_name : Lui_pkg.app_spec -> string
    val version4 : string -> int * int * int * int
    val app_xml : Lui_pkg.app_spec -> string
    val appx_xml : Lui_pkg.app_spec -> arch:string -> string
  end

  module Sign : sig
    val cert_args : Lui_pkg.signing_identity ->
      (string list, [ `Skipped of string ]) result
    val signtool : unit -> string option
    val sign : Lui_pkg.app_spec -> string -> Lui_pkg.sign_report Lui_pkg.outcome
  end

  module Nsis : sig
    val script : Lui_pkg.app_spec -> src:string -> out:string ->
      arch:string -> string
    val makensis : unit -> string option
    val make : Lui_pkg.app_spec -> string -> dir:string ->
      arch:string -> string Lui_pkg.outcome
  end

  module Msix : sig
    val makeappx : unit -> string option
    val make : Lui_pkg.app_spec -> string -> dir:string ->
      arch:string -> string Lui_pkg.outcome
  end

  module Ps_zip : sig
    (** PowerShell Compress-Archive fallback — the pure writer stays
        the default; this exists for hosts whose policy forbids
        writing archives from unsigned code paths. *)
    val compress_archive : src:string -> out:string -> string Lui_pkg.outcome
  end
end
