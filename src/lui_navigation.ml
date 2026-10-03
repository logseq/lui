open Lui_protocol

type 'route entry = { id : string; route : 'route }

(* Identity is process-local and allocated on the UI scheduler. Routes never
   cross the wire; branching from an old path still allocates a fresh id. *)
let next_identity = ref 0

let fresh_identity () =
  incr next_identity;
  !next_identity

module Path = struct
  type +'route t = 'route entry list

  let empty = []

  let push route path =
    { id = "entry-" ^ string_of_int (fresh_identity ()); route } :: path

  let pop = function [] -> [] | _ :: rest -> rest
  let pop_to_root _ = empty
  let entries = List.rev
end

let profiles = [ profile IOS SwiftUIHost; profile MacOS SwiftUIHost ]
let field name = Lui_extension.event_field name Lui_extension.IntScalar true

let stack_schema =
  Lui_extension.component "navigation-stack" profiles false
    [ "navigation-page" ]
    [
      Lui_extension.property "path" Lui_extension.StringScalar true None;
      Lui_extension.property "revision" Lui_extension.IntScalar true None;
    ]
    [
      Lui_extension.event "path-changed" [ field "revision"; field "length" ];
      Lui_extension.event "settled" [ field "revision"; field "length" ];
    ]

let page_schema =
  Lui_extension.component "navigation-page" profiles true []
    [ Lui_extension.property "entry-id" Lui_extension.StringScalar true None ]
    []

let register_into registry =
  Lui_extension.register_component registry stack_schema;
  Lui_extension.register_component registry page_schema

let registry () =
  let result = Lui_extension.registry () in
  register_into result;
  Lui_extension.freeze result;
  result

let ids path = List.map (fun entry -> entry.id) (Path.entries path)
let same_path a b = ids a = ids b

let take_length length path =
  let rec pop count path =
    if count = 0 then path else pop (count - 1) (Path.pop path)
  in
  pop (List.length path - length) path

type retained_page = { node : int; context : Lui_ui.ui_context }

let navigation_stack ?key ~path_signal ~on_path_change ~destination ~root () :
    Lui_elements.t =
 fun outer parent ->
  let apple = Lui_ui.host outer = SwiftUIHost in
  let node =
    if apple then Lui_ui.extension outer "navigation-stack"
    else Lui_ui.column outer
  in
  Option.iter (Lui_ui.key outer node) key;
  Option.iter (fun parent -> Lui_ui.append outer parent node) parent;
  let context =
    Lui_ui.child_context outer
      ("navigation-" ^ Option.value key ~default:(string_of_int node))
  in
  let application = context.Lui_ui.ui_application in
  (* The retirement flag also prevents an old owner dropping adopted nodes
     when an enclosing dyn/hot reload reconciles this component. *)
  let segment = Lui_runtime.register_dynamic_segment application node in
  let content_slot =
    if apple then node
    else begin
      let slot = Lui_ui.stack context in
      Lui_ui.float_property context slot GrowValue 1.;
      Lui_ui.append context node slot;
      slot
    end
  in
  let retained = Hashtbl.create 16 in
  let current = ref (Signal.sample path_signal) in
  let revision = ref 0 in
  let disposed = ref false in
  let fallback_visible = ref None in
  let mount_page id content =
    let page_context = Lui_ui.child_context context id in
    let page =
      if apple then Lui_ui.extension page_context "navigation-page"
      else Lui_ui.box page_context
    in
    Lui_ui.key page_context page id;
    if apple then
      Lui_ui.extension_property page_context page "entry-id" (StringValue id);
    (* A real wrapper gives even empty roots/destinations a stable child slot. *)
    ignore (Lui_elements.box ~grow:1. [ content ] page_context (Some page));
    if apple then Lui_ui.append context node page;
    let value = { node = page; context = page_context } in
    Signal.mount page_context.Lui_ui.ui_scope;
    value
  in
  let root_page = mount_page "root" root in
  let release page =
    Signal.dispose_scope page.context.Lui_ui.ui_scope;
    let owns_nodes = !(segment.Lui_runtime.dynamic_segment_active) in
    if owns_nodes then Signal.dispose_scope page.context.Lui_ui.ui_state_scope;
    (* Named state scope registry entries must not outlive their owner. *)
    let prefix = page.context.Lui_ui.ui_state_path in
    let removed =
      Hashtbl.fold
        (fun path _ result ->
          if path = prefix || String.starts_with ~prefix:(prefix ^ "/") path
          then path :: result
          else result)
        context.Lui_ui.ui_state_scopes []
    in
    if owns_nodes then
      List.iter
        (fun path ->
          Hashtbl.remove context.Lui_ui.ui_state_scopes path;
          Hashtbl.remove context.Lui_ui.ui_active_state_paths path)
        removed;
    if owns_nodes then Lui_runtime.drop_subtree application page.node
  in
  let prune () =
    let active = Hashtbl.create (List.length !current) in
    List.iter (fun entry -> Hashtbl.add active entry.id ()) !current;
    let outgoing =
      Hashtbl.fold
        (fun id page result ->
          if Hashtbl.mem active id then result else (id, page) :: result)
        retained []
    in
    List.iter
      (fun (id, page) ->
        Hashtbl.remove retained id;
        release page)
      outgoing
  in
  let render ~force path =
    if
      (not !disposed)
      && Lui_runtime.node_live application node
      && (force || not (same_path !current path))
    then begin
      current := path;
      revision := fresh_identity ();
      List.iter
        (fun entry ->
          if not (Hashtbl.mem retained entry.id) then
            Hashtbl.add retained entry.id
              (mount_page entry.id (destination entry)))
        (Path.entries path);
      if apple then begin
        Lui_ui.extension_property context node "path"
          (StringValue (String.concat "," (ids path)));
        Lui_ui.extension_property context node "revision" (IntValue !revision)
      end
      else begin
        let visible =
          match path with
          | [] -> root_page.node
          | entry :: _ -> (Hashtbl.find retained entry.id).node
        in
        (match !fallback_visible with
        | Some old when old <> visible ->
            Lui_runtime.remove_child application content_slot old
        | Some _ | None -> ());
        if !fallback_visible <> Some visible then
          Lui_ui.append context content_slot visible;
        fallback_visible := Some visible;
        prune ()
      end
    end
  in
  let propose length =
    if length >= 0 && length < List.length !current then begin
      let proposal = take_length length !current in
      on_path_change proposal;
      (* send_action may synchronously stage a new owner path. Publish that
         write before replying, including rejection or a different route. *)
      Signal.stabilize context.Lui_ui.ui_scheduler;
      render ~force:true (Signal.sample path_signal)
    end
  in
  if not apple then begin
    (* Fallback keeps detached nodes/scopes alive. Native widget retention is
       host-dependent; it has no interactive transition or browser history. *)
    let back =
      Lui_elements.button ~text:"Back"
        ~on_press:(fun _ ->
          Signal.stabilize context.Lui_ui.ui_scheduler;
          propose (List.length !current - 1))
        []
    in
    (* Put the affordance outside the changing content slot. *)
    let back_node = back context None in
    Lui_runtime.insert_child application node back_node 0
  end;
  render ~force:true !current;
  if apple then
    Lui_ui.on_event context node (fun event ->
        (* A signal update may be queued before this event arrives. Stabilize it
       first so a stale event cannot overwrite a new owner path. *)
        Signal.stabilize context.Lui_ui.ui_scheduler;
        match event with
        | ExtensionEvent (_, "navigation-stack", name, values) -> (
            match
              ( String_map.find_opt "revision" values,
                String_map.find_opt "length" values )
            with
            | Some (IntValue r), Some (IntValue length) when r = !revision ->
                if name = "path-changed" then propose length
                else if name = "settled" && length = List.length !current then
                  prune ()
            | _ -> ())
        | _ -> ());
  ignore
    (Signal.own context.Lui_ui.ui_scope
       (Signal.subscribe path_signal (render ~force:false)));
  Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
      disposed := true;
      Hashtbl.iter (fun _ page -> release page) retained;
      Hashtbl.clear retained;
      release root_page;
      Lui_runtime.unregister_dynamic_segment application segment);
  node
