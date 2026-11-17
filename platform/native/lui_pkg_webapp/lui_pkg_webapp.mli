(** Lui_pkg_webapp — packaging for webview-shell apps.

    Wraps {!Lui_pkg} (macOS [.app] → sign → DMG),
    {!Lui_pkg_linux} (AppDir → tarball) and
    {!Lui_pkg_windows} (portable dir → zip) so a {!Lui_webapp.spec}
    plus a built [lui_webapp] launcher executable becomes a platform
    installer. Nothing new is added to {!Lui_pkg.app_spec}: the web
    payload rides on the existing [resources] field — the assets as
    resource ["web"], the serialized spec as ["webapp.json"] — which
    each packager already installs at the documented place:

    - macOS: [Contents/Resources/web] and [Contents/Resources/webapp.json]
    - Windows: [web\\] and [webapp.json] beside [<name>.exe]
    - Linux: [usr/share/<app>/web] and [usr/share/<app>/webapp.json]
      inside the AppDir

    The embedded spec is the {!packaged_spec}: [web_dir] rewritten to
    the resource name ["web"] so {!Lui_webapp.boot} resolves assets
    relative to the spec file in every layout.

    {b Deltas.} Web assets are ordinary bundle files, so the shared
    {!Lui_pkg.update_pkg} / {!Lui_pkg.apply_delta} format covers them:
    a version bump that only changes [web/index.html] produces a
    delta that swaps exactly that file. *)

type product = {
  app : string;
    (** the bundle tree: [.app], [.AppDir] or portable dir *)
  artifact : string option;
    (** the distributable when one was produced: DMG, tarball or zip *)
}

(** {1 Spec mapping} *)

val web_resource_name : string
(** ["web"] — the resource name the asset directory installs under. *)

val packaged_spec : Lui_webapp.spec -> Lui_webapp.spec
(** The spec written into the bundle: identical but [web_dir] is
    ["web"] and [icon] is dropped (the packager already consumed it
    into the platform icon formats). *)

val app_spec :
  ?build:string ->
  ?identity:Lui_pkg.signing_identity ->
  ?notarization:Lui_pkg.notarization ->
  ?min_system:string ->
  ?production:bool ->
  ?info_extra:(string * Lui_pkg.pvalue) list ->
  spec:Lui_webapp.spec ->
  shell_exe:string ->
  spec_json:string ->
  unit ->
  Lui_pkg.app_spec
(** [app_spec ~spec ~shell_exe ~spec_json] maps a webapp spec onto the
    shared {!Lui_pkg.app_spec}: [shell_exe] is the launch binary (a
    built [lui_webapp] launcher), [spec_json] the path of a
    {!packaged_spec} serialization, and [resources] gains the ["web"]
    and ["webapp.json"] entries. *)

val validate : spec:Lui_webapp.spec -> shell_exe:string ->
  unit Lui_pkg.outcome
(** Input checks shared by every bundle: the {!Lui_webapp.validate}
    shape rules plus [shell_exe], [web_dir] and [web_dir/entry]
    existing on disk. *)

val with_packaged_spec :
  Lui_webapp.spec -> (string -> 'a Lui_pkg.outcome) -> 'a Lui_pkg.outcome
(** [with_packaged_spec spec f] writes {!packaged_spec} to a fresh
    temporary [webapp.json], calls [f] with its path, and removes the
    temp dir when [f] returns. *)

(** {1 Bundles} *)

val bundle_macos :
  ?identity:Lui_pkg.signing_identity ->
  ?sign:bool ->
  ?image:bool ->
  spec:Lui_webapp.spec ->
  shell_exe:string ->
  dir:string ->
  unit ->
  product Lui_pkg.outcome
(** macOS: [.app] bundle → adhoc signature → DMG. [~sign:false] skips
    signing (the bundle still verifies nothing — useful only for
    inspection); [~image:false] skips the DMG. The app is signed
    ad-hoc by default so it launches anywhere. *)

val bundle_linux :
  ?identity:Lui_pkg.signing_identity ->
  ?image:bool ->
  spec:Lui_webapp.spec ->
  shell_exe:string ->
  dir:string ->
  unit ->
  product Lui_pkg.outcome
(** Linux: [.AppDir] ([usr/bin] exe, desktop entry,
    [usr/share/<app>/web] assets) → compressed tarball. *)

val bundle_windows :
  ?identity:Lui_pkg.signing_identity ->
  ?arch:string ->
  ?image:bool ->
  spec:Lui_webapp.spec ->
  shell_exe:string ->
  dir:string ->
  unit ->
  product Lui_pkg.outcome
(** Windows: portable app dir ([<name>.exe], manifest, [web\\],
    [webapp.json]) → zip via the pure-OCaml writer. *)

val bundle :
  ?identity:Lui_pkg.signing_identity ->
  ?sign:bool ->
  ?image:bool ->
  ?arch:string ->
  spec:Lui_webapp.spec ->
  shell_exe:string ->
  dir:string ->
  unit ->
  product Lui_pkg.outcome
(** [bundle ~spec ~shell_exe ~dir] runs the host platform's flow and
    answers [Unsupported] on an unknown OS. Signing uses [~identity]
    (default ad-hoc). *)
