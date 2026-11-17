module C = Lui_command
module Registry = Lui_desktop_commands
let check test message = if not test then failwith message
let name value = match C.Name.of_string value with Ok name -> name | Error message -> failwith message
let echo = C.v ~name:(name "app.echo") ~request:C.Codec.string ~response:C.Codec.string
let number = C.v ~name:(name "app.number") ~request:C.Codec.int32 ~response:C.Codec.int32
let registry ?max_in_flight bindings = match Registry.create ?max_in_flight bindings with
  | Ok registry -> registry | Error message -> failwith message

let response () =
  let mutex = Mutex.create () and ready = Condition.create () in
  let result = ref None in
  let reply value = Mutex.lock mutex; result := Some value; Condition.signal ready; Mutex.unlock mutex in
  let wait () =
    Mutex.lock mutex;
    while !result = None do Condition.wait ready mutex done;
    let value = Option.get !result in Mutex.unlock mutex;
    Yojson.Basic.from_string value in
  reply, wait

let call registry name payload =
  let reply, wait = response () in Registry.dispatch registry ~name ~payload ~reply; wait ()
let result json = Yojson.Basic.Util.(json |> member "result" |> to_string)
let error json = Yojson.Basic.Util.(json |> member "error" |> member "code" |> to_string)

let () =
  List.iter (fun value -> check (Result.is_error (C.Name.of_string value)) ("Accepted invalid name: " ^ value))
    [""; "App.echo"; "app..echo"; "lui.echo"; "app/echo"; "app.1echo"];
  List.iter (fun value -> check (Result.is_error (C.Codec.decode C.Codec.int32 value)) "Accepted noncanonical int32")
    ["2147483648"; "-2147483649"; "01"; "+1"; "0xff"; "1.0"];
  List.iter (fun value -> check (Result.is_ok (C.Codec.decode C.Codec.int32 value)) "Rejected valid int32")
    ["-2147483648"; "2147483647"; "0"];
  let binding = Registry.handle echo (fun value -> Ok (value ^ " 中文 …")) in
  check (Result.is_error (Registry.create [binding; binding])) "Accepted duplicate command";
  let active = ref 0 in
  let commands = registry [binding; Registry.handle number (fun value -> incr active; Ok value)] in
  check (result (call commands "app.echo" "hello") = "hello 中文 …") "Unicode response mismatch";
  check (error (call commands "unknown" "") = "unknown_command") "Unknown command was admitted";
  check (error (call commands "app.number" "wrong") = "invalid_arguments" && !active = 0)
    "Malformed arguments reached the handler";
  check (error (call commands "app.echo" (String.make 1_048_577 'x')) = "invalid_arguments") "Admitted oversize payload";
  let failure = registry [Registry.handle echo (fun _ -> failwith "sensitive details")] in
  let failure = call failure "app.echo" "" in
  check (error failure = "internal_error") "Handler exception escaped";
  check (not (String.contains (Yojson.Basic.to_string failure) '\n')) "Unexpected error output";
  let gate = Mutex.create () and condition = Condition.create () in
  let entered = ref false and released = ref false in
  let blocked = registry ~max_in_flight:1 [Registry.handle echo (fun value ->
    Mutex.lock gate; entered := true; Condition.broadcast condition;
    while not !released do Condition.wait condition gate done;
    Mutex.unlock gate; Ok value)] in
  let reply, wait = response () in
  Registry.dispatch blocked ~name:"app.echo" ~payload:"first" ~reply;
  Mutex.lock gate;
  while not !entered do Condition.wait condition gate done;
  Mutex.unlock gate;
  check (error (call blocked "app.echo" "second") = "busy") "Command limit was not enforced";
  Registry.close blocked;
  check (error (call blocked "app.echo" "third") = "closed") "Closed registry admitted a command";
  Mutex.lock gate; released := true; Condition.broadcast condition; Mutex.unlock gate;
  check (error (wait ()) = "closed") "Retired handler returned a stale success";
  Registry.close commands;
  print_endline "commands passed"
