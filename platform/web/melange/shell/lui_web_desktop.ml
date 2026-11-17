type desktop

external desktop : Webapi.Dom.Window.t -> desktop Js.Nullable.t = "luiDesktop"
  [@@mel.get]

external check : desktop -> bool Js.Promise.t = "checkForUpdates" [@@mel.send]
external call : desktop -> string -> string -> string Js.Promise.t = "invoke" [@@mel.send]
external error_code : Js.Promise.error -> string Js.Undefined.t = "code" [@@mel.get]
external error_message : Js.Promise.error -> string Js.Undefined.t = "message" [@@mel.get]

let available () =
  Js.Nullable.toOption (desktop Webapi.Dom.window) <> None

let check_for_updates () =
  match Js.Nullable.toOption (desktop Webapi.Dom.window) with
  | None -> Js.Promise.resolve false
  | Some host -> check host

let invoke command argument =
  let unavailable () =
    Js.Promise.resolve (Error (Lui_command.error Unavailable "Native desktop commands are unavailable")) in
  match Js.Nullable.toOption (desktop Webapi.Dom.window) with
  | None -> unavailable ()
  | Some host -> (
      try
        let name = Lui_command.Name.to_string (Lui_command.name command) in
        call host name (Lui_command.encode_request command argument)
        |> Js.Promise.then_ (fun payload ->
            let result = try if Js.typeof payload <> "string" then
                Error (Lui_command.error Invalid_response "Expected an encoded command response")
              else match Lui_command.decode_response command payload with
              | Ok value -> Ok value
              | Error message -> Error (Lui_command.error Invalid_response message)
              with _ -> Error (Lui_command.error Invalid_response "Cannot decode the native response") in
            Js.Promise.resolve result)
        |> Js.Promise.catch (fun error ->
            let failure = try
                let string_property value fallback = match Js.Undefined.toOption value with
                  | Some text when Js.typeof text = "string" -> text
                  | Some _ | None -> fallback in
                let code, message = if Js.testAny error then "internal_error", "Native command failed"
                  else string_property (error_code error) "internal_error",
                    string_property (error_message error) "Native command failed" in
                Lui_command.error (Lui_command.code_of_name code) message
              with _ -> Lui_command.error Internal_error "Native command failed" in
            Js.Promise.resolve (Error failure))
      with _ -> unavailable ())
