(* Lui_agent: one request/reply protocol answered by the shared runtime,
   in process and through the native bridge entry every host calls. *)

let contains text part =
  let n = String.length part in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = part || at (i + 1))
  in
  at 0

let check_contains message text part =
  if not (contains text part) then
    Alcotest.failf "%s: %S does not contain %S" message text part

let gallery_view _context source send =
  Lui_elements.column
    [ View.counter_section source send;
      View.todos_section source send;
      View.checkbox_section source send ]

let with_gallery run =
  let session =
    Drive.Session.mount ~profile:(Lui_protocol.generic_profile ())
      ~initial:Model.initial ~reducer:Model.update ~view:gallery_view ()
  in
  Fun.protect ~finally:(fun () -> Drive.Session.dispose session) (fun () ->
    let target = Lui_agent.app_target ~host:"test" session.Drive.Session.app in
    run session (Lui_agent.handle target))

let request fields =
  let buffer = Buffer.create 64 in
  Buffer.add_char buffer '{';
  List.iteri
    (fun index (name, value) ->
       if index > 0 then Buffer.add_char buffer ',';
       Lui_wire.add_quoted buffer name;
       Buffer.add_char buffer ':';
       Buffer.add_string buffer value)
    fields;
  Buffer.add_char buffer '}';
  Buffer.contents buffer

let op ?(fields = []) name =
  request (("op", Lui_wire.quoted name) :: List.map (fun (k, v) -> (k, Lui_wire.quoted v)) fields)

let ok message reply = check_contains message reply "\"ok\":true"
let refused message reply = check_contains message reply "\"ok\":false"

let test_hello () =
  with_gallery (fun _session agent ->
    let reply = agent (op "hello") in
    ok "hello" reply;
    check_contains "protocol" reply "\"protocol\":\"lui-agent\",\"version\":1";
    check_contains "host" reply "\"host\":\"test\"";
    List.iter
      (fun name -> check_contains "advertised op" reply (Lui_wire.quoted name))
      Lui_agent.operations)

let test_queries () =
  with_gallery (fun _session agent ->
    let found = agent (op "find" ~fields:[ ("selector", "text:count=0") ]) in
    ok "find" found;
    check_contains "find returns node ids" found "\"nodes\":[";
    let dump = agent (op "dump") in
    check_contains "dump uses Drive's line format" dump "#4 text text=\\\"count=0\\\"";
    let tree = agent (op "tree" ~fields:[ ("selector", "kind:checkbox") ]) in
    check_contains "tree nests props" tree "\"kind\":\"checkbox\",\"props\":{";
    check_contains "tree carries wire values" tree "\"text\":\"Enable notifications\"";
    let prop =
      agent (op "prop" ~fields:[ ("selector", "kind:checkbox"); ("name", "checked") ])
    in
    check_contains "prop" prop "\"value\":false")

let test_actions () =
  with_gallery (fun session agent ->
    ok "press" (agent (op "press" ~fields:[ ("selector", "kind:button&text:+") ]));
    ok "press again" (agent (op "press" ~fields:[ ("selector", "kind:button&text:+") ]));
    Alcotest.(check int) "presses reach the reducer" 2
      (Drive.Session.read_model session).Model.count;
    ok "the view followed"
      (agent (op "find" ~fields:[ ("selector", "text:count=2") ]));
    ok "type"
      (agent
         (op "type" ~fields:[ ("selector", "kind:text-field&prop:placeholder=What*"); ("text", "Write tests") ]));
    ok "submit" (agent (op "press" ~fields:[ ("selector", "kind:button&text:Add") ]));
    let found = agent (op "find" ~fields:[ ("selector", "text:Write tests") ]) in
    check_contains "typed todo is listed" found "\"nodes\":[";
    if contains found "\"nodes\":[]" then Alcotest.fail "typed todo is missing";
    ok "toggle"
      (agent
         (request
            [ ("op", "\"toggle\""); ("selector", "\"kind:checkbox\""); ("value", "true") ]));
    check_contains "toggle patched the checkbox"
      (agent (op "prop" ~fields:[ ("selector", "kind:checkbox"); ("name", "checked") ]))
      "\"value\":true")

let test_rejections_change_nothing () =
  with_gallery (fun session agent ->
    let before = Model.(session |> Drive.Session.read_model |> fun m -> m.count) in
    let cases =
      [ ("not json", "nope", "bad request");
        ("no op", "{}", "request has no op");
        ("unknown op", op "fly", "unknown op: fly");
        ("bad selector", op "press" ~fields:[ ("selector", "id:x") ], "bad selector: id:x");
        ("no match", op "press" ~fields:[ ("selector", "text:Nowhere") ], "no node matches text:Nowhere");
        ("unsupported event",
         op "type" ~fields:[ ("selector", "kind:button&text:+"); ("text", "x") ],
         "does not handle type");
        ("missing field", op "type" ~fields:[ ("selector", "kind:text-field&prop:placeholder=What*") ], "missing text");
        ("no key surface", op "key" ~fields:[ ("combo", "cmd+k") ], "no key-surface") ]
    in
    List.iter
      (fun (name, input, message) ->
         let reply = agent input in
         refused name reply;
         check_contains name reply message)
      cases;
    Alcotest.(check int) "rejected requests dispatch nothing" before
      (Drive.Session.read_model session).Model.count)

(* The agent and Drive scenarios share one selector grammar. *)
let test_selector_parity () =
  with_gallery (fun session agent ->
    let tree = session.Drive.Session.tree in
    List.iter
      (fun selector ->
         let drive =
           match Drive.Model.selector_of_string selector with
           | Some parsed -> List.map (fun n -> n.Drive.Model.id) (Drive.Model.find tree parsed)
           | None -> Alcotest.failf "Drive rejects %s" selector
         in
         let expected =
           "\"nodes\":[" ^ String.concat "," (List.map string_of_int drive) ^ "]"
         in
         check_contains selector (agent (op "find" ~fields:[ ("selector", selector) ])) expected)
      [ "kind:button"; "text:count"; "kind:button&text:+"; "prop:text=Add";
        "prop:placeholder=What*"; "Add"; "kind:checkbox&text:notifications" ])

let boom_view _context _source _send =
  Lui_elements.column
    [ Lui_elements.button ~text:"Boom" ~on_press:(fun _ -> failwith "handler boom") [];
      Lui_elements.button ~text:"Fine" ~on_press:(fun _ -> ()) [] ]

let test_native_bridge () =
  let bridge = Lui_native_bridge.create "AgentTest" in
  let backend = Lui_native_bridge.backend bridge (Lui_protocol.generic_profile ()) in
  Alcotest.check_raises "no agent before boot"
    (Invalid_argument "AgentTest bridge is not started") (fun () ->
      ignore (Lui_native_bridge.agent bridge (op "hello")));
  let gallery = Lui_app.create backend Model.initial Model.update gallery_view in
  ignore (Lui_native_bridge.boot bridge gallery);
  let hello = Lui_native_bridge.agent bridge (op "hello") in
  Alcotest.(check bool) "a query is one reply line" false (String.contains hello '\n');
  check_contains "the bridge names the host" hello "\"host\":\"AgentTest\"";
  let pressed =
    Lui_native_bridge.agent bridge (op "press" ~fields:[ ("selector", "kind:button&text:+") ])
  in
  (match String.split_on_char '\n' pressed with
  | reply :: patches ->
    ok "press reply" reply;
    Alcotest.(check bool) "the action's patches follow the reply" true (patches <> []);
    List.iter (fun batch -> check_contains "patch batch" batch "\"ops\":") patches
  | [] -> Alcotest.fail "empty agent reply");
  let app = Lui_app.create backend () (fun model _ -> model) boom_view in
  ignore (Lui_native_bridge.boot bridge app);
  ok "a sound handler" (Lui_native_bridge.agent bridge (op "press" ~fields:[ ("selector", "Fine") ]));
  Alcotest.check_raises "a raising handler refuses the agent call"
    (Failure "handler boom") (fun () ->
      ignore (Lui_native_bridge.agent bridge (op "press" ~fields:[ ("selector", "Boom") ])));
  let diagnostic = Lui_native_bridge.take_failure bridge in
  check_contains "the refusal names the agent phase" diagnostic "\"phase\":\"agent\"";
  check_contains "and the handler's message" diagnostic "handler boom";
  ok "the agent answers after a refusal" (Lui_native_bridge.agent bridge (op "dump"));
  ignore (Lui_native_bridge.dispose bridge);
  Alcotest.check_raises "no agent after dispose"
    (Invalid_argument "AgentTest bridge is not started") (fun () ->
      ignore (Lui_native_bridge.agent bridge (op "hello")))

let tests =
  [ Alcotest.test_case "hello advertises the protocol" `Quick test_hello;
    Alcotest.test_case "tree, dump, find and prop" `Quick test_queries;
    Alcotest.test_case "actions dispatch through the runtime" `Quick test_actions;
    Alcotest.test_case "rejected requests change nothing" `Quick test_rejections_change_nothing;
    Alcotest.test_case "selectors match Drive's" `Quick test_selector_parity;
    Alcotest.test_case "native bridge entry" `Quick test_native_bridge ]
