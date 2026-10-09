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

(* Teardown can race an outer drop: branch scopes still dispose while the
   runtime already dropped part of the branch (app teardown, reconcile), so
   remove_child/drop_subtree may only touch ids that are still live. The
   segment bookkeeping always unwinds so unregister sees an empty segment. *)
let teardown_branch application segment parent node =
  (* A reconcile may have re-homed [node] under a different live parent
     while this branch's scope still disposes lazily; the node then
     belongs to the new tree, so only a node still recorded under
     [parent] (or left parent-less) is this branch's to detach/drop. *)
  let owned () =
    match Lui_runtime.recorded_parent application node with
    | Some recorded -> recorded = Lui_runtime.canonical_node application parent
    | None -> true
  in
  if
    Lui_runtime.node_live application parent
    && Lui_runtime.node_live application node
    && owned ()
  then Lui_runtime.remove_child application parent node;
  Lui_runtime.release_dynamic_segment application segment;
  if Lui_runtime.node_live application node && owned () then
    Lui_runtime.drop_subtree application node

let segment_disposer application segment dispose_reactive () =
  Fun.protect dispose_reactive
    ~finally:(fun () -> Lui_runtime.unregister_dynamic_segment application segment)

let switch context parent source equal mount =
  let application = context.Lui_ui.ui_application in
  let segment = Lui_runtime.register_dynamic_segment application parent in
  let node_ref = ref None in
  let disposed = ref false in
  let branch_name = Lui_ui.owner_name context "switch-branch" in
  let mount_branch key =
    let branch_context = Lui_ui.child_context context branch_name in
    let branch_scope = branch_context.Lui_ui.ui_scope in
    (* Reconciled branches must skip node teardown: their nodes were handed
       to the new tree (or already dropped by [emit_dropped_subtree]), so the
       unmount hook may not remove or drop them. *)
    let retired = ref false in
    let node = try mount branch_context key with failure ->
      retired := true;
      (try Signal.dispose_scope branch_scope with _ -> ());
      raise failure in
    Signal.on_unmount branch_scope (fun () ->
        if !(segment.Lui_runtime.dynamic_segment_active) && not !retired
        then teardown_branch application segment parent node;
        if not !retired && !node_ref = Some node then node_ref := None);
    branch_context, node, retired
  in
  let initial_key = Signal.sample source in
  let initial_context, initial_node, initial_retired =
    mount_branch initial_key
  in
  node_ref := Some initial_node;
  Lui_runtime.insert_child application parent initial_node
    (Lui_runtime.dynamic_segment_insert_index segment 0);
  Lui_runtime.resize_dynamic_segment application segment 1;
  Signal.mount initial_context.Lui_ui.ui_scope;
  let current_key = ref initial_key in
  let current_scope = ref initial_context.Lui_ui.ui_scope in
  let current_retired = ref initial_retired in
  let subscription =
    Signal.subscribe ~emit_initial:false source (fun next_key ->
        if !disposed || equal !current_key next_key
        then ()
        else
          match !node_ref with
          | None -> ()
          | Some _ when not (Lui_runtime.node_live application parent) ->
            (* The parent was torn down in the same pass (reconcile/restore
               rebuilds mounted_nodes wholesale); this branch goes down with
               it, so the remount is moot. *)
            ()
          | Some old_node ->
            let old_scope = !current_scope in
            let saved = Lui_runtime.checkpoint_subtree application parent old_node in
            let candidate = ref None in
            let committed = ref false in
            (try
               let branch_context, new_node, new_retired =
                 mount_branch next_key
               in
               candidate := Some (branch_context, new_retired);
               (* Link the candidate into the live graph so reconcile can map
                  it; the mount-time ops this emits are discarded by
                  [reconcile_subtree]'s pending-ops reset. *)
               Lui_runtime.insert_child application parent new_node
                 (Lui_runtime.dynamic_segment_insert_index segment 0);
               let desired_root =
                 Lui_runtime.reconcile_subtree application saved parent
                   old_node new_node
               in
               (* Mount the candidate while the old branch is still live: a
                  throwing mount hook rolls back to an old scope whose
                  subscriptions were never disposed. *)
               Signal.mount branch_context.Lui_ui.ui_scope;
               !current_retired := true;
               Lui_runtime.retire_checkpoint_dynamic_segments saved old_node;
               current_key := next_key;
               node_ref := Some desired_root;
               current_scope := branch_context.Lui_ui.ui_scope;
               current_retired := new_retired;
               committed := true;
               Signal.dispose_scope old_scope
             with failure ->
               (* A mount or reconcile failure can leave tables half rebuilt;
                  restore the checkpoint and discard the candidate branch so
                  the old branch stays mounted. *)
               if not !committed then begin
               Lui_runtime.restore application saved;
               (match !candidate with
               | Some (branch_context, retired) ->
                 (* The candidate never took ownership of the segment or the
                    node slot, so mark it retired before disposal: its unmount
                    hook must not run [teardown_branch] against the live
                    branch's registrations. *)
                 retired := true;
                 (try Signal.dispose_scope branch_context.Lui_ui.ui_scope with _ -> ())
               | None -> ());
               end;
               raise failure))
  in
  ignore (Signal.own context.Lui_ui.ui_scope subscription);
  let dispose_callback =
    segment_disposer application segment (fun () ->
        disposed := true;
        Signal.dispose_subscription subscription;
        Signal.dispose_scope !current_scope)
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
  let branch_name = Lui_ui.owner_name context "conditional-branch" in
  let switch_value =
    Signal.switch context.Lui_ui.ui_scope source
      (fun left right -> left = right)
      (fun visible ->
         let branch_context =
           Lui_ui.child_context context branch_name
         in
         let branch_scope = branch_context.Lui_ui.ui_scope in
         (if visible && Lui_runtime.node_live application parent then
            let node = mount branch_context in
            node_ref := Some node;
            Lui_runtime.insert_child application parent node
              (Lui_runtime.dynamic_segment_insert_index segment 0);
            Lui_runtime.resize_dynamic_segment application segment 1;
            Signal.on_unmount branch_scope (fun () ->
                if !(segment.Lui_runtime.dynamic_segment_active) then
                  teardown_branch application segment parent node;
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
  let item_context = Lui_ui.context context.Lui_ui.ui_application
    (Signal.child_scope "keyed-item" context.Lui_ui.ui_scope) in
  let item_scope = item_context.Lui_ui.ui_scope in
  let node = mount item_context item_source in
  nodes_ref := { ui_key = key; ui_node = node } :: !nodes_ref;
  Signal.on_unmount item_scope (fun () ->
      if !(segment.Lui_runtime.dynamic_segment_active) then
        teardown_branch context.Lui_ui.ui_application segment parent node;
      remove_key_node nodes_ref key compare);
  item_scope

(* Each keyed row owns its state registry and lifecycle. A single owner
   cleanup avoids quadratic registration of thousands of child scopes. *)
type 'item keyed_entry = {
  keyed_item_state : 'item Signal.state;
  keyed_item_scope : Signal.scope;
  keyed_item_node : int;
}

let keyed (type key) context parent source (key_fn : _ -> key) compare mount =
  let module Keys = Map.Make (struct type t = key let compare = compare end) in
  let application = context.Lui_ui.ui_application in
  let scheduler = context.Lui_ui.ui_scheduler in
  let segment = Lui_runtime.register_dynamic_segment application parent in
  let entries = ref Keys.empty in
  let ordered = ref [||] in
  let nodes_ref = ref [] in
  let disposed = ref false in
  let dispose_entry entry =
    Fun.protect (fun () -> Signal.dispose_scope entry.keyed_item_scope)
      ~finally:(fun () -> Signal.dispose_signal (Signal.value entry.keyed_item_state)) in
  let detach_entry index entry =
    if Lui_runtime.node_live application parent && Lui_runtime.node_live application entry.keyed_item_node then begin
      Lui_runtime.remove_child_at application (Lui_runtime.canonical_node application parent)
        (Lui_runtime.canonical_node application entry.keyed_item_node)
        (Lui_runtime.dynamic_segment_index segment index);
      Lui_runtime.drop_subtree application entry.keyed_item_node
    end;
    Lui_runtime.release_dynamic_segment application segment in
  let remove_entry index entry =
    detach_entry index entry;
    dispose_entry entry in
  let reconcile items =
    if not !disposed && Lui_runtime.node_live application parent then begin
      let items = Array.of_list items in
      let old = !ordered in
      let unchanged = ref (Array.length items = Array.length old) in
      let index = ref 0 in
      while !unchanged && !index < Array.length items do
        let key, entry = old.(!index) in
        unchanged := compare key (key_fn items.(!index)) = 0
          && items.(!index) == Signal.get_state entry.keyed_item_state;
        incr index
      done;
      if not !unchanged then begin
      let desired = ref Keys.empty in
      Array.iteri (fun index item ->
        let key = key_fn item in
        if Keys.mem key !desired then invalid_arg "keyed collection contains a duplicate key";
        desired := Keys.add key index !desired) items;
      let nodes = Array.fold_left (fun nodes (_, entry) ->
        List.rev_append (Lui_runtime.collect_subtree_nodes
          application.Lui_runtime.runtime_children entry.keyed_item_node) nodes)
        [Lui_runtime.canonical_node application parent] old in
      let saved = Lui_runtime.checkpoint ~nodes application in
      let previous_entries = !entries in
      let mounted = ref [] in
      let retired = ref [] in
      let cleanup_candidates () = List.iter (fun entry ->
        try dispose_entry entry with _ -> ()) !mounted in
      (try
      (* Own every candidate before running its constructor or mount hooks. *)
      let fresh = Array.map (fun item ->
        let key = key_fn item in
        match Keys.find_opt key !entries with
        | Some _ -> None
        | None ->
          let item_state = Signal.state scheduler item in
          let scope = Signal.scope "keyed-item" in
          let item_context = Lui_ui.context application scope in
          let node = try mount item_context (Signal.value item_state)
            with failure ->
              (try Signal.dispose_scope scope with _ -> ());
              Signal.dispose_signal (Signal.value item_state);
              raise failure in
          let entry = { keyed_item_state = item_state; keyed_item_scope = scope;
                        keyed_item_node = node } in
          mounted := entry :: !mounted;
          Signal.mount scope;
          Some entry) items in
      let old = !ordered in
      let old_positions = ref Keys.empty in
      Array.iteri (fun index (key, _) -> old_positions := Keys.add key index !old_positions) old;
      (* Prefix sums track the remaining old rows while new rows are placed
         left to right; each retained row's current index costs O(log n). *)
      let counts = Array.make (Array.length old + 1) 0 in
      let add index delta =
        let index = ref (index + 1) in
        while !index < Array.length counts do
          counts.(!index) <- counts.(!index) + delta;
          index := !index + (!index land (- !index))
        done in
      let before index =
        let total = ref 0 and index = ref index in
        while !index > 0 do
          total := !total + counts.(!index);
          index := !index - (!index land (- !index))
        done;
        !total in
         for index = Array.length old - 1 downto 0 do
           let key, entry = old.(index) in
           if not (Keys.mem key !desired) then begin
             detach_entry index entry;
             retired := entry :: !retired;
             entries := Keys.remove key !entries
           end else add index 1
         done;
         let next = Array.mapi (fun index item ->
           let key = key_fn item in
           let entry = match Keys.find_opt key !entries with
             | Some entry ->
               let old_index = Keys.find key !old_positions in
               let current_index = index + before old_index in
               if current_index <> index then
                 Lui_runtime.move_child_at application (Lui_runtime.canonical_node application parent)
                   (Lui_runtime.canonical_node application entry.keyed_item_node)
                   (Lui_runtime.dynamic_segment_index segment current_index)
                   (Lui_runtime.dynamic_segment_index segment index);
               add old_index (-1);
               (* Physical equality: structural [<>] raises when an item
                  contains a closure. *)
               if item != Signal.get_state entry.keyed_item_state then
                 Signal.set entry.keyed_item_state item;
               entry
             | None ->
               let entry = match fresh.(index) with
                 | Some entry -> entry
                 | None -> invalid_arg "keyed mount missing" in
               Lui_runtime.insert_child application parent entry.keyed_item_node
                 (Lui_runtime.dynamic_segment_insert_index segment index);
               Lui_runtime.resize_dynamic_segment application segment 1;
               entries := Keys.add key entry !entries;
               entry in
           key, entry) items in
         ordered := next;
         nodes_ref := Array.to_list (Array.map (fun (key, entry) -> { ui_key = key; ui_node = entry.keyed_item_node }) next)
       with failure ->
         Lui_runtime.restore application saved;
         entries := previous_entries;
         cleanup_candidates ();
         raise failure);
      (* Structural ownership commits before fallible retirement callbacks. *)
      let failure = ref None in
      List.iter (fun entry -> try dispose_entry entry with error ->
        if !failure = None then failure := Some error) !retired;
      (match !failure with None -> ()
       | Some error -> raise error)
      end
    end in
  reconcile (Signal.sample source);
  let subscription = Signal.subscribe ~emit_initial:false source reconcile in
  ignore (Signal.own context.Lui_ui.ui_scope subscription);
  let dispose_callback () =
    if not !disposed then begin
      disposed := true;
      Signal.dispose_subscription subscription;
      let previous = !ordered in
      ordered := [||]; entries := Keys.empty; nodes_ref := [];
      let failure = ref None in
      let attempt cleanup = try cleanup () with error ->
        if !failure = None then failure := Some error in
      for index = Array.length previous - 1 downto 0 do
        let _, entry = previous.(index) in
        attempt (fun () ->
          if !(segment.Lui_runtime.dynamic_segment_active) then remove_entry index entry
          else dispose_entry entry)
      done;
      attempt (fun () -> Lui_runtime.unregister_dynamic_segment application segment);
      match !failure with None -> () | Some error -> raise error
    end in
  Signal.on_dispose context.Lui_ui.ui_scope dispose_callback;
  { dispose_dynamic_keyed = dispose_callback; key_nodes = nodes_ref; key_compare = compare }

let keyed_node keyed_value key =
  match
    find_key_node !(keyed_value.key_nodes) key keyed_value.key_compare
  with
  | Some node -> node
  | None -> invalid_arg "keyed node not found"

let dispose_keyed keyed_value = keyed_value.dispose_dynamic_keyed ()
