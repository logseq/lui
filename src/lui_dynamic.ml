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
(* Node-side cleanup shared by segment teardown and the retired-segment
   fallback: a host-hoisted node (a dialog/sheet the backend moves under
   the root or an overlay layer) reports a recorded parent that is an
   *ancestor* of this branch's parent — unlike a node reconcile re-homed
   into a sibling subtree, no other owner will drop it, so this scope
   still has to. *)
let drop_branch_node application parent node =
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
  if Lui_runtime.node_live application node then
    if owned () then
      Lui_runtime.drop_subtree application node
    else
      (let hoisted rp =
         let rec up depth p =
           depth < 64
           &&
           match Lui_runtime.recorded_parent application p with
           | Some pp -> if pp = rp then true else up (depth + 1) pp
           | None -> false
         in
         up 0 parent
       in
       match Lui_runtime.recorded_parent application node with
       | Some rp when hoisted rp ->
         Lui_runtime.remove_child application rp node;
         Lui_runtime.drop_subtree application node
       | _ -> ())

(* Retired segments handed ordinary nodes to the replacement tree. Only
   live nodes hoisted out of the branch remain this scope's to clean up. *)
let teardown_branch_node application parent node =
  if Lui_runtime.node_live application node then
    match Lui_runtime.recorded_parent application node with
    | Some recorded
      when recorded <> Lui_runtime.canonical_node application parent ->
      drop_branch_node application parent node
    | _ -> ()

let teardown_branch application segment parent node =
  Lui_runtime.release_dynamic_segment application segment;
  drop_branch_node application parent node

let segment_disposer application segment dispose_reactive () =
  Fun.protect dispose_reactive
    ~finally:(fun () -> Lui_runtime.unregister_dynamic_segment application segment)

let replacing_virtual_nodes application nodes =
  let replacements = List.filter_map (fun node ->
    match Hashtbl.find_opt application.Lui_runtime.runtime_virtual_sources node with
    | Some source -> Some (Lui_virtual.Internal.replacing_source source)
    | None -> Option.map Lui_virtual.Internal.replacing_owner
        (Hashtbl.find_opt application.Lui_runtime.runtime_virtual_owners node)) nodes in
  let finished = ref false in
  fun () -> if not !finished then begin
    finished := true;
    List.iter (fun finish -> finish ()) replacements
  end

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
    Signal.subscribe ~emit_initial:false source (fun next_key -> context.Lui_ui.ui_protect (fun () ->
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
            let finish_replacements = replacing_virtual_nodes application
              (Lui_runtime.collect_subtree_nodes application.Lui_runtime.runtime_children
                (Lui_runtime.canonical_node application old_node)) in
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
               finish_replacements ();
               !current_retired := true;
               Lui_runtime.retire_checkpoint_dynamic_segments application saved old_node;
               current_key := next_key;
               node_ref := Some desired_root;
               current_scope := branch_context.Lui_ui.ui_scope;
               current_retired := new_retired;
               committed := true;
               Signal.dispose_scope old_scope
             with failure ->
               finish_replacements ();
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
               raise failure)))
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
  let mounted_visible = ref false in
  let branch_name = Lui_ui.owner_name context "conditional-branch" in
  let switch_value =
    Signal.switch context.Lui_ui.ui_scope source
      (fun left right -> left = right)
      (fun visible ->
         let branch_context =
           Lui_ui.child_context context branch_name
         in
         let branch_scope = branch_context.Lui_ui.ui_scope in
         context.Lui_ui.ui_protect (fun () ->
         let was_mounted = !mounted_visible in
         mounted_visible := visible;
         (if visible && Lui_runtime.node_live application parent then
            (match !node_ref with
             | Some node ->
               (* the switch refires its mount callback when the previous
                  branch scope was disposed externally — mounting again
                  would leak a duplicate retained node. Rebind teardown of
                  the live node to this scope so a real close still
                  removes it. *)
               Signal.on_unmount branch_scope (fun () ->
                   if !(segment.Lui_runtime.dynamic_segment_active) then
                     teardown_branch application segment parent node
                   else
                     teardown_branch_node application parent node;
                   node_ref := None)
             | None when not was_mounted ->
               let node = mount branch_context in
               node_ref := Some node;
               Lui_runtime.insert_child application parent node
                 (Lui_runtime.dynamic_segment_insert_index segment 0);
               Lui_runtime.resize_dynamic_segment application segment 1;
               Signal.on_unmount branch_scope (fun () ->
                   if !(segment.Lui_runtime.dynamic_segment_active) then
                     teardown_branch application segment parent node
                   else
                     teardown_branch_node application parent node;
                   node_ref := None)
             | None -> ()));
         Signal.mount branch_scope);
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
  let item_context = { (Lui_ui.context context.Lui_ui.ui_application
    (Signal.child_scope "keyed-item" context.Lui_ui.ui_scope)) with
    Lui_ui.ui_protect = context.Lui_ui.ui_protect } in
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

let occurrence_keys (type key) parent (key_fn : _ -> key) compare items =
  let module Counts = Map.Make (struct type t = key let compare = compare end) in
  let counts = ref Counts.empty in
  Array.map (fun item ->
    let key = key_fn item in
    let occurrence = Option.value (Counts.find_opt key !counts) ~default:0 in
    counts := Counts.add key (occurrence + 1) !counts;
    if occurrence > 0 then
      Printf.eprintf "LUI duplicate key: key_hash=%d parent=%d occurrence=%d\n%!"
        (Hashtbl.hash key) parent occurrence;
    key, occurrence) items

let keyed_controller (type key) context parent segment (key_fn : _ -> key) compare mount =
  let module Keys = Map.Make (struct
    type t = key * int
    let compare (a, i) (b, j) =
      let order = compare a b in if order = 0 then Int.compare i j else order
  end) in
  let application = context.Lui_ui.ui_application in
  let scheduler = context.Lui_ui.ui_scheduler in
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
  let reconcile ?commit ?identities items =
    if not !disposed && Lui_runtime.node_live application parent then begin
      let items = Array.of_list items in
      let identities = match identities with
        | Some identities -> identities
        | None -> occurrence_keys parent key_fn compare items in
      let old = !ordered in
      let unchanged = ref (Array.length items = Array.length old) in
      let index = ref 0 in
      while !unchanged && !index < Array.length items do
        let key, entry = old.(!index) in
        let previous_key, previous_occurrence = key in
        let next_key, next_occurrence = identities.(!index) in
        unchanged := compare previous_key next_key = 0 && previous_occurrence = next_occurrence
          && items.(!index) == Signal.get_state entry.keyed_item_state;
        incr index
      done;
      if !unchanged then
        Option.iter (fun commit ->
          let saved = Lui_runtime.checkpoint
            ~nodes:[Lui_runtime.canonical_node application parent] application in
          try commit () with failure ->
            Lui_runtime.restore application saved;
            raise failure) commit
      else begin
      let desired = ref Keys.empty in
      Array.iteri (fun index _item ->
        let key = identities.(index) in
        desired := Keys.add key index !desired) items;
      (* Reordering changes only the parent sequence. Retained row updates
         are queued through Signal.set; only removed subtrees are dropped
         inside this transaction and need their runtime state restored. *)
      let nodes = Array.fold_left (fun nodes (key, entry) ->
        if Keys.mem key !desired then nodes
        else List.rev_append (Lui_runtime.collect_subtree_nodes
          application.Lui_runtime.runtime_children entry.keyed_item_node) nodes)
        [Lui_runtime.canonical_node application parent] old in
      let saved = Lui_runtime.checkpoint ~nodes application in
      let retiring = List.filter (fun node ->
        node <> Lui_runtime.canonical_node application parent) nodes in
      let finish_replacements = replacing_virtual_nodes application retiring in
      let previous_entries = !entries in
      let previous_ordered = !ordered and previous_nodes = !nodes_ref in
      let mounted = ref [] in
      let retired = ref [] in
      let updates = ref [] in
      let cleanup_candidates () = List.iter (fun entry ->
        try dispose_entry entry with _ -> ()) !mounted in
      (try
      (* Own every candidate before running its constructor or mount hooks. *)
      let fresh = Array.mapi (fun index item ->
        let key = identities.(index) in
        match Keys.find_opt key !entries with
        | Some _ -> None
        | None ->
          let item_state = Signal.state scheduler item in
          let scope = Signal.scope "keyed-item" in
          let item_context = { (Lui_ui.context application scope) with
            Lui_ui.ui_protect = context.Lui_ui.ui_protect } in
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
      finish_replacements ();
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
           let key = identities.(index) in
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
                 updates := (entry, item) :: !updates;
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
         nodes_ref := Array.to_list (Array.map (fun ((key, _), entry) ->
           { ui_key = key; ui_node = entry.keyed_item_node }) next);
         Option.iter (fun commit -> commit ()) commit
       with failure ->
         finish_replacements ();
         Lui_runtime.restore application saved;
         entries := previous_entries;
         ordered := previous_ordered; nodes_ref := previous_nodes;
         cleanup_candidates ();
         raise failure);
      List.iter (fun (entry, item) -> Signal.set entry.keyed_item_state item)
        (List.rev !updates);
      (* Structural ownership commits before fallible retirement callbacks. *)
      let failure = ref None in
      List.iter (fun entry -> try dispose_entry entry with error ->
        if !failure = None then failure := Some error) !retired;
      (match !failure with None -> ()
       | Some error -> raise error)
      end
    end in
  let dispose_callback () =
    if not !disposed then begin
      disposed := true;
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
  let identities_by_node () =
    let nodes = Hashtbl.create (Array.length !ordered) in
    Array.iter (fun (identity, entry) ->
      Hashtbl.replace nodes entry.keyed_item_node identity) !ordered;
    nodes in
  reconcile, { dispose_dynamic_keyed = dispose_callback; key_nodes = nodes_ref; key_compare = compare }, identities_by_node


let keyed context parent source key_fn compare mount =
  let segment = Lui_runtime.register_dynamic_segment context.Lui_ui.ui_application parent in
  let reconcile, keyed, _ = keyed_controller context parent segment key_fn compare mount in
  reconcile (Signal.sample source);
  let subscription = Signal.subscribe ~emit_initial:false source (fun items ->
    context.Lui_ui.ui_protect (fun () -> reconcile items)) in
  ignore (Signal.own context.Lui_ui.ui_scope subscription);
  { keyed with dispose_dynamic_keyed = (fun () ->
      Signal.dispose_subscription subscription;
      keyed.dispose_dynamic_keyed ()) }

let virtual_rows (type key) ?viewport ?scroll_key context parent source
    (key_fn : _ -> key) compare mount =
  let module Keys = Map.Make (struct
    type t = key * int
    let compare (a, i) (b, j) =
      let order = compare a b in if order = 0 then Int.compare i j else order
  end) in
  let application = context.Lui_ui.ui_application in
  if Option.is_some viewport && Option.is_none scroll_key then
    invalid_arg "shared virtual rows require semantic scroll_key";
  let segment = Lui_runtime.register_dynamic_segment ~exclusive:true application parent in
  let reconcile, keyed, identities_by_node = keyed_controller context parent segment key_fn compare mount in
  if not application.Lui_runtime.runtime_virtual_rows then begin
    reconcile (Signal.sample source);
    let subscription = Signal.subscribe ~emit_initial:false source (fun items ->
      context.Lui_ui.ui_protect (fun () -> reconcile items)) in
    ignore (Signal.own context.Lui_ui.ui_scope subscription);
    { keyed with dispose_dynamic_keyed = (fun () ->
        Signal.dispose_subscription subscription;
        keyed.dispose_dynamic_keyed ()) }
  end else begin
    let viewport_lease = Option.map (fun source ->
      (Option.get (Signal.sample (Lui_virtual.binding source))).Lui_virtual.lease) viewport in
    let dataset = ref [||] in
    let dataset_identities = ref [||] in
    let positions = ref Keys.empty in
    let scroll_positions = ref Lui_protocol.String_map.empty in
    let revision = ref 0 and stopped = ref false in
    let properties () = Option.value
      (Hashtbl.find_opt application.Lui_runtime.runtime_properties
         (Lui_runtime.canonical_node application parent))
      ~default:Lui_protocol.Property_map.empty in
    let property name = Lui_protocol.Property_map.find_opt name (properties ()) in
    let target positions value =
      match value with
      | None | Some (Lui_protocol.StringValue "") -> -1
      | Some (Lui_protocol.StringValue key) ->
        (match scroll_key with
         | None -> invalid_arg "virtual_rows requires scroll_key for scroll_target"
         | Some _ -> Option.value (Lui_protocol.String_map.find_opt key positions) ~default:(-1))
      | Some _ -> invalid_arg "invalid virtual-list scroll target" in
    let bootstrap count =
      let overscan = match property Lui_protocol.VirtualOverscan with
        | Some (Lui_protocol.IntValue value) -> value
        | _ -> 2 in
      let extent = match property Lui_protocol.VirtualItemExtent with
        | Some (Lui_protocol.FloatValue value) -> value
        | _ -> 24. in
      let visible = match property Lui_protocol.HeightValue with
        | Some (Lui_protocol.IntValue height) ->
          int_of_float (min (float count) (ceil (float height /. extent)))
        | _ -> min count 1 in
      let limit = visible + min (count - visible) overscan in
      let limit = limit + min (count - limit) overscan in
      List.init limit Fun.id in
    let build items =
      let items = Array.of_list items in
      let identities = occurrence_keys parent key_fn compare items in
      let indices = ref Keys.empty and targets = ref Lui_protocol.String_map.empty in
      Array.iteri (fun index item ->
        let key = identities.(index) in
        indices := Keys.add key index !indices;
        Option.iter (fun scroll_key ->
          let key = scroll_key item in
          if Option.is_some viewport && key = "" then
            invalid_arg "shared virtual row key must not be empty";
          if Lui_protocol.String_map.mem key !targets then
            invalid_arg "virtual_rows contains a duplicate scroll_key";
          targets := Lui_protocol.String_map.add key index !targets) scroll_key) items;
      items, identities, !indices, !targets in
    let window_keys = ref [] and native_pins = ref [] and adopted_pins = ref [] in
    let visible_indices indices = List.filter_map (fun key -> Keys.find_opt key indices) !window_keys in
    let reconcile_indices ?window_pins ?(identities = !dataset_identities) items indices targets epoch selected =
      let visible_keys = List.map (Array.get identities) selected in
      (* Cold semantic keys are unioned before every reconciliation, including
         bootstrap and source publications, before any row has a native id. *)
      let retained = match viewport with
        | None -> []
        | Some viewport -> List.filter_map (fun key ->
            Lui_protocol.String_map.find_opt key targets)
            (Lui_virtual.Internal.retained_keys viewport) in
      let pins = match window_pins with
        | Some pins -> pins
        | None -> List.rev_append !native_pins !adopted_pins in
      let pins = List.map (Lui_runtime.canonical_node application) pins in
      let mounted_identities = identities_by_node () in
      let physical = List.filter_map (fun entry ->
        if List.mem (Lui_runtime.canonical_node application entry.ui_node) pins
        then Option.bind (Hashtbl.find_opt mounted_identities entry.ui_node)
          (fun identity -> Keys.find_opt identity indices) else None)
        !(keyed.key_nodes) in
      let selected = List.sort_uniq Int.compare
        (List.rev_append physical (List.rev_append retained selected)) in
      let target_index = target targets (property Lui_protocol.ScrollTarget) in
      let selected_items = List.map (Array.get items) selected in
      reconcile selected_items ~identities:(Array.of_list (List.map (Array.get identities) selected)) ~commit:(fun () ->
        List.iter (fun (name, value) -> Lui_runtime.set_prop application parent name value)
          [ Lui_protocol.VirtualTotalCount, Lui_protocol.IntValue (Array.length items);
            Lui_protocol.VirtualGeneration, Lui_protocol.IntValue epoch;
            Lui_protocol.VirtualIndices,
              Lui_protocol.StringValue (Lui_protocol.virtual_indices_to_string selected);
            Lui_protocol.VirtualScrollIndex, Lui_protocol.IntValue target_index ];
        Option.iter (fun viewport ->
          let keys = List.map (fun index ->
            (Option.get scroll_key) items.(index)) selected in
          Lui_runtime.set_prop application parent Lui_protocol.VirtualRowKeys
            (Lui_protocol.StringValue (Lui_virtual_json.encode_strings keys));
          let children = Lui_runtime.children application parent in
          Lui_virtual.Internal.commit_rows viewport ~lease:(Option.get viewport_lease) ~generation:epoch
            ~contains:(fun key -> Lui_protocol.String_map.mem key targets)
            (List.combine keys children)) viewport;
        Lui_runtime.validate_virtual_list application parent;
        dataset := items; dataset_identities := identities; positions := indices; scroll_positions := targets;
        window_keys := visible_keys;
        Option.iter (fun pins -> native_pins := pins; adopted_pins := []) window_pins;
        revision := epoch) in
    let update_source items =
      if not !stopped && Lui_runtime.node_live application parent then begin
        let items, identities, indices, targets = build items in
        let mounted_identities = identities_by_node () in
        (* Keep matched mounted keys through the generation handshake. A new
           bootstrap is needed only if no old row remains, avoiding growth
           across repeated source revisions before the host responds. *)
        let selected = (match viewport with
          | Some _ -> visible_indices indices
          | None -> List.filter_map (fun entry ->
              Option.bind (Hashtbl.find_opt mounted_identities entry.ui_node)
                (fun identity -> Keys.find_opt identity indices))
              !(keyed.key_nodes)) |> List.sort_uniq Int.compare in
        let selected = if selected = [] then bootstrap (Array.length items) else selected in
        let saved = Lui_runtime.checkpoint
          ~nodes:[Lui_runtime.canonical_node application parent] application in
        let previous_revision = !revision in
        if !(application.Lui_runtime.next_virtual_generation) = max_int then
          invalid_arg "virtual_rows generation overflow";
        incr application.Lui_runtime.next_virtual_generation;
        let epoch = !(application.Lui_runtime.next_virtual_generation) in
        (try reconcile_indices ~identities items indices targets epoch selected with failure ->
          (* A retirement callback can fail after the new revision committed;
             that accepted revision must keep its allocated identity. *)
          if !revision = previous_revision then Lui_runtime.restore application saved;
          raise failure)
      end in
    update_source (Signal.sample source);
    let clear_adopted_pins = Option.map (fun viewport ->
      Lui_virtual.Internal.adopt_pins viewport ~node:parent (fun pins ->
        adopted_pins := List.sort_uniq Int.compare (List.rev_append pins !adopted_pins))) viewport in
    let unsubscribe_retention = Option.map (fun viewport ->
      Lui_virtual.Internal.on_change viewport (fun () ->
        context.Lui_ui.ui_protect (fun () ->
        if not !stopped && Lui_runtime.node_live application parent then begin
          let selected = visible_indices !positions in
          reconcile_indices !dataset !positions !scroll_positions !revision selected
        end))) viewport in
    Lui_runtime.journal_ref application Lui_runtime.Segment_on_property
      segment.Lui_runtime.dynamic_segment_id segment.Lui_runtime.dynamic_segment_on_property (Some (fun name value ->
      if name = Lui_protocol.ScrollTarget && not !stopped then
        Lui_runtime.set_prop application parent Lui_protocol.VirtualScrollIndex
          (Lui_protocol.IntValue (target !scroll_positions value))));
    let subscription = Signal.subscribe ~emit_initial:false source (fun items ->
      context.Lui_ui.ui_protect (fun () -> update_source items)) in
    ignore (Signal.own context.Lui_ui.ui_scope subscription);
    Lui_ui.on_event context parent (function
      | Lui_protocol.VirtualWindow (_, epoch, first, last, pins)
        when not !stopped && epoch = !revision ->
        if first < 0 || last < first then invalid_arg "invalid virtual row window";
        let count = Array.length !dataset in
        let first = min count first and last = min count last in
        (* Native emits its current pin snapshot before a released receipt.
           The receipt's adopted snapshot also covers the immediate cold-key
           removal, until the next current-generation window replaces it. *)
        let pins = List.filter (Lui_runtime.node_live application) pins in
        let selected = List.init (last - first) (fun index -> first + index) in
        context.Lui_ui.ui_protect (fun () ->
          reconcile_indices ~window_pins:pins !dataset !positions !scroll_positions !revision selected)
      | _ -> ());
    let dispose () =
      if not !stopped then begin
        stopped := true;
        Signal.dispose_subscription subscription;
        Option.iter (fun unsubscribe -> unsubscribe ()) unsubscribe_retention;
        Option.iter (fun clear -> clear ()) clear_adopted_pins;
        Lui_runtime.journal_ref application Lui_runtime.Segment_on_property
          segment.Lui_runtime.dynamic_segment_id segment.Lui_runtime.dynamic_segment_on_property None;
        dataset := [||]; positions := Keys.empty;
        window_keys := []; native_pins := []; adopted_pins := [];
        scroll_positions := Lui_protocol.String_map.empty;
        keyed.dispose_dynamic_keyed ()
      end in
    Signal.on_dispose context.Lui_ui.ui_scope dispose;
    { keyed with dispose_dynamic_keyed = dispose }
  end

let keyed_node keyed_value key =
  match
    find_key_node !(keyed_value.key_nodes) key keyed_value.key_compare
  with
  | Some node -> node
  | None -> invalid_arg "keyed node not found"

let dispose_keyed keyed_value = keyed_value.dispose_dynamic_keyed ()

type mounted_range = {
  range_segment : Lui_runtime.dynamic_segment;
  range_context : Lui_ui.ui_context;
}

let rec range_contains owner segment =
  owner == segment || match segment.Lui_runtime.dynamic_segment_owner with
  | None -> false
  | Some parent -> range_contains owner parent

let range_nodes application segment =
  let parent = Lui_runtime.canonical_node application segment.Lui_runtime.dynamic_segment_parent in
  match Hashtbl.find_opt application.Lui_runtime.runtime_children parent with
  | None -> []
  | Some children -> List.init !(segment.Lui_runtime.dynamic_segment_size)
      (fun index -> Lui_sequence.get children (!(segment.Lui_runtime.dynamic_segment_base) + index))

let retire_range ?(drop = true) application segment =
  if !(segment.Lui_runtime.dynamic_segment_active) then begin
    let parent = Lui_runtime.canonical_node application segment.Lui_runtime.dynamic_segment_parent in
    let nodes = if drop then range_nodes application segment else [] in
    if !(segment.Lui_runtime.dynamic_segment_size) <> 0 then
      Lui_runtime.resize_dynamic_segment application segment
        (- !(segment.Lui_runtime.dynamic_segment_size));
    let current = Option.value
      (Hashtbl.find_opt application.Lui_runtime.dynamic_segments parent) ~default:[] in
    let remaining = List.filter (fun child ->
      if range_contains segment child then begin
        Lui_runtime.journal_ref application Lui_runtime.Segment_active
          child.Lui_runtime.dynamic_segment_id child.Lui_runtime.dynamic_segment_active false;
        decr application.Lui_runtime.runtime_dynamic_segment_count;
        false
      end else true) current in
    Lui_runtime.journal_list application Lui_runtime.Segment_member
      application.Lui_runtime.dynamic_segments parent
      (fun child -> child.Lui_runtime.dynamic_segment_id) remaining;
    List.iter (drop_branch_node application parent) nodes
  end

let range_owner context parent =
  match context.Lui_ui.ui_dynamic_owner with
  | Some owner when
      Lui_runtime.canonical_node context.Lui_ui.ui_application owner.Lui_runtime.dynamic_segment_parent
      = Lui_runtime.canonical_node context.Lui_ui.ui_application parent -> Some owner
  | _ -> None

let range_segment context parent =
  Lui_runtime.register_dynamic_segment ?owner:(range_owner context parent)
    context.Lui_ui.ui_application parent

let register_range_at application parent owner position =
  let parent = Lui_runtime.canonical_node application parent in
  let segment = Lui_runtime.register_dynamic_segment ~owner application parent in
  match position with
  | `End -> segment
  | `Start ->
    let current = Hashtbl.find application.Lui_runtime.dynamic_segments parent in
    let rec at_start = function
      | s :: next :: _ when s == segment -> next == owner
      | _ :: rest -> at_start rest
      | [] -> false in
    if at_start current then segment
    else begin
      let rec place acc = function
        | [] -> invalid_arg "dynamic range owner is not registered"
        | s :: rest when s == segment -> place acc rest
        | s :: rest when s == owner -> List.rev_append acc (segment :: s :: rest)
        | s :: rest -> place (s :: acc) rest in
      let reordered = place [] current in
      Lui_runtime.journal_ref application Lui_runtime.Segment_base
        segment.Lui_runtime.dynamic_segment_id segment.Lui_runtime.dynamic_segment_base
        !(owner.Lui_runtime.dynamic_segment_base);
      Lui_runtime.journal_list application Lui_runtime.Segment_member
        application.Lui_runtime.dynamic_segments parent
        (fun s -> s.Lui_runtime.dynamic_segment_id) reordered;
      segment
    end
  | `After prev ->
    let current = Hashtbl.find application.Lui_runtime.dynamic_segments parent in
    let rec already_after = function
      | s :: next :: _ when s == segment -> range_contains prev next
      | _ :: rest -> already_after rest
      | [] -> false in
    if already_after current then segment
    else begin
      let rec place acc = function
        | [] -> invalid_arg "previous dynamic range is not registered"
        | s :: rest when s == segment -> place acc rest
        | (s :: _ as all) when range_contains prev s -> List.rev_append acc (segment :: all)
        | s :: rest -> place (s :: acc) rest in
      let reordered = place [] current in
      let target_base =
        !(prev.Lui_runtime.dynamic_segment_base) + !(prev.Lui_runtime.dynamic_segment_size) in
      Lui_runtime.journal_ref application Lui_runtime.Segment_base
        segment.Lui_runtime.dynamic_segment_id segment.Lui_runtime.dynamic_segment_base
        target_base;
      Lui_runtime.journal_list application Lui_runtime.Segment_member
        application.Lui_runtime.dynamic_segments parent
        (fun s -> s.Lui_runtime.dynamic_segment_id) reordered;
      segment
    end

let create_range ?name ?(persistent = true) ?(position = `End) context parent owner =
  let name = match name with Some name -> name | None -> Lui_ui.owner_name context "dynamic-range" in
  let context = if persistent then Lui_ui.child_context context name else
    { (Lui_ui.context context.Lui_ui.ui_application (Signal.child_scope name context.Lui_ui.ui_scope))
      with Lui_ui.ui_protect = context.Lui_ui.ui_protect } in
  let segment = register_range_at context.Lui_ui.ui_application parent owner position in
  let context = { context with Lui_ui.ui_dynamic_owner = Some segment } in
  Signal.on_unmount context.Lui_ui.ui_scope (fun () ->
    retire_range context.Lui_ui.ui_application segment);
  { range_segment = segment; range_context = context }

let mount_range ?name ?persistent context parent owner mount =
  let range = create_range ?name ?persistent context parent owner in
  let context = range.range_context and segment = range.range_segment in
  (try mount context with failure ->
    (try Signal.dispose_scope context.Lui_ui.ui_scope with _ -> ());
    retire_range context.Lui_ui.ui_application segment;
    raise failure);
  range

let dispose_range range = Signal.dispose_scope range.range_context.Lui_ui.ui_scope

let switch_range context parent source equal mount =
  let application = context.Lui_ui.ui_application in
  let owner = range_segment context parent in
  Signal.on_unmount context.Lui_ui.ui_scope (fun () -> retire_range application owner);
  let name = Lui_ui.owner_name context "switch-branch" in
  let initial = Signal.sample source in
  let current = ref (mount_range ~name context parent owner (fun context -> ignore (mount context initial))) in
  let value = ref initial in
  Signal.mount (!current).range_context.Lui_ui.ui_scope;
  let subscription = Signal.subscribe ~emit_initial:false source (fun next ->
    context.Lui_ui.ui_protect (fun () ->
      if !(owner.Lui_runtime.dynamic_segment_active) && not (equal !value next) then begin
        let old = !current in
        let old_nodes = range_nodes application old.range_segment in
        let base = !(old.range_segment.Lui_runtime.dynamic_segment_base) in
        let saved = Lui_runtime.checkpoint_subtree application parent parent in
        let finish_replacements = replacing_virtual_nodes application
          (List.concat_map (Lui_runtime.collect_subtree_nodes application.Lui_runtime.runtime_children) old_nodes) in
        let candidate = ref None in
        let committed = ref false in
        try
          let fresh = mount_range ~name context parent owner (fun context -> ignore (mount context next)) in
          candidate := Some fresh;
          ignore (Lui_runtime.reconcile_forest ~range:(base, List.length old_nodes)
            application saved parent old_nodes (range_nodes application fresh.range_segment));
          Signal.mount fresh.range_context.Lui_ui.ui_scope;
          finish_replacements ();
          List.iter (Lui_runtime.retire_checkpoint_dynamic_segments application saved) old_nodes;
          retire_range ~drop:false application old.range_segment;
          current := fresh;
          value := next;
          committed := true;
          dispose_range old
        with failure ->
          finish_replacements ();
          if not !committed then begin
            Option.iter (fun fresh -> retire_range ~drop:false application fresh.range_segment) !candidate;
            Lui_runtime.restore application saved;
            Option.iter (fun fresh -> try dispose_range fresh with _ -> ()) !candidate
          end;
          raise failure
      end)) in
  Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
    Signal.dispose_subscription subscription;
    Fun.protect (fun () -> dispose_range !current)
      ~finally:(fun () -> retire_range application owner))

let conditional_range context parent source mount =
  switch_range context parent source Bool.equal
    (fun context visible -> if visible then ignore (mount context))

type 'a range_entry = {
  entry_range : mounted_range;
  entry_state : 'a Signal.state;
}

let weighted_lis ~max_rank ranks weights =
  let n = Array.length ranks in
  let in_lis = Array.make n false in
  if n > 0 && max_rank > 0 then begin
    let bit_val = Array.make (max_rank + 1) 0 in
    let bit_idx = Array.make (max_rank + 1) (-1) in
    let prev = Array.make n (-1) in
    let best_total = ref 0 and best_end = ref (-1) in
    for i = 0 to n - 1 do
      let w = weights.(i) in
      if w > 0 then begin
        let r = ranks.(i) in
        let best_w = ref 0 and best_i = ref (-1) and idx = ref r in
        while !idx > 0 do
          if bit_val.(!idx) > !best_w then begin
            best_w := bit_val.(!idx);
            best_i := bit_idx.(!idx)
          end;
          idx := !idx - (!idx land (- !idx))
        done;
        let total = !best_w + w in
        prev.(i) <- !best_i;
        let idx = ref (r + 1) in
        while !idx <= max_rank do
          if total > bit_val.(!idx) then begin
            bit_val.(!idx) <- total;
            bit_idx.(!idx) <- i
          end;
          idx := !idx + (!idx land (- !idx))
        done;
        if total > !best_total then begin
          best_total := total;
          best_end := i
        end
      end
    done;
    let cur = ref !best_end in
    while !cur <> -1 do
      in_lis.(!cur) <- true;
      cur := prev.(!cur)
    done
  end;
  in_lis

let reorder_ranges application owner ranges =
  let parent = Lui_runtime.canonical_node application owner.Lui_runtime.dynamic_segment_parent in
  let m = Array.length ranges in
  let groups = Hashtbl.create (max 1 m) in
  let old_ranks = Hashtbl.create (max 1 m) in
  let rec child_of_owner segment =
    match segment.Lui_runtime.dynamic_segment_owner with
    | Some parent when parent == owner -> Some segment
    | Some parent -> child_of_owner parent
    | None -> None in
  let registered = List.rev (Hashtbl.find application.Lui_runtime.dynamic_segments parent) in
  let non_empty = ref [] in
  let next_rank = ref 0 in
  List.iter (fun segment -> Option.iter (fun root ->
    let id = root.Lui_runtime.dynamic_segment_id in
    if segment == root then begin
      Hashtbl.replace old_ranks id !next_rank;
      incr next_rank;
      if !(root.Lui_runtime.dynamic_segment_size) > 0 then
        non_empty := root :: !non_empty
    end;
    let previous = Option.value (Hashtbl.find_opt groups id) ~default:[] in
    Hashtbl.replace groups id (segment :: previous)) (child_of_owner segment)) registered;
  let ranks = Array.init m (fun i ->
    Hashtbl.find old_ranks ranges.(i).Lui_runtime.dynamic_segment_id) in
  let sizes = Array.init m (fun i -> !(ranges.(i).Lui_runtime.dynamic_segment_size)) in
  let in_lis = weighted_lis ~max_rank:!next_rank ranks sizes in
  let needs_move = ref false in
  for i = 0 to m - 1 do
    if sizes.(i) > 0 && not in_lis.(i) then needs_move := true
  done;
  if !needs_move then begin
    let positions = Lui_indexed_sequence.of_list [] in
    List.iteri (fun idx seg ->
      let id = seg.Lui_runtime.dynamic_segment_id in
      Lui_indexed_sequence.insert positions idx id;
      Lui_indexed_sequence.set_weight positions id !(seg.Lui_runtime.dynamic_segment_size))
      (List.rev !non_empty);
    let owner_base = !(owner.Lui_runtime.dynamic_segment_base) in
    let owner_size = !(owner.Lui_runtime.dynamic_segment_size) in
    let anchor = ref None in
    for i = m - 1 downto 0 do
      let w = sizes.(i) in
      if w > 0 then begin
        let seg = ranges.(i) in
        let id = seg.Lui_runtime.dynamic_segment_id in
        if not in_lis.(i) then begin
          let src_slot = Option.get (Lui_indexed_sequence.index positions id) in
          let cur_0 = owner_base + Lui_indexed_sequence.prefix_weight positions src_slot in
          let anchor_slot, anchor_pos = match !anchor with
            | None -> Lui_indexed_sequence.length positions, owner_base + owner_size
            | Some anchor_id ->
              let slot = Option.get (Lui_indexed_sequence.index positions anchor_id) in
              slot, owner_base + Lui_indexed_sequence.prefix_weight positions slot in
          if cur_0 + w <> anchor_pos then begin
            if cur_0 < anchor_pos then begin
              let target = anchor_pos - 1 in
              for _ = 0 to w - 1 do
                let children = Hashtbl.find application.Lui_runtime.runtime_children parent in
                let node = Lui_sequence.get children cur_0 in
                Lui_runtime.move_child_at application parent node cur_0 target
              done;
              Lui_indexed_sequence.move positions id (anchor_slot - 1);
              Lui_indexed_sequence.set_weight positions id w
            end else begin
              for offset = 0 to w - 1 do
                let children = Hashtbl.find application.Lui_runtime.runtime_children parent in
                let from_index = cur_0 + offset in
                let node = Lui_sequence.get children from_index in
                Lui_runtime.move_child_at application parent node from_index (anchor_pos + offset)
              done;
              Lui_indexed_sequence.move positions id anchor_slot;
              Lui_indexed_sequence.set_weight positions id w
            end
          end
        end;
        anchor := Some id
      end
    done
  end;
  let rec split_at_owner prefix = function
    | [] -> prefix, []
    | current :: rest when current == owner -> current :: prefix, rest
    | current :: rest -> split_at_owner (current :: prefix) rest in
  let prefix_with_owner_rev, after_owner = split_at_owner [] registered in
  let cursor = ref !(owner.Lui_runtime.dynamic_segment_base) in
  let acc = ref prefix_with_owner_rev in
  for i = 0 to m - 1 do
    let range = ranges.(i) in
    let shift = !cursor - !(range.Lui_runtime.dynamic_segment_base) in
    cursor := !cursor + sizes.(i);
    let group = List.rev (Hashtbl.find groups range.Lui_runtime.dynamic_segment_id) in
    List.iter (fun segment ->
      if shift <> 0 then
        Lui_runtime.journal_ref application Lui_runtime.Segment_base
          segment.Lui_runtime.dynamic_segment_id segment.Lui_runtime.dynamic_segment_base
          (!(segment.Lui_runtime.dynamic_segment_base) + shift);
      acc := segment :: !acc) group
  done;
  List.iter (fun segment ->
    if not (range_contains owner segment) then acc := segment :: !acc) after_owner;
  Lui_runtime.journal_list application Lui_runtime.Segment_member
    application.Lui_runtime.dynamic_segments parent
    (fun s -> s.Lui_runtime.dynamic_segment_id) !acc

let keyed_range (type key) context parent source key compare mount =
  let module Keys = Map.Make (struct
    type t = key * int
    let compare (a, i) (b, j) = let order = compare a b in
      if order = 0 then Int.compare i j else order
  end) in
  let application = context.Lui_ui.ui_application in
  let owner = range_segment context parent in
  let entries = ref Keys.empty in
  let ordered = ref [||] in
  Signal.on_unmount context.Lui_ui.ui_scope (fun () -> retire_range application owner);
  let dispose entry = Fun.protect (fun () -> dispose_range entry.entry_range)
    ~finally:(fun () -> Signal.dispose_signal (Signal.value entry.entry_state)) in
  let dispose_all entries =
    let failure = ref None in
    List.iter (fun entry -> try dispose entry with error ->
      if !failure = None then failure := Some error) entries;
    match !failure with None -> () | Some error -> raise error in
  let deliver_updates_and_dispose updates removed =
    (try
       List.iter (fun (entry, item) -> Signal.set entry.entry_state item) (List.rev updates)
     with error ->
       List.iter (fun entry -> try dispose entry with _ -> ()) removed;
       raise error);
    dispose_all removed in
  let reconcile items =
    if !(owner.Lui_runtime.dynamic_segment_active) && Lui_runtime.node_live application parent then begin
      let items = Array.of_list items in
      let identities = occurrence_keys parent key compare items in
      let old = !ordered in
      let n = Array.length items in
      let old_len = Array.length old in
      let same_order = ref (n = old_len) in
      let idx = ref 0 in
      while !same_order && !idx < n do
        let (prev_key, prev_occ), _ = old.(!idx) in
        let next_key, next_occ = identities.(!idx) in
        if compare prev_key next_key <> 0 || prev_occ <> next_occ then
          same_order := false;
        incr idx
      done;
      if !same_order then begin
        for index = 0 to n - 1 do
          let _, entry = old.(index) in
          let item = items.(index) in
          if item != Signal.get_state entry.entry_state then
            Signal.set entry.entry_state item
        done
      end else begin
        let old_positions = ref Keys.empty in
        Array.iteri (fun index (identity, _) ->
          old_positions := Keys.add identity index !old_positions) old;
        let desired_set = ref Keys.empty in
        let fresh_count = ref 0 in
        let updates = ref [] in
        let retained_rev = ref [] in
        let last_old_pos = ref (-1) in
        let retained_in_order = ref true in
        for index = 0 to n - 1 do
          let identity = identities.(index) in
          desired_set := Keys.add identity index !desired_set;
          match Keys.find_opt identity !entries with
          | Some entry ->
            let item = items.(index) in
            if item != Signal.get_state entry.entry_state then
              updates := (entry, item) :: !updates;
            let pos = Keys.find identity !old_positions in
            if pos < !last_old_pos then retained_in_order := false;
            last_old_pos := pos;
            retained_rev := (pos, entry) :: !retained_rev
          | None ->
            incr fresh_count
        done;
        let removed_rev = ref [] in
        for index = 0 to old_len - 1 do
          let identity, entry = old.(index) in
          if not (Keys.mem identity !desired_set) then
            removed_rev := (index, entry) :: !removed_rev
        done;
        let removed_with_pos = List.rev !removed_rev in
        let removed = List.map snd removed_with_pos in
        if !fresh_count = 0 then begin
          List.iter (fun entry -> retire_range application entry.entry_range.range_segment) removed;
          let retained = Array.of_list (List.rev !retained_rev) in
          let next_entries = ref Keys.empty in
          let next_ordered = Array.init n (fun index ->
            let identity = identities.(index) in
            let _, entry = retained.(index) in
            next_entries := Keys.add identity entry !next_entries;
            identity, entry) in
          if not !retained_in_order then
            reorder_ranges application owner
              (Array.map (fun (_, entry) -> entry.entry_range.range_segment) next_ordered);
          entries := !next_entries;
          ordered := next_ordered;
          deliver_updates_and_dispose !updates removed
        end else begin
          let canonical_parent = Lui_runtime.canonical_node application parent in
          let saved = Lui_runtime.checkpoint ~nodes:[canonical_parent] application in
          let finish_replacements =
            if removed <> [] &&
               (Hashtbl.length application.Lui_runtime.runtime_virtual_sources > 0
                || Hashtbl.length application.Lui_runtime.runtime_virtual_owners > 0) then
              let retiring = List.concat_map (fun entry ->
                List.concat_map
                  (Lui_runtime.collect_subtree_nodes application.Lui_runtime.runtime_children)
                  (range_nodes application entry.entry_range.range_segment)) removed in
              replacing_virtual_nodes application retiring
            else fun () -> () in
          let fresh = ref [] in
          let next = ref Keys.empty in
          let committed = ref false in
          (try
             if old_len > 0 && not !retained_in_order then begin
               let retained = Array.of_list (List.rev !retained_rev) in
               if removed_with_pos = [] then
                 reorder_ranges application owner
                   (Array.map (fun (_, entry) -> entry.entry_range.range_segment) retained)
               else begin
                 (* Interleave removed entries before the first LIS-kept retained entry
                    with a larger old index so removed segments stay stationary and
                    untouched until after every fresh entry mounts. *)
                 let r_len = Array.length retained in
                 let r_ranks = Array.init r_len (fun i -> fst retained.(i)) in
                 let r_sizes = Array.init r_len (fun i ->
                   !((snd retained.(i)).entry_range.range_segment.Lui_runtime.dynamic_segment_size)) in
                 let r_in_lis = weighted_lis ~max_rank:old_len r_ranks r_sizes in
                 let rem_arr = Array.of_list removed_with_pos in
                 let rem_len = Array.length rem_arr in
                 let rem_idx = ref 0 in
                 let augmented_rev = ref [] in
                 for i = 0 to r_len - 1 do
                   let pos, entry = retained.(i) in
                   if r_in_lis.(i) then
                     while !rem_idx < rem_len && fst rem_arr.(!rem_idx) < pos do
                       augmented_rev := (snd rem_arr.(!rem_idx)).entry_range.range_segment :: !augmented_rev;
                       incr rem_idx
                     done;
                   augmented_rev := entry.entry_range.range_segment :: !augmented_rev
                 done;
                 while !rem_idx < rem_len do
                   augmented_rev := (snd rem_arr.(!rem_idx)).entry_range.range_segment :: !augmented_rev;
                   incr rem_idx
                 done;
                 reorder_ranges application owner (Array.of_list (List.rev !augmented_rev))
               end
             end;
             let prev_seg = ref None in
             let next_ordered_rev = ref [] in
             for index = 0 to n - 1 do
               let identity = identities.(index) in
               let entry = match Keys.find_opt identity !entries with
                 | Some entry ->
                   prev_seg := Some entry.entry_range.range_segment;
                   entry
                 | None ->
                   let state = Signal.state context.Lui_ui.ui_scheduler items.(index) in
                   let position = match !prev_seg with
                     | None -> `Start
                     | Some prev -> `After prev in
                   let range = try create_range ~persistent:false ~position context parent owner
                     with failure ->
                       Signal.dispose_signal (Signal.value state);
                       raise failure in
                   let entry = { entry_range = range; entry_state = state } in
                   fresh := entry :: !fresh;
                   ignore (mount range.range_context (Signal.value state));
                   Signal.mount range.range_context.Lui_ui.ui_scope;
                   prev_seg := Some range.range_segment;
                   entry in
               next := Keys.add identity entry !next;
               next_ordered_rev := (identity, entry) :: !next_ordered_rev
             done;
             finish_replacements ();
             List.iter (fun entry -> retire_range application entry.entry_range.range_segment) removed;
             entries := !next;
             ordered := Array.of_list (List.rev !next_ordered_rev);
             committed := true
           with failure ->
             finish_replacements ();
             if not !committed then begin
               (match Hashtbl.find_opt application.Lui_runtime.dynamic_segments canonical_parent with
                | Some segments ->
                  List.iter (fun segment ->
                    if segment.Lui_runtime.dynamic_segment_id >
                       saved.Lui_runtime.checkpoint_next_dynamic_segment_id then
                      segment.Lui_runtime.dynamic_segment_active := false) segments
                | None -> ());
               for id = !(application.Lui_runtime.next_node_id)
                 downto saved.Lui_runtime.checkpoint_next_node_id + 1 do
                 if Lui_runtime.node_live application id then
                   Lui_runtime.drop_subtree application id
               done;
               Lui_runtime.restore application saved;
               List.iter (fun entry -> try dispose entry with _ -> ()) !fresh
             end;
             raise failure);
          deliver_updates_and_dispose !updates removed
        end
      end
    end in
  reconcile (Signal.sample source);
  let subscription = Signal.subscribe ~emit_initial:false source (fun items ->
    context.Lui_ui.ui_protect (fun () -> reconcile items)) in
  Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
    Signal.dispose_subscription subscription;
    let previous = !ordered in
    ordered := [||];
    entries := Keys.empty;
    Fun.protect (fun () ->
      let failure = ref None in
      for index = Array.length previous - 1 downto 0 do
        let _, entry = previous.(index) in
        try dispose entry with error ->
          if !failure = None then failure := Some error
      done;
      match !failure with None -> () | Some error -> raise error)
      ~finally:(fun () -> retire_range application owner))
