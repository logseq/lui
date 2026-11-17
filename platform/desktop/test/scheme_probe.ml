external run :
  string * string * int * int * bool * (string -> string * string) * (string -> string) -> unit
  = "lui_desktop_scheme_window_run"

let asset = function
  | "/" -> "text/html; charset=utf-8", {|<!doctype html><html><head>
      <meta charset="utf-8"><title>LUI Scheme Lifecycle Probe</title>
      </head><body><p id="result"></p><script type="module" src="./probe.js"></script></body></html>|}
  | "/probe.js" -> "text/javascript; charset=utf-8", {|
      if (location.origin !== "lui://localhost" && location.origin !== "null")
        throw new Error("Wrong scheme origin: " + location.origin);
      document.getElementById("result").textContent = "Unicode: 中文 …";
      window.addEventListener("load", async () => {
        await window.__lui_request("ready");
        setTimeout(() => window.__lui_later(), 1200);
      });|}
  | _ -> invalid_arg "Unknown probe asset"

let command = function
  | "ready" -> print_endline "scheme-ready"; flush stdout; "{}"
  | "later" -> print_endline "scheme-later"; flush stdout; "null"
  | _ -> invalid_arg "Unknown probe command"

let () =
  run ("LUI Scheme Lifecycle Probe", "lui://localhost/", 400, 240, true, asset, command);
  print_endline "scheme-closed"
