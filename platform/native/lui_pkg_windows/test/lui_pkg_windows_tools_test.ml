(* lui_pkg_windows tools suite — runs on mingw64 only (the dune
   enabled_if): real tool discovery and real tool invocations.

   What is exercised depends on what is installed on the host; every
   missing tool reports its absence in the test output rather than
   failing — discovery is the contract being tested, not the host's
   configuration. PowerShell is the expected find on a stock Windows
   box; signtool/makeappx/makensis report found-or-missing either way.
   No test-framework dependency: plain counted assertions. *)

module L = Lui_pkg
module P = Lui_pkg.Private
module W = Lui_pkg_windows
module WP = Lui_pkg_windows.Private

let failures = ref 0
let total = ref 0

let ok name cond =
  incr total;
  if not cond then (
    incr failures;
    Printf.printf "FAIL %s\n%!" name)

let fail s =
  incr failures;
  Printf.printf "FAIL %s\n%!" s;
  raise (Failure s)

let () =
  at_exit (fun () ->
      Printf.printf "%d checks, %d failures\n%!" !total !failures;
      if !failures > 0 then exit 1)

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui-pkg-wintools-" ()

let report name = function
  | Some p ->
    Printf.printf "  %-16s found: %s\n%!" name p;
    incr total;
    true
  | None ->
    Printf.printf "  %-16s MISSING\n%!" name;
    incr total;
    false

let test_tool_discovery () =
  Printf.printf "tool discovery on %s:\n%!" Sys.os_type;
  let hits =
    [
      report "powershell" (W.powershell ());
      report "signtool" (WP.Sign.signtool ());
      report "makeappx" (WP.Msix.makeappx ());
      report "makensis" (WP.Nsis.makensis ());
      report "7z" (W.find_tool "7z");
      report "zip" (W.find_tool "zip");
    ]
  in
  ok "powershell found" (List.hd hits);
  ok "find_tool powershell" (Option.is_some (W.find_tool "powershell"))

let test_which_semantics () =
  (* a name carrying its extension resolves as given *)
  (match W.find_tool "powershell.exe" with
   | Some _ -> incr total
   | None -> fail "powershell.exe not found by explicit-extension name");
  (* an absolute path resolves itself *)
  match W.find_tool Sys.executable_name with
  | Some _ -> incr total
  | None -> fail "absolute path not resolved"

(* A fabricated zip is expanded by the platform's own Expand-Archive:
   interop between the pure-OCaml writer and Windows. *)
let test_expand_archive_interop () =
  let base = tmp_dir () in
  let src = Filename.concat base "src" in
  P.Fs.mkdir_p (Filename.concat src "sub");
  P.Fs.write_file (Filename.concat src "a.txt") "alpha\n";
  P.Fs.write_file
    (Filename.concat src "sub/b.bin")
    (String.init 3000 (fun i -> Char.chr (i mod 251)));
  let z = Filename.concat base "out.zip" in
  WP.Zip.write_dir ~src ~out:z;
  let dst = Filename.concat base "expanded" in
  let script =
    Printf.sprintf
      "Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force; \
       if (-not (Test-Path '%s')) { exit 3 }; \
       $a = Get-Content -Raw '%s'; \
       if ($a -ne \"alpha`n\") { exit 4 }; exit 0"
      z dst
      (Filename.concat (Filename.concat dst "sub") "b.bin")
      (Filename.concat dst "a.txt")
  in
  let r = W.powershell_run script in
  ok
    (Printf.sprintf "expand rc=%d out=%s" r.status
       (String.escaped (r.stdout ^ r.stderr)))
    (r.status = 0);
  let back = P.Fs.read_file (Filename.concat dst "a.txt") in
  if back <> "alpha\n" then
    fail (Printf.sprintf "round-trip file: got %S" back)
  else incr total;
  P.Fs.rm_rf base

(* Compress-Archive output must read back through the pure reader. *)
let test_compress_archive () =
  let base = tmp_dir () in
  let src = Filename.concat base "src" in
  P.Fs.mkdir_p src;
  P.Fs.write_file (Filename.concat src "c.txt") "see me\n";
  let z = Filename.concat base "ps.zip" in
  (match WP.Ps_zip.compress_archive ~src ~out:z with
   | L.Ok _ -> (
     match WP.Zip.extract z "c.txt" with
     | Some "see me\n" -> incr total
     | _ -> (
       (* Compress-Archive may nest entries under the dir name *)
       match WP.Zip.extract z "src/c.txt" with
       | Some "see me\n" -> incr total
       | _ ->
         let names =
           String.concat ","
             (List.map (fun (n, _, _) -> n) (WP.Zip.list z))
         in
         fail ("ps zip lacks c.txt; entries: " ^ names)))
   | L.Skipped s -> fail ("powershell skipped: " ^ s)
   | L.Failed f -> fail (L.string_of_failure f)
   | L.Unsupported s -> fail s);
  P.Fs.rm_rf base

let () =
  test_tool_discovery ();
  test_which_semantics ();
  test_expand_archive_interop ();
  test_compress_archive ()
