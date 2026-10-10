(** Lui_pkg_linux — Linux packaging for LUI native apps.

    Fills the {!Lui_pkg.packager} contract on Linux:

    - {b bundle}: an AppDir tree — [usr/bin/<exe>], a desktop entry under
      [usr/share/applications] plus a copy at the AppDir root, hicolor
      icons, a MIME package when the spec declares file types, the
      spec's resources under [usr/share/<app>], and an [AppRun]
      launcher.
      The result feeds appimagetool, a tar archive, or a .deb payload.
    - {b package}: a portable tar archive (zstd when the tool is
      installed, gzip next, plain tar last), an AppImage when
      [appimagetool] is in PATH, or a .deb when [dpkg-deb] is.
      [pkg_disk_image] maps to {!tarball}: it always produces a
      distributable artifact. The other formats are opt-in calls that
      answer [Skipped] with the missing tool named.
    - {b sign/notarize}: Linux has no system signing or notarization
      step; the slots answer [Unsupported].

    Delta updates are the shared {!Lui_pkg} format; on Linux the old and
    new trees are AppDirs. *)

val linux_packager : Lui_pkg.packager

val bundle : Lui_pkg.app_spec -> dir:string -> string Lui_pkg.outcome
(** [bundle spec ~dir] builds [<dir>/<name>.AppDir] and returns its
    path. Runs [desktop-file-validate] on the entry when the tool is
    installed. *)

val tarball : Lui_pkg.app_spec -> string -> dir:string -> string Lui_pkg.outcome
(** [tarball spec appdir ~dir] writes
    [<dir>/<name>-<version>-linux-<arch>.tar.<ext>] with [ext] resolved
    by the compressor chain [zstd > gzip > none]. Fails when [tar] is
    absent or [appdir] is not an AppDir. *)

val appimage : Lui_pkg.app_spec -> string -> dir:string -> string Lui_pkg.outcome
(** [appimage spec appdir ~dir] runs [appimagetool appdir out] and
    returns the .AppImage path; [Skipped] when appimagetool is not
    installed. *)

val deb : Lui_pkg.app_spec -> string -> dir:string -> string Lui_pkg.outcome
(** [deb spec appdir ~dir] builds [<name>_<version>_<arch>.deb] with
    [dpkg-deb]: payload in [/opt/<name>], a [/usr/bin] launcher link,
    desktop entry and icons registered. [Skipped] when dpkg-deb is not
    installed. *)

val probe : unit -> (string * string option) list
(** [(tool, resolved path)] for every external tool this module can
    call, in fallback order. *)

val update_pkg :
  from:string -> to_:string -> old_dir:string -> new_dir:string ->
  string -> unit Lui_pkg.outcome
(** Shared delta write; [old_dir]/[new_dir] are AppDir trees. *)

val apply_delta :
  delta:string -> from:string -> to_:string -> old_dir:string ->
  new_dir:string -> unit Lui_pkg.outcome
(** Rebuilds [to_]'s AppDir at [new_dir], verifying size and SHA-256 of
    every produced file. *)

val delta_info : string -> (string * string * int) Lui_pkg.outcome

(** Internals exposed to the test suite; not part of the API contract. *)
module Private : sig
  val slugify : string -> string
  val exe_name : Lui_pkg.app_spec -> string
  val appdir_name : Lui_pkg.app_spec -> string
  val desktop_name : Lui_pkg.app_spec -> string
  val icon_name : Lui_pkg.app_spec -> string
  val mime_entries : Lui_pkg.app_spec -> string list
  val desktop_entry : Lui_pkg.app_spec -> exec:string -> icon:string option -> string
  val mime_package : Lui_pkg.app_spec -> string
  val png_size : string -> (int * int) option
  val deb_arch : string -> string option
  val deb_version : string -> string
  val archive_name : Lui_pkg.app_spec -> arch:string -> ext:string -> string
  val appimage_name : Lui_pkg.app_spec -> arch:string -> string
  val deb_name : Lui_pkg.app_spec -> arch:string -> string
  val control_text : Lui_pkg.app_spec -> arch:string -> installed_kb:int -> string
  val sh_quote : string -> string
  val valid_appdir : string -> bool
end
