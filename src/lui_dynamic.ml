(* Dynamic UI structure: switches, conditionals, and keyed collections
   bridging signal lifecycles and runtime dynamic segments. *)

type ui_switch = {
  dispose_dynamic_switch : unit -> unit;
  switch_node_ref : int option ref;
}

type ui_conditional = {
  dispose_dynamic_conditional : unit -> unit;
  conditional_node_ref : int option ref;
}

type 'key ui_key_node = {
  ui_key : 'key;
  ui_node : int;
}

type 'key ui_keyed = {
  dispose_dynamic_keyed : unit -> unit;
  key_nodes : 'key ui_key_node list ref;
  key_compare : 'key -> 'key -> int;
}

let segment_disposer application segment dispose_reactive () =
  dispose_reactive ();
  Lui_runtime.unregister_dynamic_segment application segment

let switch context parent source equal mount =
  let application = context.Lui_ui.ui_application in
  let segment = Lui_runtime.register_dynamic_segment application parent in
  let node_ref = ref None in
  let switch_value =
    Signal.switch context.Lui_ui.ui_scope source equal (fun key ->
        let branch_context = Lui_ui.child_context context "switch-branch" in
        let branch_scope = branch_context.Lui_ui.ui_scope in
        let node = mount branch_context key in
        node_ref := Some node;
        Lui_runtime.insert_child application parent node
          (Lui_runtime.dynamic_segment_insert_index segment 0);
        Lui_runtime.resize_dynamic_segment application segment 1;
        Signal.on_unmount branch_scope (fun () ->
            if !(segment.Lui_runtime.dynamic_segment_active) then begin
              Lui_runtime.remove_child application parent node;
              Lui_runtime.resize_dynamic_segment application segment (-1);
              Lui_runtime.drop_subtree application node
            end;
            node_ref := None);
        branch_scope)
  in
  let dispose_callback =
    segment_disposer application segment (fun () ->
        Signal.dispose_switch switch_value)
  in
  Signal.on_dispose context.Lui_ui.ui_scope dispose_callback;
  { dispose_dynamic_switch = dispose_callback; switch_node_ref = node_ref }

let switch_node switch_value =
  match !(switch_value.switch_node_ref) with
  | Some node -> node
  | None -> invalid_arg "switch has no active node"

let dispose_switch switch_value = switch_value.dispose_dynamic_switch ()

let conditional context parent source mount =
  let application = context.Lui_ui.ui_application in
  let segment = Lui_runtime.register_dynamic_segment application parent in
  let node_ref = ref None in
  let switch_value =
    Signal.switch context.Lui_ui.ui_scope source
      (fun left right -> left = right)
      (fun visible ->
         let branch_context =
           Lui_ui.child_context context "conditional-branch"
         in
         let branch_scope = branch_context.Lui_ui.ui_scope in
         (if visible then
            let node = mount branch_context in
            node_ref := Some node;
            Lui_runtime.insert_child application parent node
              (Lui_runtime.dynamic_segment_insert_index segment 0);
            Lui_runtime.resize_dynamic_segment application segment 1;
            Signal.on_unmount branch_scope (fun () ->
                if !(segment.Lui_runtime.dynamic_segment_active) then begin
                  Lui_runtime.remove_child application parent node;
                  Lui_runtime.resize_dynamic_segment application segment (-1);
                  Lui_runtime.drop_subtree application node
                end;
                node_ref := None));
         branch_scope)
  in
  let dispose_callback =
    segment_disposer application segment (fun () ->
        Signal.dispose_switch switch_value)
  in
  Signal.on_dispose context.Lui_ui.ui_scope dispose_callback;
  {
    dispose_dynamic_conditional = dispose_callback;
    conditional_node_ref = node_ref;
  }

let conditional_node conditional_value =
  match !(conditional_value.conditional_node_ref) with
  | Some node -> node
  | None -> invalid_arg "conditional has no active node"

let dispose_conditional conditional_value =
  conditional_value.dispose_dynamic_conditional ()

let find_key_node nodes key compare =
  let rec loop nodes =
    match nodes with
    | [] -> None
    | entry :: rest ->
      if compare entry.ui_key key = 0 then Some entry.ui_node else loop rest
  in
  loop nodes

let remove_key_node nodes_ref key compare =
  nodes_ref :=
    List.filter
      (fun entry -> compare entry.ui_key key <> 0)
      !nodes_ref

let mount_keyed_item context parent segment key_fn compare mount nodes_ref
    item_source =
  let current = Signal.sample item_source in
  let key = key_fn current in
  let item_context = Lui_ui.child_context context "keyed-item" in
  let item_scope = item_context.Lui_ui.ui_scope in
  let node = mount item_context item_source in
  nodes_ref := !nodes_ref @ [ { ui_key = key; ui_node = node } ];
  Signal.on_unmount item_scope (fun () ->
      if !(segment.Lui_runtime.dynamic_segment_active) then begin
        Lui_runtime.remove_child context.Lui_ui.ui_application parent node;
        Lui_runtime.resize_dynamic_segment context.Lui_ui.ui_application
          segment (-1);
        Lui_runtime.drop_subtree context.Lui_ui.ui_application node
      end;
      remove_key_node nodes_ref key compare);
  item_scope

let keyed context parent source key_fn compare mount =
  let application = context.Lui_ui.ui_application in
  let segment = Lui_runtime.register_dynamic_segment application parent in
  let nodes_ref = ref [] in
  let keyed_value =
    Signal.keyed context.Lui_ui.ui_scope source key_fn compare
      (fun item_source ->
         mount_keyed_item context parent segment key_fn compare mount
           nodes_ref item_source)
      (fun patch ->
         match patch with
         | Signal.Insert (key, index) ->
           (match find_key_node !nodes_ref key compare with
           | Some node ->
             Lui_runtime.insert_child application parent node
               (Lui_runtime.dynamic_segment_insert_index segment index);
             Lui_runtime.resize_dynamic_segment application segment 1
           | None -> invalid_arg "missing inserted keyed node")
         | Signal.Remove (_key, _index) -> ()
         | Signal.Move (key, _from_index, to_index) ->
           (match find_key_node !nodes_ref key compare with
           | Some node ->
             Lui_runtime.move_child application parent node
               (Lui_runtime.dynamic_segment_index segment to_index)
           | None -> invalid_arg "missing moved keyed node"))
  in
  let dispose_callback =
    segment_disposer application segment (fun () ->
        Signal.dispose_keyed keyed_value)
  in
  Signal.on_dispose context.Lui_ui.ui_scope dispose_callback;
  {
    dispose_dynamic_keyed = dispose_callback;
    key_nodes = nodes_ref;
    key_compare = compare;
  }

let keyed_node keyed_value key =
  match
    find_key_node !(keyed_value.key_nodes) key keyed_value.key_compare
  with
  | Some node -> node
  | None -> invalid_arg "keyed node not found"

let dispose_keyed keyed_value = keyed_value.dispose_dynamic_keyed ()
