(* Behavioral tests for lui_ai: pure model helpers, keyed transcript
   updates (streaming in place, reorder/dup identity), tool grouping,
   composer send/stop gating, disposal, and both viewport modes. *)

open Lui_protocol

module M = Lui_ai.Model

let msg id kind text = { (M.item id kind) with M.text }
let user id text = msg id M.User text
let assistant id text = msg id M.Assistant text

let tool_item id status =
  let call : M.tool_call =
    { call_id = id; title = "Run " ^ id; tool_kind = "shell"; status;
      input = None; output = None; output_truncated = false } in
  { (M.item id M.Tool_call) with tool = Some call }

let update id ?status ?output () : M.tool_update =
  { update_id = id; update_title = None; update_kind = None;
    update_status = status; update_input = None; update_output = output;
    update_output_truncated = None }

let drive_mount ~initial ~view =
  Drive.Session.mount ~profile:(generic_profile ()) ~initial
    ~reducer:(fun m f -> f m) ~view ()

let drive_tree (s : _ Drive.Session.t) = s.Drive.Session.tree
let drive_flush s = Drive.Session.flush s
let drive_dispose s = Drive.Session.dispose s

let model_of (s : _ Drive.Session.t) = Lui_app.model s.Drive.Session.app

let drive_send_model s f =
  ignore (Lui_app.send s.Drive.Session.app f);
  drive_flush s

let find_node s pred =
  let tree = drive_tree s in
  let found = ref None in
  Hashtbl.iter
    (fun _ (n : Drive.Model.node) -> if pred n then found := Some n)
    tree.Drive.Model.nodes;
  match !found with Some n -> n | None -> Alcotest.fail "node missing"

let node_prop (n : Drive.Model.node) name =
  Hashtbl.find_opt n.Drive.Model.props name

let find_by_prop s name value =
  find_node s (fun n -> node_prop n name = Some value)

let find_opt s name value =
  try
    ignore (find_by_prop s name value);
    true
  with _ -> false

let container_node s =
  find_node s (fun n ->
      let k = n.Drive.Model.kind in
      k = "virtual-list" || k = "list")

let text_nodes s =
  let tree = drive_tree s in
  Hashtbl.fold
    (fun _ (n : Drive.Model.node) acc ->
       match node_prop n "text" with
       | Some (StringValue v) -> v :: acc | _ -> acc)
    tree.nodes []

let send_event s ev = Drive.Session.dispatch s ev

let has_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

(* {1 Pure model} *)

let test_model_helpers () =
  let items = [ user "u1" "hi"; assistant "a1" "hello" ] in
  let grown = M.append_text items "a1" " world" in
  Alcotest.(check int) "same count" 2 (List.length grown);
  Alcotest.(check string) "delta merged" "hello world"
    (Option.get (M.find grown "a1")).M.text;
  let reordered = M.upsert grown (user "u1" "hi2") in
  Alcotest.(check string) "upsert keeps position" "u1"
    (List.hd reordered).M.id;
  let appended = M.upsert items (assistant "a2" "new") in
  Alcotest.(check string) "order preserved" "a2" (List.nth appended 2).M.id

let test_tool_sparse_merge () =
  let items = [ tool_item "t1" `in_progress ] in
  let upd : M.tool_update =
    { update_id = "t1"; update_title = None; update_kind = None;
      update_status = None; update_input = Some "{ \"cmd\": \"ls\" }";
      update_output = None; update_output_truncated = None } in
  let merged = M.update_tool items upd in
  let call = Option.get (List.hd merged).M.tool in
  Alcotest.(check string) "title preserved" "Run t1" call.title;
  Alcotest.(check bool) "status preserved" true
    (call.status = `in_progress);
  let merged2 = M.update_tool merged { upd with update_output = Some "ok" } in
  let call2 = Option.get (List.hd merged2).M.tool in
  Alcotest.(check string) "input kept" "{ \"cmd\": \"ls\" }"
    (Option.get call2.input);
  Alcotest.(check string) "output set" "ok" (Option.get call2.output)

let test_group_rows () =
  let items =
    [ user "u1" "a"; tool_item "t1" `in_progress; tool_item "t2" `completed;
      assistant "a1" "done"; tool_item "t3" `completed ] in
  let rows = M.group_rows ~group:true items in
  Alcotest.(check (list string)) "one group per run"
    [ "u1"; "tools:t1"; "a1"; "tools:t3" ] (List.map M.row_key rows);
  let ungrouped = M.group_rows ~group:false items in
  Alcotest.(check (list string)) "ungrouped keeps all"
    [ "u1"; "t1"; "t2"; "a1"; "t3" ] (List.map M.row_key ungrouped);
  (match List.nth rows 1 with
   | M.Tool_group members ->
       Alcotest.(check bool) "group active" true (M.group_active members)
   | _ -> Alcotest.fail "expected group");
  match M.group_rows ~group:true
          [ tool_item "t1" `completed; tool_item "t2" `completed ] with
  | [ M.Tool_group members ] ->
      Alcotest.(check bool) "finished group inactive" false
        (M.group_active members)
  | _ -> Alcotest.fail "expected finished group"

(* {1 Transcript behavior} *)

let transcript_view _ctx model_s _send =
  Lui_ai.Transcript.transcript ~messages:model_s ()

let test_streaming_same_row () =
  let items =
    [ user "u1" "q"; { (assistant "a1" "ans") with streaming = true } ] in
  let s = drive_mount ~initial:items ~view:transcript_view in
  let row = find_by_prop s "key" (StringValue "a1") in
  drive_send_model s (fun m -> M.append_text m "a1" " part2");
  let row' = find_by_prop s "key" (StringValue "a1") in
  Alcotest.(check int) "same node id" row.Drive.Model.id
    row'.Drive.Model.id;
  Alcotest.(check (list string)) "text updated in place"
    [ "ans part2"; "q" ] (List.sort String.compare (text_nodes s));
  drive_send_model s (fun m -> M.append_text m "a1" "\nmore");
  let row'' = find_by_prop s "key" (StringValue "a1") in
  Alcotest.(check int) "still same row" row.Drive.Model.id
    row''.Drive.Model.id;
  drive_dispose s

let test_keyed_reorder_dup () =
  let items = [ user "u1" "a"; assistant "a1" "b"; assistant "a2" "c" ] in
  let s = drive_mount ~initial:items ~view:transcript_view in
  let a1 = find_by_prop s "key" (StringValue "a1") in
  let a2 = find_by_prop s "key" (StringValue "a2") in
  drive_send_model s (fun _ -> List.rev items);
  let a1' = find_by_prop s "key" (StringValue "a1") in
  let a2' = find_by_prop s "key" (StringValue "a2") in
  Alcotest.(check int) "reorder keeps a1" a1.Drive.Model.id a1'.Drive.Model.id;
  Alcotest.(check int) "reorder keeps a2" a2.Drive.Model.id a2'.Drive.Model.id;
  drive_send_model s (fun _ -> List.filter (fun i -> i.M.id <> "a1") items);
  let a2'' = find_by_prop s "key" (StringValue "a2") in
  Alcotest.(check int) "survivor keeps id" a2.Drive.Model.id
    a2''.Drive.Model.id;
  drive_dispose s

let test_tool_group_rendering () =
  let items =
    [ user "u1" "go"; tool_item "t1" `in_progress; tool_item "t2" `pending;
      assistant "a1" "done" ] in
  let s = drive_mount ~initial:items ~view:transcript_view in
  let accordion = find_by_prop s "accessibility-identifier"
      (StringValue "lui-ai-tool-group") in
  Alcotest.(check (option string)) "group auto-expanded while active"
    (Some "true")
    (match node_prop accordion "selected" with
     | Some (BoolValue b) -> Some (string_of_bool b) | _ -> None);
  Alcotest.(check bool) "group headline" true
    (List.exists (( = ) "Working on 2 steps") (text_nodes s));
  drive_send_model s
    (fun m -> M.update_tool m (update "t1" ~status:`completed ~output:"out" ()));
  drive_send_model s
    (fun m -> M.update_tool m (update "t2" ~status:`completed ()));
  Alcotest.(check bool) "group settles" true
    (List.exists (( = ) "Worked through 2 steps") (text_nodes s));
  drive_dispose s

let host_attrs (item : M.item) =
  [ "data-event-id", item.id; "data-current-text", item.text ]

let host_tool ?(on_press = fun _ -> ()) item_s =
  if (Lui_elements.sample item_s).M.id <> "host" then None
  else
    Some
      (Lui_elements.button ~text:"Host tool details"
         ~accessibility_identifier:"host-tool-details"
         ~on_press:(fun _ -> on_press (Lui_elements.get item_s)) [])

let host_transcript ?(group_tools = true) ?on_press () _ctx source _send =
  Lui_ai.Transcript.transcript ~messages:source ~group_tools
    ~render_item:(host_tool ?on_press) ~item_data_attrs:host_attrs
    ~item_class:(fun _ -> "host-item") ()

let test_grouped_host_renderer () =
  let initial = [ tool_item "host" `in_progress; tool_item "fallback" `pending ] in
  let s = drive_mount ~initial ~view:(host_transcript ()) in
  Alcotest.(check bool) "host renderer is used inside the group" true
    (List.mem "Host tool details" (text_nodes s));
  Alcotest.(check bool) "default tool renderer remains available" true
    (List.exists (fun text -> has_sub text "Run fallback") (text_nodes s));
  let host = find_by_prop s "accessibility-identifier"
      (StringValue "lui-ai-item:host") in
  Alcotest.(check string) "group member is a noninteractive container" "column"
    host.Drive.Model.kind;
  Alcotest.(check (option string)) "host row class is preserved" (Some "host-item")
    (match node_prop host "style-class" with Some (StringValue x) -> Some x | _ -> None);
  Alcotest.(check bool) "host row metadata is preserved" true
    (match node_prop host "data-attrs" with
     | Some (StringValue x) -> has_sub x "data-event-id" && has_sub x "host"
     | _ -> false);
  drive_dispose s

let test_grouped_host_updates () =
  let clicked = ref "" in
  let initial = [ tool_item "host" `in_progress; tool_item "fallback" `in_progress ] in
  let view = host_transcript ~on_press:(fun item -> clicked := item.M.text) () in
  let s = drive_mount ~initial ~view in
  let host () = find_by_prop s "accessibility-identifier"
      (StringValue "lui-ai-item:host") in
  let before = (host ()).Drive.Model.id in
  drive_send_model s (fun items -> M.append_text items "host" "fresh host content");
  drive_send_model s (fun items ->
      M.update_tool items (update "fallback" ~output:"fresh default output" ()));
  Alcotest.(check int) "streaming retains grouped row identity" before (host ()).id;
  Alcotest.(check bool) "grouped metadata follows the current item" true
    (match node_prop (host ()) "data-attrs" with
     | Some (StringValue x) -> has_sub x "fresh host content" | _ -> false);
  Drive.Session.press s
    (find_by_prop s "accessibility-identifier" (StringValue "host-tool-details")).id;
  Alcotest.(check string) "host callback reads current borrowed item"
    "fresh host content" !clicked;
  Alcotest.(check bool) "default grouped tool content still updates" true
    (List.mem "fresh default output" (text_nodes s));
  drive_dispose s

let test_single_host_metadata_updates () =
  let initial = [ tool_item "host" `in_progress ] in
  let s = drive_mount ~initial ~view:(host_transcript ~group_tools:false ()) in
  let host () = find_by_prop s "accessibility-identifier"
      (StringValue "lui-ai-item:host") in
  let before = (host ()).Drive.Model.id in
  drive_send_model s (fun items -> M.append_text items "host" "new single metadata");
  Alcotest.(check int) "single row keeps identity" before (host ()).id;
  Alcotest.(check bool) "single metadata follows the same item contract" true
    (match node_prop (host ()) "data-attrs" with
     | Some (StringValue x) -> has_sub x "new single metadata" | _ -> false);
  drive_dispose s

let test_grouped_host_lifetime () =
  let mounted = ref 0 and disposed = ref [] in
  let renderer source =
    let id = (Lui_elements.sample source).M.id in
    Some (Lui_elements.scoped (fun context ->
        incr mounted;
        Signal.on_dispose context.Lui_ui.ui_scope (fun () -> disposed := id :: !disposed);
        Lui_elements.button ~text:id ~accessibility_identifier:("host:" ^ id) [])) in
  let view _ctx source _send =
    Lui_ai.Transcript.transcript ~messages:source ~render_item:renderer () in
  let t1 = tool_item "t1" `in_progress and t2 = tool_item "t2" `pending in
  let s = drive_mount ~initial:[t1;t2] ~view in
  let group = find_by_prop s "accessibility-identifier"
      (StringValue "lui-ai-tool-group") in
  let t2_node = find_by_prop s "accessibility-identifier" (StringValue "host:t2") in
  Drive.Session.toggle s group.id false;
  drive_send_model s (fun _ -> [t1;tool_item "t3" `in_progress;t2]);
  Alcotest.(check int) "group insertion retains custom tool" t2_node.id
    (find_by_prop s "accessibility-identifier" (StringValue "host:t2")).id;
  Alcotest.(check bool) "user disclosure survives active updates" true
    (node_prop group "selected" = Some (BoolValue false));
  Alcotest.(check int) "only the added custom child mounts" 3 !mounted;
  drive_send_model s (fun items -> List.filter (fun item -> item.M.id <> "t2") items);
  Alcotest.(check (list string)) "removed child is disposed once" ["t2"] !disposed;
  drive_send_model s (fun _ -> []);
  Alcotest.(check (list string)) "all group children are disposed" ["t1";"t2";"t3"]
    (List.sort String.compare !disposed);
  drive_send_model s (fun _ -> [assistant "after" "caller stream remains alive"]);
  Alcotest.(check bool) "group disposal does not dispose caller source" true
    (List.mem "after" (text_nodes s));
  drive_dispose s;
  Alcotest.(check int) "each mounted host view is disposed exactly once" 4
    (List.length !disposed)

(* {1 Anchored follow (virtual_list by default)} *)

let test_autoscroll_follow () =
  let items = List.init 40 (fun i -> assistant (Printf.sprintf "m%d" i) "x") in
  let s = drive_mount ~initial:items ~view:transcript_view in
  let list_el = container_node s in
  Alcotest.(check string) "default transcript is virtual" "virtual-list"
    list_el.Drive.Model.kind;
  Alcotest.(check bool) "visible-range tracking" true
    (node_prop list_el "track-visible-range" = Some (BoolValue true));
  drive_send_model s (fun m -> m @ [ user "tail" "new" ]);
  Alcotest.(check (option string)) "target is tail" (Some "tail")
    (match node_prop (container_node s) "scroll-target" with
     | Some (StringValue v) -> Some v | _ -> None);
  let token () =
    match node_prop (container_node s) "scroll-token" with
    | Some (IntValue v) -> v | _ -> -1 in
  Alcotest.(check bool) "token bumped" true (token () > 0);
  send_event s (ScrollEdges (list_el.Drive.Model.id, true, false));
  let before = token () in
  drive_send_model s (fun m -> m @ [ user "later" "x" ]);
  Alcotest.(check bool) "no scroll while unpinned" true (before = token ());
  Drive.Session.press s
    (find_by_prop s "accessibility-identifier" (StringValue "lui-ai-jump")).id;
  Alcotest.(check (option string)) "jump re-pins" (Some "later")
    (match node_prop (container_node s) "scroll-target" with
     | Some (StringValue v) -> Some v | _ -> None);
  drive_dispose s

let test_reach_top_hook () =
  let reached = ref 0 in
  let view _ctx model_s _send =
    Lui_ai.Transcript.transcript ~messages:model_s
      ~on_reach_top:(fun () -> incr reached) () in
  let s = drive_mount ~initial:[ assistant "a1" "x" ] ~view in
  let list_el = container_node s in
  send_event s (ScrollEdges (list_el.Drive.Model.id, true, false));
  send_event s (ScrollEdges (list_el.Drive.Model.id, true, false));
  send_event s (ScrollEdges (list_el.Drive.Model.id, false, false));
  send_event s (ScrollEdges (list_el.Drive.Model.id, true, false));
  Alcotest.(check int) "top edge fires on rising edge only" 2 !reached;
  drive_dispose s

let test_host_driven_viewport () =
  let at_bottom_ref = ref None in
  let scroll_calls = ref [] in
  let view _ctx model_s _send =
    Lui_elements.scoped (fun context ->
      let at_bottom =
        Signal.state context.Lui_ui.ui_scheduler true in
      at_bottom_ref := Some at_bottom;
      let viewport =
        Lui_ai.Transcript.Host_driven
          { container = `virtual_list;
            at_bottom = Signal.value at_bottom;
            scroll_to =
              (fun ~key ~animated ->
                 scroll_calls := (key, animated) :: !scroll_calls) } in
      Lui_ai.Transcript.transcript ~messages:model_s ~viewport ()) in
  let s = drive_mount ~initial:[ user "u1" "hi" ] ~view in
  ignore (container_node s);
  Alcotest.(check bool) "initial follow scroll" true
    (List.exists (fun (k, _) -> k = "u1") !scroll_calls);
  drive_send_model s (fun m -> m @ [ assistant "a1" "part" ]);
  Alcotest.(check bool) "growth scrolls to new tail" true
    (List.exists (fun (k, _) -> k = "a1") !scroll_calls);
  scroll_calls := [];
  Signal.set (Option.get !at_bottom_ref) false;
  drive_flush s;
  drive_send_model s (fun m -> m @ [ assistant "a2" "more" ]);
  Alcotest.(check bool) "unpinned: no scroll" true (!scroll_calls = []);
  drive_dispose s;
  scroll_calls := [];
  Signal.set (Option.get !at_bottom_ref) true;
  drive_flush s;
  Alcotest.(check bool) "unmounted: subscription released" true
    (!scroll_calls = [])

(* {1 Composer} *)

let test_composer_send_stop () =
  let sent = ref 0 and stopped = ref 0 and typed = ref "" in
  let s =
    drive_mount ~initial:("", false)
      ~view:(fun _ctx model_s _send ->
        Lui_ai.Composer.composer
          ~draft:(Lui_elements.map fst model_s)
          ~generating:(Lui_elements.map snd model_s)
          ~on_input:(fun ev ->
            match ev with TextChanged (_, t) -> typed := t | _ -> ())
          ~on_send:(fun _ -> incr sent)
          ~on_stop:(fun _ -> incr stopped) ())
  in
  Alcotest.(check bool) "no stop while idle" true
    (not (find_opt s "accessibility-identifier" (StringValue "lui-ai-stop")));
  let field =
    find_node s (fun n -> n.Drive.Model.kind = "textarea") in
  Drive.Session.text_changed s field.Drive.Model.id "hello";
  Alcotest.(check string) "draft edit reaches host" "hello" !typed;
  let send_btn =
    find_by_prop s "accessibility-identifier" (StringValue "button.send") in
  Drive.Session.press s send_btn.Drive.Model.id;
  Alcotest.(check int) "send dispatched" 1 !sent;
  drive_send_model s (fun _ -> ("", true));
  let send_btn =
    find_by_prop s "accessibility-identifier" (StringValue "button.send") in
  Alcotest.(check bool) "send disabled while generating" true
    (node_prop send_btn "enabled" = Some (BoolValue false));
  let stop =
    find_by_prop s "accessibility-identifier" (StringValue "lui-ai-stop") in
  Drive.Session.press s stop.Drive.Model.id;
  Alcotest.(check int) "stop dispatched" 1 !stopped;
  drive_send_model s (fun _ -> ("", false));
  Alcotest.(check bool) "stop unmounts when done" true
    (not (find_opt s "accessibility-identifier" (StringValue "lui-ai-stop")));
  drive_dispose s


(* {1 PR242 review regressions} *)

let scroll_target s =
  match node_prop (container_node s) "scroll-target" with
  | Some (StringValue v) -> Some v | _ -> None

(* Rows, not items, drive the tail-follow target: a transcript ending in
   a tool group must scroll to the group row key, not the last tool's
   item id (which has no row). *)
let test_grouped_tail_key () =
  let items =
    [ user "u1" "go"; tool_item "t1" `in_progress; tool_item "t2" `pending ] in
  let s = drive_mount ~initial:items ~view:transcript_view in
  drive_send_model s (fun m -> M.append_text m "u1" "!");
  Alcotest.(check (option string)) "tail target is group row key"
    (Some "tools:t1") (scroll_target s);
  drive_dispose s

(* Pin detection counts rows, not items: with [u1,t1,t2] grouped into 2
   rows, seeing the last row (index 1) must keep the tail pinned. *)
let test_grouped_pin () =
  let items =
    [ user "u1" "go"; tool_item "t1" `in_progress; tool_item "t2" `pending ] in
  let s = drive_mount ~initial:items ~view:transcript_view in
  let list_el = container_node s in
  send_event s (ScrollEdges (list_el.Drive.Model.id, false, true));
  drive_send_model s (fun m -> m @ [ assistant "a9" "ok" ]);
  Alcotest.(check (option string)) "still pinned at grouped tail"
    (Some "a9") (scroll_target s);
  send_event s (ScrollEdges ((container_node s).Drive.Model.id, true, false));
  let before = scroll_target s in
  drive_send_model s (fun m -> m @ [ assistant "a10" "more" ]);
  Alcotest.(check (option string)) "unpinned stays put" before
    (scroll_target s);
  drive_dispose s

let composer_with ?(generating = fun m -> snd m) ?send_disabled
    ?disabled_reason send model_s =
  ignore generating;
  Lui_ai.Composer.composer
    ~draft:(Lui_elements.map fst model_s)
    ~generating:(Lui_elements.map snd model_s)
    ?send_disabled
    ?disabled_reason
    ~on_input:(fun _ -> ())
    ~on_send:(fun ev -> ignore ev; send ())
    ()

let textarea_node s =
  find_node s (fun n -> n.Drive.Model.kind = "textarea")

(* One send-allowed gate for button and Enter: Enter (Submit) must be
   swallowed while send is disabled, not queued or delivered. *)
let test_enter_gate () =
  let sent = ref 0 in
  let view _ctx model_s send =
    ignore send;
    composer_with (fun () -> incr sent) model_s in
  let s = drive_mount ~initial:("hi", true) ~view in
  let field = textarea_node s in
  send_event s (Submit field.Drive.Model.id);
  Alcotest.(check int) "Enter gated while generating" 0 !sent;
  drive_send_model s (fun _ -> ("hi", false));
  send_event s (Submit (textarea_node s).Drive.Model.id);
  Alcotest.(check int) "Enter submits when allowed" 1 !sent;
  drive_dispose s

let test_enter_gate_send_disabled () =
  let sent = ref 0 in
  let view _ctx model_s send =
    ignore send;
    Lui_elements.scoped (fun context ->
      let blocked =
        Signal.state context.Lui_ui.ui_scheduler true in
      Lui_ai.Composer.composer
        ~draft:(Lui_elements.map fst model_s)
        ~generating:(Lui_elements.map snd model_s)
        ~send_disabled:(Signal.value blocked)
        ~on_input:(fun _ -> ())
        ~on_send:(fun _ -> incr sent) ()) in
  let s = drive_mount ~initial:("hi", false) ~view in
  send_event s (Submit (textarea_node s).Drive.Model.id);
  Alcotest.(check int) "Enter gated while send_disabled" 0 !sent;
  let btn =
    find_by_prop s "accessibility-identifier" (StringValue "button.send") in
  Alcotest.(check bool) "send button disabled too" true
    (node_prop btn "enabled" = Some (BoolValue false));
  drive_dispose s

(* disabled_reason must feed the same send-allowed gate. *)
let test_disabled_reason_gate () =
  let sent = ref 0 in
  let view _ctx model_s send =
    ignore send;
    Lui_elements.scoped (fun context ->
      let reason =
        Signal.state context.Lui_ui.ui_scheduler "Read only" in
      Lui_ai.Composer.composer
        ~draft:(Lui_elements.map fst model_s)
        ~generating:(Lui_elements.map snd model_s)
        ~disabled_reason:(Signal.value reason)
        ~on_input:(fun _ -> ())
        ~on_send:(fun _ -> incr sent) ()) in
  let s = drive_mount ~initial:("hi", false) ~view in
  let btn =
    find_by_prop s "accessibility-identifier" (StringValue "button.send") in
  Alcotest.(check bool) "reason disables send" true
    (node_prop btn "enabled" = Some (BoolValue false));
  send_event s (Submit (textarea_node s).Drive.Model.id);
  Alcotest.(check int) "reason gates Enter" 0 !sent;
  drive_dispose s

(* Picker completion is host-controlled: a Picked event must NOT echo the
   completion token (Apple would revoke temp files before async import);
   the host echoes via ?picker_completion. Dismiss still releases the
   outstanding request automatically when no host signal is supplied. *)
let test_picker_async_ack () =
  let picked = ref [] in
  let view _ctx _model_s _send =
    Lui_elements.scoped (fun context ->
      let draft = Signal.state context.Lui_ui.ui_scheduler "" in
      let gen = Signal.state context.Lui_ui.ui_scheduler false in
      Lui_ai.Composer.composer
        ~draft:(Signal.value draft) ~generating:(Signal.value gen)
        ~picker:{ source = `files; types = None; accept = None;
                  multiple = true }
        ~on_picked:(fun ev ->
          match ev with Picked (_, p) -> picked := p :: !picked | _ -> ())
        ~on_input:(fun _ -> ()) ~on_send:(fun _ -> ()) ()) in
  let s = drive_mount ~initial:() ~view in
  let picker =
    find_node s (fun n -> n.Drive.Model.kind = "file-picker") in
  Drive.Session.press s
    (find_by_prop s "accessibility-identifier" (StringValue "lui-ai-attach")).id;
  send_event s (Picked (picker.Drive.Model.id,
    {|{"request":"op-1","files":[]}|}));
  Alcotest.(check bool) "picked delivered" true (!picked <> []);
  Alcotest.(check (option string)) "no premature ack" None
    (match node_prop picker "completion" with
     | Some (StringValue v) -> Some v | _ -> None);
  send_event s (Dismiss picker.Drive.Model.id);
  Alcotest.(check bool) "dismiss releases outstanding request" true
    (node_prop picker "completion" <> None);
  drive_dispose s

let test_picker_host_completion () =
  let completion_ref = ref None in
  let view _ctx _model_s _send =
    Lui_elements.scoped (fun context ->
      let draft = Signal.state context.Lui_ui.ui_scheduler "" in
      let gen = Signal.state context.Lui_ui.ui_scheduler false in
      let completion =
        Signal.state context.Lui_ui.ui_scheduler (`Int (-1)) in
      completion_ref := Some completion;
      Lui_ai.Composer.composer
        ~draft:(Signal.value draft) ~generating:(Signal.value gen)
        ~picker:{ source = `files; types = None; accept = None;
                  multiple = true }
        ~picker_completion:(Signal.value completion)
        ~on_input:(fun _ -> ()) ~on_send:(fun _ -> ()) ()) in
  let s = drive_mount ~initial:() ~view in
  let picker =
    find_node s (fun n -> n.Drive.Model.kind = "file-picker") in
  Drive.Session.press s
    (find_by_prop s "accessibility-identifier" (StringValue "lui-ai-attach")).id;
  send_event s (Picked (picker.Drive.Model.id,
    {|{"request":"op-1","files":[]}|}));
  Alcotest.(check (option string)) "host acks, library does not" None
    (match node_prop picker "completion" with
     | Some (StringValue v) -> Some v | _ -> None);
  Signal.set (Option.get !completion_ref) (`String "op-1");
  drive_flush s;
  Alcotest.(check (option string)) "host completion echoes"
    (Some "op-1")
    (match node_prop picker "completion" with
     | Some (StringValue v) -> Some v | _ -> None);
  drive_dispose s

(* The transcript bounds its own scroll viewport and centers a bounded
   content column; user bubbles right-align inside it. *)
let test_bounded_layout () =
  let s = drive_mount ~initial:[ user "u1" "hi" ] ~view:transcript_view in
  let list_el = container_node s in
  Alcotest.(check bool) "scroll container min-height 0" true
    (node_prop list_el "min-height" = Some (IntValue 0)
     || node_prop list_el "min-height" = Some (StringValue "0"));
  let centered =
    find_node s (fun n ->
        n.Drive.Model.kind = "row"
        && node_prop n "main" = Some (StringValue "center")) in
  ignore centered;
  let bounded =
    find_node s (fun n ->
        n.Drive.Model.kind = "column"
        && node_prop n "max-width" = Some (IntValue 768)) in
  ignore bounded;
  drive_dispose s

let test_container_data_attrs_signal () =
  let attrs_ref = ref None in
  let view _ctx model_s _send =
    Lui_elements.scoped (fun context ->
      let attrs =
        Signal.state context.Lui_ui.ui_scheduler
          [ ("data-scroll-root", "chat") ] in
      attrs_ref := Some attrs;
      Lui_ai.Transcript.transcript ~messages:model_s
        ~container_data_attrs_signal:(Signal.value attrs) ()) in
  let s = drive_mount ~initial:[ user "u1" "x" ] ~view in
  let list_el = container_node s in
  let get_attrs () =
    match node_prop list_el "data-attrs" with
    | Some (StringValue v) -> Some v | _ -> None in
  Alcotest.(check bool) "signal attrs land" true
    (match get_attrs () with
     | Some v -> has_sub v "data-scroll-root"
     | None -> false);
  Signal.set (Option.get !attrs_ref)
    [ ("data-scroll-root", "chat"); ("data-row-count", "1") ];
  drive_flush s;
  Alcotest.(check bool) "signal attrs update" true
    (match get_attrs () with
     | Some v -> has_sub v "data-row-count"
     | None -> false);
  drive_dispose s

(* {1 Disposal} *)

let test_dispose () =
  let s = drive_mount ~initial:[ user "u1" "x" ] ~view:transcript_view in
  drive_dispose s;
  Alcotest.(check bool) "disposed" true
    (Lui_app.disposed s.Drive.Session.app)

let tests =
  [
    ( "model",
      [ Alcotest.test_case "helpers" `Quick test_model_helpers;
        Alcotest.test_case "tool sparse merge" `Quick test_tool_sparse_merge;
        Alcotest.test_case "tool grouping" `Quick test_group_rows ] );
    ( "transcript",
      [ Alcotest.test_case "grouped tail key" `Quick test_grouped_tail_key;
        Alcotest.test_case "grouped pin" `Quick test_grouped_pin;
        Alcotest.test_case "bounded layout" `Quick test_bounded_layout;
        Alcotest.test_case "container attrs signal" `Quick
          test_container_data_attrs_signal;
        Alcotest.test_case "streaming updates same row" `Quick
          test_streaming_same_row;
        Alcotest.test_case "reorder/dup identity" `Quick
          test_keyed_reorder_dup;
        Alcotest.test_case "tool group" `Quick test_tool_group_rendering;
        Alcotest.test_case "grouped host renderer" `Quick test_grouped_host_renderer;
        Alcotest.test_case "grouped host updates" `Quick test_grouped_host_updates;
        Alcotest.test_case "single host metadata updates" `Quick test_single_host_metadata_updates;
        Alcotest.test_case "grouped host lifetime" `Quick test_grouped_host_lifetime;
        Alcotest.test_case "autoscroll follow" `Quick test_autoscroll_follow;
        Alcotest.test_case "reach-top hook" `Quick test_reach_top_hook;
        Alcotest.test_case "host-driven viewport" `Quick
          test_host_driven_viewport ] );
    ( "composer",
      [ Alcotest.test_case "send/stop gating" `Quick test_composer_send_stop;
        Alcotest.test_case "enter gate" `Quick test_enter_gate;
        Alcotest.test_case "enter gate send_disabled" `Quick
          test_enter_gate_send_disabled;
        Alcotest.test_case "disabled reason gate" `Quick
          test_disabled_reason_gate;
        Alcotest.test_case "picker async ack" `Quick test_picker_async_ack;
        Alcotest.test_case "picker host completion" `Quick
          test_picker_host_completion ] );
    ( "lifecycle", [ Alcotest.test_case "dispose" `Quick test_dispose ] );
  ]
