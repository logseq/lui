(* webview-shell — boots a built LUI web bundle inside the native
   webview shell and exercises the JS <-> OCaml bridge.

   Wire format: the page talks to native by posting one JSON object
   per [window.webkit.messageHandlers.lui_wv.postMessage] call, which
   arrives here as one [on_message] string; native talks to the page by
   [eval]uating JavaScript (evaluateJavaScript). Same shape as mygo's
   bridge (its "mygo" handler), with the handler name [lui_wv] that
   {!Lui_webview} registers.

   After the first load finishes the shell installs a small page-side
   hook ([bridge_js]): it posts a "hello" message, forwards document
   clicks as {"kind":"click",...}, and mounts a badge element that the
   OCaml side updates in reply — a visible two-way round trip that
   needs no changes to the web build itself.

   Usage:
     main.exe [WEBAPP_JSON]

   The default spec boots the release bundle produced by
   tooling/build_web_release.mjs (see run.sh). *)

let default_spec = "examples/components/webview-shell/webapp.json"

let eval_ref : (string -> unit) option ref = ref None
let clicks = ref 0

let js_string s = Yojson.Safe.to_string (`String s)

(* native -> page: rewrite the badge's text. *)
let set_badge text =
  match !eval_ref with
  | Some eval ->
    eval
      ("var b=document.getElementById('lui-shell-badge');if(b){b.textContent="
       ^ js_string text ^ ";}")
  | None -> ()

(* Page-side hook, installed by the first [eval] after Did_finish. The
   guard on [lui_wv] makes it a no-op inside a plain browser (the
   degrade path), where no message handler exists. *)
let bridge_js =
  "(function(){\
   if(window.__lui_shell)return;\
   var h=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.lui_wv;\
   var post=function(o){if(h)h.postMessage(JSON.stringify(o));};\
   window.__lui_shell={clicks:0,post:post};\
   var b=document.createElement('div');\
   b.id='lui-shell-badge';\
   b.textContent='native shell: installing bridge';\
   b.style.cssText='position:fixed;right:12px;bottom:12px;z-index:2147483647;'\
   +'padding:6px 10px;border-radius:6px;background:#245;color:#fff;'\
   +'font:12px -apple-system,sans-serif;box-shadow:0 1px 4px rgba(0,0,0,.4)';\
   document.body.appendChild(b);\
   document.addEventListener('click',function(ev){\
   window.__lui_shell.clicks+=1;\
   post({kind:'click',n:window.__lui_shell.clicks,x:ev.clientX,y:ev.clientY});\
   },true);\
   post({kind:'hello',title:document.title,href:location.href});\
   })();"

let on_ready ~eval =
  eval_ref := Some eval;
  eval bridge_js;
  set_badge "native shell: bridge installed"

let on_message payload =
  let kind =
    try
      match Yojson.Safe.from_string payload with
      | `Assoc _ as j ->
        let open Yojson.Safe.Util in
        (match j |> member "kind" with
         | `String s -> Some s
         | _ -> None)
      | _ -> None
    with Yojson.Json_error _ -> None
  in
  match kind with
  | Some "hello" ->
    Printf.printf "shell <- page: hello %s\n%!" payload;
    set_badge "native shell: bridge connected"
  | Some "click" ->
    incr clicks;
    Printf.printf "shell <- page: %s\n%!" payload;
    set_badge (Printf.sprintf "native shell: click #%d" !clicks)
  | _ -> Printf.printf "shell <- page: %s\n%!" payload

let usage () =
  Printf.printf
    "webview-shell — run a LUI web bundle in the native webview shell\n\
     usage: %s [WEBAPP_JSON]\n\
     default: %s\n"
    Sys.argv.(0) default_spec

(* The window record of {!Lui_webapp.spec} maps field-for-field onto
   the shell's lower-level type. *)
let sdl_window (w : Lui_webapp.window) : Lui_webapp.Sdl_shell.window =
  { width = w.width; height = w.height; resizable = w.resizable;
    min_width = w.min_width; min_height = w.min_height }

let () =
  let spec_path =
    match Array.to_list Sys.argv with
    | _ :: ("--help" | "-h") :: _ ->
      usage ();
      exit 0
    | _ :: p :: _ -> p
    | _ -> default_spec
  in
  match Lui_webapp.read_spec spec_path with
  | Error e ->
    prerr_endline ("webview-shell: " ^ e);
    exit 2
  | Ok spec ->
    let base = Filename.dirname spec_path in
    (match Lui_webapp.prepare ~base spec with
     | Error e ->
       prerr_endline ("webview-shell: " ^ e);
       exit 2
     | Ok prep ->
       if Lui_webapp.Sdl_shell.available () then
         (* A [File] source loads the entry with
            [loadFileURL:allowingReadAccessToURL:], which grants the
            page read access to its own directory — the release
            bundle's ./app.js, ./lui.css and ./icons resolve. The
            [Html]-with-file-base path that {!Lui_webapp.entry_source}
            prefers cannot fetch file:// subresources in WKWebView,
            so it only suits self-contained pages. *)
         match
           Lui_webapp.Sdl_shell.run ~window:(sdl_window prep.prep_spec.window)
             ~title:prep.prep_spec.name
             ~source:(Lui_webview.File prep.entry_file)
             ~on_message ~on_ready
         with
         | Ok () -> ()
         | Error e ->
           Printf.eprintf "webview-shell: native shell failed: %s — \
                           opening the default browser\n%!" e;
           (match Lui_webapp.open_in_browser prep.url with
            | Ok () -> ()
            | Error m ->
              prerr_endline ("webview-shell: " ^ m);
              exit 2)
       else
         (* No platform engine: degrade to the default browser, the
            same fallback {!Lui_webapp.boot} takes. *)
         (match Lui_webapp.open_in_browser prep.url with
          | Ok () ->
            Printf.eprintf
              "webview-shell: no webview backend — opened %s in the \
               default browser\n%!" prep.url
          | Error m ->
            prerr_endline ("webview-shell: " ^ m);
            exit 2))
