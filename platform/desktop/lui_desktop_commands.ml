module Command = Lui_command

type binding = Binding : ('a, 'b) Command.t * ('a -> ('b, Command.error) result) -> binding
let handle command handler = Binding (command, handler)

type t = {
  bindings : (string, binding) Hashtbl.t;
  mutex : Mutex.t;
  maximum : int;
  mutable active : int;
  mutable closed : bool;
}

let create ?(max_in_flight = 16) bindings =
  if max_in_flight < 1 || max_in_flight > 256 then Error "Invalid command concurrency limit"
  else
    let table = Hashtbl.create (List.length bindings) in
    let rec add = function
      | [] -> Ok { bindings = table; mutex = Mutex.create (); maximum = max_in_flight; active = 0; closed = false }
      | (Binding (command, _) as binding) :: remaining ->
          let name = Command.Name.to_string (Command.name command) in
          if Hashtbl.mem table name then Error ("Duplicate command: " ^ name)
          else (Hashtbl.add table name binding; add remaining)
    in add bindings

let lock registry callback =
  Mutex.lock registry.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock registry.mutex) callback

let error_json error =
  Yojson.Basic.to_string (`Assoc ["error", `Assoc [
    "code", `String (Command.code_name error.Command.code);
    "message", `String error.message]])

let dispatch registry ~name ~payload ~reply =
  let admitted = lock registry (fun () ->
    if registry.closed then Error (Command.error Closed "The application window is closed")
    else if String.length payload > 1_048_576 then Error (Command.error Invalid_arguments "Command payload exceeds 1 MiB")
    else match Hashtbl.find_opt registry.bindings name with
      | None -> Error (Command.error Unknown_command ("Unknown command: " ^ name))
      | Some _ when registry.active >= registry.maximum -> Error (Command.error Busy "Too many commands are in flight")
      | Some binding -> registry.active <- registry.active + 1; Ok binding) in
  match admitted with
  | Error error -> reply (error_json error)
  | Ok (Binding (command, handler)) ->
      let work () =
        let response =
          try match Command.decode_request command payload with
            | Error message -> error_json (Command.error Invalid_arguments message)
            | Ok input -> (match handler input with
                | Error error -> error_json error
                | Ok output ->
                    let result = Command.encode_response command output in
                    if String.length result > 1_048_576 then
                      error_json (Command.error Invalid_response "Command response exceeds 1 MiB")
                    else Yojson.Basic.to_string (`Assoc ["result", `String result]))
          with _ -> error_json (Command.error Internal_error "The native command failed") in
        let live = lock registry (fun () ->
          registry.active <- registry.active - 1; not registry.closed) in
        reply (if live then response else error_json (Command.error Closed "The application window is closed"))
      in
      (try ignore (Thread.create work ())
       with _ ->
         lock registry (fun () -> registry.active <- registry.active - 1);
         reply (error_json (Command.error Internal_error "Cannot start the command worker")))

let close registry = lock registry (fun () -> registry.closed <- true)
