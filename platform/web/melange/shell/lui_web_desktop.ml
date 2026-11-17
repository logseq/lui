type desktop

external desktop : Webapi.Dom.Window.t -> desktop Js.Nullable.t = "luiDesktop"
  [@@mel.get]

external check : desktop -> bool Js.Promise.t = "checkForUpdates" [@@mel.send]

let available () =
  Js.Nullable.toOption (desktop Webapi.Dom.window) <> None

let check_for_updates () =
  match Js.Nullable.toOption (desktop Webapi.Dom.window) with
  | None -> Js.Promise.resolve false
  | Some host -> check host
