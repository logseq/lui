(** OCaml desktop host for a prebuilt OCaml/Melange Web frontend. *)
val run : config:string -> updater_html:string -> updater_js:string -> unit
(** Start the system WebView on the main thread.
    macOS loads packaged assets at [lui://localhost] without a TCP listener.
    Configuration is embedded by [tooling/desktop.py build]. *)
