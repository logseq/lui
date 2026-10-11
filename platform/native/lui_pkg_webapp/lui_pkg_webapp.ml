(* Lui_pkg_webapp — packaging for webview-shell apps: a webapp spec
   plus a built lui_webapp launcher in, a platform installer out.
   The web payload travels as ordinary bundle resources so every
   packager — and the shared delta format — covers it for free. *)

module L = Lui_pkg
module P = Lui_pkg.Private

let ( / ) = Filename.concat
let fmt = Printf.sprintf

let ( let* ) o f =
  match o with
  | L.Ok v -> f v
  | L.Skipped s -> L.Skipped s
  | L.Unsupported s -> L.Unsupported s
  | L.Failed f -> L.Failed f

type product = {
  app : string;
  artifact : string option;
}

let web_resource_name = "web"
let spec_resource_name = Lui_webapp.spec_file_name

(** {1 Spec mapping} *)

let packaged_spec (s : Lui_webapp.spec) : Lui_webapp.spec =
  { s with web_dir = web_resource_name; icon = None }

let validate ~spec ~shell_exe : unit L.outcome =
  match Lui_webapp.validate spec with
  | Error m -> L.Failed (L.Invalid m)
  | Ok () ->
    (match P.Fs.kind_of shell_exe with
     | P.Fs.File ->
       (match P.Fs.kind_of spec.Lui_webapp.web_dir with
        | P.Fs.Dir ->
          let entry =
            spec.Lui_webapp.web_dir / spec.Lui_webapp.entry
          in
          (match P.Fs.kind_of entry with
           | P.Fs.File -> Ok ()
           | _ -> L.Failed (L.Missing (fmt "entry %s" entry)))
        | _ ->
          L.Failed
            (L.Missing (fmt "web_dir %s" spec.Lui_webapp.web_dir)))
     | _ -> L.Failed (L.Missing (fmt "shell exe %s" shell_exe)))

let app_spec ?build ?(identity = L.Adhoc) ?notarization
    ?(min_system = "12.0") ?(production = false) ?(info_extra = [])
    ~(spec : Lui_webapp.spec) ~shell_exe ~spec_json () : L.app_spec =
  L.v_spec ~name:spec.name ~bundle_id:spec.app_id
    ~version:spec.version ?build ?icon:spec.icon ~executable:shell_exe
    ~resources:
      [ { res_name = web_resource_name; res_src = spec.web_dir };
        { res_name = spec_resource_name; res_src = spec_json } ]
    ~identity ?notarization ~min_system ~production ~info_extra ()

let with_packaged_spec (spec : Lui_webapp.spec) f =
  let tmp = P.Fs.temp_dir ~prefix:"lui-webapp-spec-" () in
  Fun.protect
    ~finally:(fun () -> P.Fs.rm_rf tmp)
    (fun () ->
       let p = tmp / spec_resource_name in
       match Lui_webapp.write_spec (packaged_spec spec) p with
       | Ok () -> f p
       | Error m -> L.Failed (L.Invalid m))

(** {1 Bundles} *)

(* An artifact step that may legitimately skip (missing optional tool)
   demotes to artifact=None; a real failure aborts the flow. *)
let artifact o =
  match o with
  | L.Ok p -> L.Ok (Some p)
  | L.Skipped _ | L.Unsupported _ -> L.Ok None
  | L.Failed f -> L.Failed f

let bundle_macos ?(identity = L.Adhoc) ?(sign = true) ?(image = true)
    ~spec ~shell_exe ~dir () =
  let pk = L.macos_packager in
  let* () = validate ~spec ~shell_exe in
  with_packaged_spec spec (fun spec_json ->
      let pkg = app_spec ~identity ~spec ~shell_exe ~spec_json () in
      let* app = pk.L.pkg_bundle pkg dir in
      let* () =
        if not sign then Ok ()
        else
          let* (_ : L.sign_report) = pk.L.pkg_sign pkg app in
          Ok ()
      in
      let* image =
        if not image then Ok None
        else artifact (pk.L.pkg_disk_image pkg app dir)
      in
      Ok { app; artifact = image })

let bundle_linux ?(identity = L.Adhoc) ?(image = true) ~spec
    ~shell_exe ~dir () =
  let* () = validate ~spec ~shell_exe in
  with_packaged_spec spec (fun spec_json ->
      let pkg = app_spec ~identity ~spec ~shell_exe ~spec_json () in
      let* app = Lui_pkg_linux.bundle pkg ~dir in
      let* tar =
        if not image then Ok None
        else artifact (Lui_pkg_linux.tarball pkg app ~dir)
      in
      Ok { app; artifact = tar })

let bundle_windows ?(identity = L.Adhoc) ?(arch = L.host_arch ())
    ?(image = true) ~spec ~shell_exe ~dir () =
  let* () = validate ~spec ~shell_exe in
  with_packaged_spec spec (fun spec_json ->
      let pkg = app_spec ~identity ~spec ~shell_exe ~spec_json () in
      let* app = Lui_pkg_windows.bundle ~arch pkg ~dir in
      let* zip =
        if not image then Ok None
        else
          artifact
            (Lui_pkg_windows.package ~fmt:Lui_pkg_windows.Zip pkg app
               ~dir)
      in
      Ok { app; artifact = zip })

let bundle ?(identity = L.Adhoc) ?(sign = true) ?(image = true) ?arch
    ~spec ~shell_exe ~dir () : product L.outcome =
  match L.host_platform () with
  | L.Macos ->
    bundle_macos ~identity ~sign ~image ~spec ~shell_exe ~dir ()
  | L.Linux -> bundle_linux ~identity ~image ~spec ~shell_exe ~dir ()
  | L.Windows ->
    bundle_windows ~identity ?arch ~image ~spec ~shell_exe ~dir ()
  | L.Unknown s ->
    L.Unsupported (fmt "no webapp packager on platform %s" s)
