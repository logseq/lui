(** OCaml desktop host for a prebuilt OCaml/Melange Web frontend. *)
val run : config:string -> updater_html:string -> updater_js:string -> unit
(** Start the system WebView on the main thread.
    macOS loads packaged assets at [lui://localhost] without a TCP listener.
    Configuration is embedded by [tooling/desktop.py build]. *)

val run_with_commands :
  commands:(unit -> Lui_desktop_commands.binding list) ->
  config:string -> updater_html:string -> updater_js:string -> unit
(** Register application handlers in the main process. The initializer is never
    called by updater/installer helpers. No command is registered implicitly. *)
