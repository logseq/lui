(* Retained runtime: mounts a node tree, queues patch ops, and flushes
   patch batches to a backend after signal stabilization. *)

open Lui_protocol

type event_handler = {
  handler_id : int;
  handler_callback : event -> unit;
}

type dynamic_segment = {
  dynamic_segment_id : int;
  dynamic_segment_parent : int;
  dynamic_segment_base : int ref;
  dynamic_segment_size : int ref;
  dynamic_segment_active : bool ref;
}

type flush_status =
  | NotFlushed
  | NoBatch
  | Applied
  | Rejected

type flush_diagnostics = {
  flush_status : flush_status;
  flush_generation : int;
  flush_operation_count : int;
  flush_pending_operation_count : int;
  flush_mounted_node_count : int;
  flush_handler_count : int;
  flush_dynamic_segment_count : int;
  flush_signal_generation : int;
  flush_signal_round_count : int;
  flush_signal_effect_count : int;
  flush_signal_dirty_task_count : int;
}

type application = {
  runtime_scheduler : Signal.scheduler;
  runtime_backend : backend;
  runtime_extension_registry : Lui_extension.extension_registry;
  next_node_id : int ref;
  mounted_nodes : (int, node_kind) Hashtbl.t;
  runtime_extension_nodes : (int, string) Hashtbl.t;
  runtime_properties : (int, wire_value Property_map.t) Hashtbl.t;
  runtime_extension_properties : (int, wire_value String_map.t) Hashtbl.t;
  runtime_children : (int, int list) Hashtbl.t;
  runtime_parents : (int, int) Hashtbl.t;
  pending_ops : patch_op list ref; (* stored in reverse order *)
  runtime_generation : int ref;
  runtime_diagnostics : flush_diagnostics ref;
  next_handler_id : int ref;
  event_handlers : (int, event_handler list) Hashtbl.t;
  next_dynamic_segment_id : int ref;
  dynamic_segments : (int, dynamic_segment list) Hashtbl.t;
  runtime_reload_keys : (int, string) Hashtbl.t;
  runtime_node_aliases : (int, int) Hashtbl.t;
  runtime_handler_count : int ref;
  runtime_dynamic_segment_count : int ref;
  runtime_extension_dirty : bool ref;
}

type runtime_checkpoint = {
  checkpoint_generation : int;
  checkpoint_next_node_id : int;
  checkpoint_mounted_nodes : (int, node_kind) Hashtbl.t;
  checkpoint_extension_nodes : (int, string) Hashtbl.t;
  checkpoint_properties : (int, wire_value Property_map.t) Hashtbl.t;
  checkpoint_extension_properties : (int, wire_value String_map.t) Hashtbl.t;
  checkpoint_children : (int, int list) Hashtbl.t;
  checkpoint_parents : (int, int) Hashtbl.t;
  checkpoint_pending_ops : patch_op list;
  checkpoint_next_handler_id : int;
  checkpoint_event_handlers : (int, event_handler list) Hashtbl.t;
  checkpoint_next_dynamic_segment_id : int;
  checkpoint_dynamic_segments : (int, dynamic_segment list) Hashtbl.t;
  checkpoint_reload_keys : (int, string) Hashtbl.t;
  checkpoint_node_aliases : (int, int) Hashtbl.t;
  checkpoint_handler_count : int;
  checkpoint_dynamic_segment_count : int;
  checkpoint_extension_dirty : bool;
}

type render_tree_snapshot = {
  render_mounted_nodes : (int, node_kind) Hashtbl.t;
  render_extension_nodes : (int, string) Hashtbl.t;
  render_properties : (int, wire_value Property_map.t) Hashtbl.t;
  render_extension_properties : (int, wire_value String_map.t) Hashtbl.t;
  render_children : (int, int list) Hashtbl.t;
  render_reload_keys : (int, string) Hashtbl.t;
}

let empty_diagnostics () =
  {
    flush_status = NotFlushed;
    flush_generation = 0;
    flush_operation_count = 0;
    flush_pending_operation_count = 0;
    flush_mounted_node_count = 0;
    flush_handler_count = 0;
    flush_dynamic_segment_count = 0;
    flush_signal_generation = 0;
    flush_signal_round_count = 0;
    flush_signal_effect_count = 0;
    flush_signal_dirty_task_count = 0;
  }

let create_with_extensions scheduler backend registry =
  Lui_extension.freeze registry;
  {
    runtime_scheduler = scheduler;
    runtime_backend = backend;
    runtime_extension_registry = registry;
    next_node_id = ref 0;
    mounted_nodes = Hashtbl.create 16;
    runtime_extension_nodes = Hashtbl.create 16;
    runtime_properties = Hashtbl.create 16;
    runtime_extension_properties = Hashtbl.create 16;
    runtime_children = Hashtbl.create 16;
    runtime_parents = Hashtbl.create 16;
    pending_ops = ref [];
    runtime_generation = ref 0;
    runtime_diagnostics = ref (empty_diagnostics ());
    next_handler_id = ref 0;
    event_handlers = Hashtbl.create 16;
    next_dynamic_segment_id = ref 0;
    dynamic_segments = Hashtbl.create 16;
    runtime_reload_keys = Hashtbl.create 16;
    runtime_node_aliases = Hashtbl.create 16;
    runtime_handler_count = ref 0;
    runtime_dynamic_segment_count = ref 0;
    runtime_extension_dirty = ref false;
  }

let create scheduler backend =
  create_with_extensions scheduler backend (Lui_extension.registry ())

let checkpoint application =
  {
    checkpoint_generation = !(application.runtime_generation);
    checkpoint_next_node_id = !(application.next_node_id);
    checkpoint_mounted_nodes = Hashtbl.copy application.mounted_nodes;
    checkpoint_extension_nodes = Hashtbl.copy application.runtime_extension_nodes;
    checkpoint_properties =
      Hashtbl.fold
        (fun node values acc -> Hashtbl.add acc node values; acc)
        application.runtime_properties (Hashtbl.create 16);
    checkpoint_extension_properties =
      Hashtbl.copy application.runtime_extension_properties;
    checkpoint_children = Hashtbl.copy application.runtime_children;
    checkpoint_parents = Hashtbl.copy application.runtime_parents;
    checkpoint_pending_ops = !(application.pending_ops);
    checkpoint_next_handler_id = !(application.next_handler_id);
    checkpoint_event_handlers = Hashtbl.copy application.event_handlers;
    checkpoint_next_dynamic_segment_id =
      !(application.next_dynamic_segment_id);
    checkpoint_dynamic_segments = Hashtbl.copy application.dynamic_segments;
    checkpoint_reload_keys = Hashtbl.copy application.runtime_reload_keys;
    checkpoint_node_aliases = Hashtbl.copy application.runtime_node_aliases;
    checkpoint_handler_count = !(application.runtime_handler_count);
    checkpoint_dynamic_segment_count =
      !(application.runtime_dynamic_segment_count);
    checkpoint_extension_dirty = !(application.runtime_extension_dirty);
  }

let render_tree_snapshot application =
  {
    render_mounted_nodes = application.mounted_nodes;
    render_extension_nodes = application.runtime_extension_nodes;
    render_properties = application.runtime_properties;
    render_extension_properties = application.runtime_extension_properties;
    render_children = application.runtime_children;
    render_reload_keys = application.runtime_reload_keys;
  }

let restore application saved =
  if !(application.runtime_generation) <> saved.checkpoint_generation then
    invalid_arg "cannot restore a stale runtime checkpoint";
  application.next_node_id := saved.checkpoint_next_node_id;
  let replace target source =
    Hashtbl.reset target;
    Hashtbl.iter (fun key value -> Hashtbl.replace target key value) source
  in
  replace application.mounted_nodes saved.checkpoint_mounted_nodes;
  replace application.runtime_extension_nodes saved.checkpoint_extension_nodes;
  replace application.runtime_properties saved.checkpoint_properties;
  replace application.runtime_extension_properties
    saved.checkpoint_extension_properties;
  replace application.runtime_children saved.checkpoint_children;
  replace application.runtime_parents saved.checkpoint_parents;
  application.pending_ops := saved.checkpoint_pending_ops;
  application.next_handler_id := saved.checkpoint_next_handler_id;
  replace application.event_handlers saved.checkpoint_event_handlers;
  application.next_dynamic_segment_id :=
    saved.checkpoint_next_dynamic_segment_id;
  replace application.dynamic_segments saved.checkpoint_dynamic_segments;
  replace application.runtime_reload_keys saved.checkpoint_reload_keys;
  replace application.runtime_node_aliases saved.checkpoint_node_aliases;
  application.runtime_handler_count := saved.checkpoint_handler_count;
  application.runtime_dynamic_segment_count :=
    saved.checkpoint_dynamic_segment_count;
  application.runtime_extension_dirty := saved.checkpoint_extension_dirty

let canonical_node application node =
  match Hashtbl.find_opt application.runtime_node_aliases node with
  | Some canonical -> canonical
  | None -> node

let map_node mapping node =
  match Hashtbl.find_opt mapping node with
  | Some mapped -> mapped
  | None -> node

let node_compatible application saved old_node candidate_node =
  match Hashtbl.find_opt saved.checkpoint_mounted_nodes old_node with
  | Some old_kind ->
    (match Hashtbl.find_opt application.mounted_nodes candidate_node with
    | Some candidate_kind -> old_kind = candidate_kind
    | None -> false)
  | None ->
    (match Hashtbl.find_opt saved.checkpoint_extension_nodes old_node with
    | Some old_identifier ->
      (match
         Hashtbl.find_opt application.runtime_extension_nodes candidate_node
       with
      | Some candidate_identifier -> old_identifier = candidate_identifier
      | None -> false)
    | None -> false)

let keyed_children children reload_keys =
  List.fold_left
    (fun result child ->
       match Hashtbl.find_opt reload_keys child with
       | Some key ->
         if Hashtbl.mem result key then
           invalid_arg "duplicate reload key among siblings";
         Hashtbl.replace result key child;
         result
       | None -> result)
    (Hashtbl.create 8) children

let rec collect_node_mapping application saved old_node candidate_node
    mapping =
  if not (node_compatible application saved old_node candidate_node) then
    mapping
  else begin
    Hashtbl.replace mapping candidate_node old_node;
    let old_children =
      match Hashtbl.find_opt saved.checkpoint_children old_node with
      | Some children -> children
      | None -> []
    in
    let candidate_children =
      match Hashtbl.find_opt application.runtime_children candidate_node with
      | Some children -> children
      | None -> []
    in
    let old_reload_keys = saved.checkpoint_reload_keys in
    let candidate_reload_keys = application.runtime_reload_keys in
    let old_keyed = keyed_children old_children old_reload_keys in
    ignore (keyed_children candidate_children candidate_reload_keys);
    List.iteri
      (fun index candidate_child ->
         let old_child =
           match Hashtbl.find_opt candidate_reload_keys candidate_child with
           | Some key -> Hashtbl.find_opt old_keyed key
           | None ->
             if index < List.length old_children then
               let position_child = List.nth old_children index in
               if Hashtbl.mem old_reload_keys position_child then None
               else Some position_child
             else None
         in
         match old_child with
         | Some matched ->
           ignore
             (collect_node_mapping application saved matched candidate_child
                mapping)
         | None -> ())
      candidate_children;
    mapping
  end

let collect_subtree_nodes children_map root =
  let rec collect node acc =
    let children =
      match Hashtbl.find_opt children_map node with
      | Some current -> current
      | None -> []
    in
    List.fold_left (fun acc child -> collect child acc) (node :: acc) children
  in
  List.rev (collect root [])

let retire_checkpoint_dynamic_segments saved root =
  List.iter
    (fun node ->
       match Hashtbl.find_opt saved.checkpoint_dynamic_segments node with
       | Some segments ->
         List.iter
           (fun segment -> segment.dynamic_segment_active := false)
           segments
       | None -> ())
    (collect_subtree_nodes saved.checkpoint_children root)

let remove_node_keys values nodes =
  List.iter (fun node -> Hashtbl.remove values node) nodes

let remap_node_values source candidate_nodes mapping base =
  List.iter
    (fun candidate ->
       match Hashtbl.find_opt source candidate with
       | Some value ->
         Hashtbl.replace base (map_node mapping candidate) value
       | None -> ())
    candidate_nodes;
  base

let remap_children source candidate_nodes mapping base =
  List.iter
    (fun candidate ->
       let children =
         match Hashtbl.find_opt source candidate with
         | Some current -> current
         | None -> []
       in
       Hashtbl.replace base
         (map_node mapping candidate)
         (List.map (fun child -> map_node mapping child) children))
    candidate_nodes;
  base

let rebuild_parents children_map =
  let parents = Hashtbl.create 16 in
  Hashtbl.iter
    (fun parent children ->
       List.iter (fun child -> Hashtbl.replace parents child parent) children)
    children_map;
  parents

let index_map children =
  let result = Hashtbl.create 16 in
  List.iteri (fun index child -> Hashtbl.replace result child index) children;
  result

(* Places [value] at [start], shifting values[start .. end-1] right to
   start+1 .. end. Returns the new list and position table. *)
let shift_right values positions start end_ value =
  let arr = Array.of_list values in
  for j = end_ downto start + 1 do
    let moved = arr.(j - 1) in
    arr.(j) <- moved;
    Hashtbl.replace positions moved j
  done;
  arr.(start) <- value;
  Hashtbl.replace positions value start;
  Array.to_list arr

let enqueue application operation =
  application.pending_ops := operation :: !(application.pending_ops)

let rec find_child_index_in children child index =
  match children with
  | [] -> None
  | head :: rest ->
    if head = child then Some index else find_child_index_in rest child (index + 1)

let find_child_index children child = find_child_index_in children child 0

let remove_at values removed_index =
  List.filteri (fun index _ -> index <> removed_index) values

let insert_at values inserted_index value =
  let rec loop front rest index =
    match rest with
    | [] -> List.rev (value :: front)
    | head :: tail ->
      if index = inserted_index then
        List.rev_append (value :: front) (head :: tail)
      else loop (head :: front) tail (index + 1)
  in
  if inserted_index = List.length values then values @ [ value ]
  else loop [] values 0

let move_at values from_index to_index =
  let value = List.nth values from_index in
  let without = remove_at values from_index in
  let rec loop front rest index =
    if index = to_index then List.rev_append (value :: front) rest
    else
      match rest with
      | [] -> List.rev_append (value :: front) []
      | head :: tail -> loop (head :: front) tail (index + 1)
  in
  loop [] without 0

let emit_child_diff application parent old_children desired_children =
  let desired_index = index_map desired_children in
  let surviving =
    List.filter
      (fun child ->
         if Hashtbl.mem desired_index child then true
         else begin
           enqueue application (remove_child_op parent child);
           false
         end)
      old_children
  in
  let rec loop index current positions =
    if index = List.length desired_children then ()
    else
      let child = List.nth desired_children index in
      match Hashtbl.find_opt positions child with
      | Some from_index ->
        if from_index = index then loop (index + 1) current positions
        else begin
          enqueue application (move_child_op parent child index);
          let next_current =
            shift_right current positions index from_index child
          in
          loop (index + 1) next_current positions
        end
      | None ->
        enqueue application (insert_child_op parent child index);
        let next_current =
          shift_right
            (current @ [ child ])
            positions index (List.length current) child
        in
        loop (index + 1) next_current positions
  in
  loop 0 surviving (index_map surviving)

let emit_property_diff application node old_values desired_values =
  Property_map.iter
    (fun property _value ->
       if not (Property_map.mem property desired_values) then
         enqueue application (remove_prop_op node property))
    old_values;
  Property_map.iter
    (fun property value ->
       if Property_map.find_opt property old_values <> Some value then
         enqueue application (set_prop_op node property value))
    desired_values

let emit_extension_property_diff application node old_values desired_values =
  String_map.iter
    (fun property _value ->
       if not (String_map.mem property desired_values) then
         enqueue application (remove_extension_prop_op node property))
    old_values;
  String_map.iter
    (fun property value ->
       if String_map.find_opt property old_values <> Some value then
         enqueue application (set_extension_prop_op node property value))
    desired_values

let rec emit_dropped_subtree application saved removed_set node =
  let children =
    match Hashtbl.find_opt saved.checkpoint_children node with
    | Some current -> current
    | None -> []
  in
  List.iter
    (fun child ->
       if Hashtbl.mem removed_set child then begin
         enqueue application (remove_child_op node child);
         emit_dropped_subtree application saved removed_set child
       end)
    children;
  enqueue application (drop_node_op node)

let reconcile_subtree application saved parent old_root candidate_root =
  let parent = canonical_node application parent in
  let old_root = canonical_node application old_root in
  let current_children = application.runtime_children in
  let old_nodes = collect_subtree_nodes saved.checkpoint_children old_root in
  let candidate_nodes = collect_subtree_nodes current_children candidate_root in
  let mapping = Hashtbl.create 16 in
  ignore
    (collect_node_mapping application saved old_root candidate_root mapping);
  let desired_root = map_node mapping candidate_root in
  let desired_node_set = Hashtbl.create 16 in
  List.iter
    (fun candidate ->
       Hashtbl.replace desired_node_set (map_node mapping candidate) true)
    candidate_nodes;
  let removed_nodes =
    List.filter
      (fun node -> not (Hashtbl.mem desired_node_set node))
      old_nodes
  in
  let removed_set = Hashtbl.create 16 in
  List.iter (fun node -> Hashtbl.replace removed_set node true) removed_nodes;
  let base_standard = Hashtbl.copy saved.checkpoint_mounted_nodes in
  remove_node_keys base_standard old_nodes;
  let base_extensions = Hashtbl.copy saved.checkpoint_extension_nodes in
  remove_node_keys base_extensions old_nodes;
  let base_properties = Hashtbl.copy saved.checkpoint_properties in
  remove_node_keys base_properties old_nodes;
  let base_extension_properties =
    Hashtbl.copy saved.checkpoint_extension_properties
  in
  remove_node_keys base_extension_properties old_nodes;
  let base_reload_keys = Hashtbl.copy saved.checkpoint_reload_keys in
  remove_node_keys base_reload_keys old_nodes;
  let base_children = Hashtbl.copy saved.checkpoint_children in
  remove_node_keys base_children old_nodes;
  let desired_standard =
    remap_node_values application.mounted_nodes candidate_nodes mapping
      base_standard
  in
  let desired_extensions =
    remap_node_values application.runtime_extension_nodes candidate_nodes
      mapping base_extensions
  in
  let desired_properties =
    remap_node_values application.runtime_properties candidate_nodes mapping
      base_properties
  in
  let desired_extension_properties =
    remap_node_values application.runtime_extension_properties candidate_nodes
      mapping base_extension_properties
  in
  let desired_reload_keys =
    remap_node_values application.runtime_reload_keys candidate_nodes mapping
      base_reload_keys
  in
  let desired_children =
    remap_children current_children candidate_nodes mapping base_children
  in
  Hashtbl.replace desired_children parent [ desired_root ];
  let base_handlers = Hashtbl.copy saved.checkpoint_event_handlers in
  remove_node_keys base_handlers old_nodes;
  let desired_handlers =
    remap_node_values application.event_handlers candidate_nodes mapping
      base_handlers
  in
  let base_segments = Hashtbl.copy saved.checkpoint_dynamic_segments in
  remove_node_keys base_segments old_nodes;
  let desired_segments =
    remap_node_values application.dynamic_segments candidate_nodes mapping
      base_segments
  in
  if Hashtbl.find_opt application.mounted_nodes candidate_root = Some Root then
    invalid_arg "runtime root cannot be nested";
  application.pending_ops := saved.checkpoint_pending_ops;
  List.iter
    (fun candidate ->
       if candidate = map_node mapping candidate then
         match Hashtbl.find_opt desired_standard candidate with
         | Some kind ->
           enqueue application (create_node_op candidate kind)
         | None ->
           (match Hashtbl.find_opt desired_extensions candidate with
           | Some identifier ->
             let extension_schema =
               match
                 Lui_extension.schema
                   application.runtime_extension_registry identifier
               with
               | Some current -> current
               | None -> invalid_arg "unknown extension schema"
             in
             let fingerprint =
               if
                 Lui_extension.is_tweak
                   application.runtime_extension_registry identifier
               then Lui_extension.tweak_fingerprint extension_schema
               else Lui_extension.fingerprint extension_schema
             in
             enqueue
               application
               (create_extension_op candidate identifier fingerprint)
           | None -> ()))
    candidate_nodes;
  List.iter
    (fun candidate ->
       let node = map_node mapping candidate in
       match Hashtbl.find_opt desired_properties node with
       | Some values ->
         let old_values =
           match Hashtbl.find_opt saved.checkpoint_properties node with
           | Some old -> old
           | None -> Property_map.empty
         in
         emit_property_diff application node old_values values
       | None ->
         (match Hashtbl.find_opt desired_extension_properties node with
         | Some values ->
           let old_values =
             match
               Hashtbl.find_opt saved.checkpoint_extension_properties node
             with
             | Some old -> old
             | None -> String_map.empty
           in
           emit_extension_property_diff application node old_values values
         | None -> ()))
    candidate_nodes;
  let all_parents =
    List.map (fun candidate -> map_node mapping candidate) candidate_nodes
    @ [ parent ]
  in
  List.iter
    (fun node ->
       let old_children =
         match Hashtbl.find_opt saved.checkpoint_children node with
         | Some children -> children
         | None -> []
       in
       let new_children =
         match Hashtbl.find_opt desired_children node with
         | Some children -> children
         | None -> []
       in
       emit_child_diff application node old_children new_children)
    all_parents;
  List.iter
    (fun node ->
       match Hashtbl.find_opt saved.checkpoint_parents node with
       | Some old_parent ->
         if not (Hashtbl.mem removed_set old_parent) then
           emit_dropped_subtree application saved removed_set node
       | None -> emit_dropped_subtree application saved removed_set node)
    removed_nodes;
  let replace target source =
    Hashtbl.reset target;
    Hashtbl.iter (fun key value -> Hashtbl.replace target key value) source
  in
  replace application.mounted_nodes desired_standard;
  replace application.runtime_extension_nodes desired_extensions;
  replace application.runtime_properties desired_properties;
  replace application.runtime_extension_properties
    desired_extension_properties;
  replace application.runtime_children desired_children;
  let new_parents = rebuild_parents desired_children in
  replace application.runtime_parents new_parents;
  replace application.event_handlers desired_handlers;
  replace application.dynamic_segments desired_segments;
  application.runtime_handler_count :=
    Hashtbl.fold
      (fun _node handlers total -> total + List.length handlers)
      desired_handlers 0;
  application.runtime_dynamic_segment_count :=
    Hashtbl.fold
      (fun _parent segments total -> total + List.length segments)
      desired_segments 0;
  replace application.runtime_reload_keys desired_reload_keys;
  application.runtime_extension_dirty :=
    Hashtbl.length desired_extensions > 0;
  Hashtbl.reset application.runtime_node_aliases;
  Hashtbl.iter
    (fun candidate node ->
       if candidate <> node then
         Hashtbl.replace application.runtime_node_aliases candidate node)
    mapping;
  desired_root

(* target is a descendant-or-self of root iff walking the parent chain
   from target reaches root. *)
let rec descendant application root target =
  if target = root then true
  else
    match Hashtbl.find_opt application.runtime_parents target with
    | Some parent -> descendant application root parent
    | None -> false

let require_standard_node_kind application node =
  match
    Hashtbl.find_opt application.mounted_nodes
      (canonical_node application node)
  with
  | Some kind -> kind
  | None -> invalid_arg "unknown node"

let extension_identifier application node =
  Hashtbl.find_opt application.runtime_extension_nodes
    (canonical_node application node)

let require_extension_schema application node =
  match extension_identifier application node with
  | Some identifier ->
    (match
       Lui_extension.schema application.runtime_extension_registry identifier
     with
    | Some extension_schema -> extension_schema
    | None -> invalid_arg "unknown extension schema")
  | None -> invalid_arg "unknown extension node"

let require_node application node =
  let node = canonical_node application node in
  if
    (not (Hashtbl.mem application.mounted_nodes node))
    && not (Hashtbl.mem application.runtime_extension_nodes node)
  then invalid_arg "unknown node"

let next_node application =
  incr application.next_node_id;
  !(application.next_node_id)

let create_node application kind =
  let node = next_node application in
  Hashtbl.replace application.mounted_nodes node kind;
  Hashtbl.replace application.runtime_properties node Property_map.empty;
  Hashtbl.replace application.runtime_children node [];
  enqueue application (create_node_op node kind);
  node

let create_extension_node application identifier =
  let extension_schema =
    match
      Lui_extension.schema application.runtime_extension_registry identifier
    with
    | Some current -> current
    | None -> invalid_arg "unknown extension identifier"
  in
  if
    not
      (Lui_extension.profile_supported extension_schema
         application.runtime_backend.backend_profile)
  then invalid_arg "extension is unsupported by backend profile";
  let node = next_node application in
  Hashtbl.replace application.runtime_extension_nodes node identifier;
  Hashtbl.replace application.runtime_extension_properties node
    String_map.empty;
  Hashtbl.replace application.runtime_children node [];
  application.runtime_extension_dirty := true;
  enqueue
    application
    (create_extension_op node identifier
       (Lui_extension.fingerprint extension_schema));
  node

let create_tweak_node application identifier =
  let registry = application.runtime_extension_registry in
  if not (Lui_extension.is_tweak registry identifier) then
    invalid_arg "unknown platform tweak";
  let extension_schema =
    match Lui_extension.schema registry identifier with
    | Some current -> current
    | None -> invalid_arg "unknown platform tweak"
  in
  if
    not
      (Lui_extension.profile_supported extension_schema
         application.runtime_backend.backend_profile)
  then invalid_arg "tweak is unsupported by backend profile";
  let node = next_node application in
  Hashtbl.replace application.runtime_extension_nodes node identifier;
  Hashtbl.replace application.runtime_extension_properties node
    String_map.empty;
  Hashtbl.replace application.runtime_children node [];
  application.runtime_extension_dirty := true;
  enqueue
    application
    (create_extension_op node identifier
       (Lui_extension.tweak_fingerprint extension_schema));
  node

let set_reload_key application node key =
  let node = canonical_node application node in
  require_node application node;
  Hashtbl.replace application.runtime_reload_keys node key

let children application node =
  match
    Hashtbl.find_opt application.runtime_children
      (canonical_node application node)
  with
  | Some children -> children
  | None -> invalid_arg "unknown parent"

let rec drop_subtree application node =
  let node = canonical_node application node in
  match Hashtbl.find_opt application.runtime_children node with
  | Some children ->
    List.iter
      (fun child ->
         remove_child application node child;
         drop_subtree application child)
      children;
    drop_node application node
  | None -> drop_node application node

and drop_node application node =
  let node = canonical_node application node in
  require_node application node;
  if Hashtbl.mem application.runtime_parents node then
    invalid_arg "cannot drop an attached node";
  if children application node <> [] then
    invalid_arg "cannot drop a node with children";
  (match Hashtbl.find_opt application.dynamic_segments node with
  | Some segments ->
    List.iter
      (fun segment -> segment.dynamic_segment_active := false)
      segments
  | None -> ());
  Hashtbl.remove application.mounted_nodes node;
  Hashtbl.remove application.runtime_extension_nodes node;
  Hashtbl.remove application.runtime_properties node;
  Hashtbl.remove application.runtime_extension_properties node;
  Hashtbl.remove application.runtime_children node;
  Hashtbl.remove application.runtime_parents node;
  Hashtbl.remove application.runtime_reload_keys node;
  application.runtime_extension_dirty := true;
  enqueue application (drop_node_op node)

and remove_child application parent child =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  let current = children application parent in
  (match find_child_index current child with
  | Some index ->
    Hashtbl.replace application.runtime_children parent
      (remove_at current index);
    Hashtbl.remove application.runtime_parents child;
    application.runtime_extension_dirty := true
  | None -> invalid_arg "child is not attached to parent");
  enqueue application (remove_child_op parent child)

let set_prop application node property value =
  let node = canonical_node application node in
  let kind = require_standard_node_kind application node in
  if not (property_supported kind property) then
    invalid_arg
      (Printf.sprintf "property is unsupported by node kind: kind=%s prop=%s"
         (Lui_wire_schema.node_kind_name kind)
         (Lui_wire_schema.property_name property));
  if not (property_value_supported_for_kind kind property value) then
    invalid_arg
      (Printf.sprintf "invalid property value: kind=%s prop=%s value=%s"
         (Lui_wire_schema.node_kind_name kind)
         (Lui_wire_schema.property_name property)
         (Lui_wire.encode_value value));
  let current =
    match Hashtbl.find_opt application.runtime_properties node with
    | Some values -> values
    | None -> Property_map.empty
  in
  if Property_map.find_opt property current <> Some value then begin
    Hashtbl.replace application.runtime_properties node
      (Property_map.add property value current);
    enqueue application (set_prop_op node property value)
  end

let remove_prop application node property =
  let node = canonical_node application node in
  let kind = require_standard_node_kind application node in
  if not (property_supported kind property) then
    invalid_arg "property is unsupported by node kind";
  let current =
    match Hashtbl.find_opt application.runtime_properties node with
    | Some values -> values
    | None -> Property_map.empty
  in
  Hashtbl.replace application.runtime_properties node
    (Property_map.remove property current);
  enqueue application (remove_prop_op node property)

let set_extension_prop application node property value =
  let node = canonical_node application node in
  let extension_schema = require_extension_schema application node in
  if
    not
      (Lui_extension.property_value_supported extension_schema property
         value)
  then invalid_arg "invalid extension property value";
  let current =
    match Hashtbl.find_opt application.runtime_extension_properties node with
    | Some values -> values
    | None -> String_map.empty
  in
  if String_map.find_opt property current <> Some value then begin
    Hashtbl.replace application.runtime_extension_properties node
      (String_map.add property value current);
    application.runtime_extension_dirty := true;
    enqueue application (set_extension_prop_op node property value)
  end

let remove_extension_prop application node property =
  let node = canonical_node application node in
  let extension_schema = require_extension_schema application node in
  if
    not (Lui_extension.property_supported extension_schema property)
  then invalid_arg "unknown extension property";
  let current =
    match Hashtbl.find_opt application.runtime_extension_properties node with
    | Some values -> values
    | None -> String_map.empty
  in
  Hashtbl.replace application.runtime_extension_properties node
    (String_map.remove property current);
  application.runtime_extension_dirty := true;
  enqueue application (remove_extension_prop_op node property)

let rec child_supported application parent child =
  let standard_nodes = application.mounted_nodes in
  let extension_nodes = application.runtime_extension_nodes in
  let registry = application.runtime_extension_registry in
  match Hashtbl.find_opt extension_nodes child with
  | Some child_identifier ->
    if Lui_extension.is_tweak registry child_identifier then
      let tweak_children = children application child in
      List.length tweak_children = 1
      && child_supported application parent (List.nth tweak_children 0)
    else
      (match Hashtbl.find_opt standard_nodes parent with
      | Some parent_kind ->
        Lui_extension.standard_container_supported parent_kind
      | None ->
        (match Hashtbl.find_opt extension_nodes parent with
        | Some parent_identifier ->
          (match Lui_extension.schema registry parent_identifier with
          | Some extension_schema ->
            if Lui_extension.is_tweak registry parent_identifier then
              children application parent = []
            else
              Lui_extension.identifier_allowed
                extension_schema.extension_child_identifiers child_identifier
          | None -> false)
        | None -> false))
  | None ->
    (match Hashtbl.find_opt standard_nodes child with
    | Some child_kind ->
      if child_kind = Root then false
      else
        (match Hashtbl.find_opt standard_nodes parent with
        | Some parent_kind ->
          can_contain_children parent_kind
          && child_kind_supported parent_kind child_kind
        | None ->
          (match Hashtbl.find_opt extension_nodes parent with
          | Some parent_identifier ->
            (match Lui_extension.schema registry parent_identifier with
            | Some extension_schema ->
              if Lui_extension.is_tweak registry parent_identifier then
                children application parent = []
              else extension_schema.extension_standard_children
            | None -> false)
          | None -> false))
    | None -> false)

let insert_child application parent child index =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  let current = children application parent in
  (match
     ( Hashtbl.find_opt application.mounted_nodes parent,
       Hashtbl.find_opt application.mounted_nodes child )
   with
  | Some parent_kind, Some child_kind ->
    if not (can_contain_children parent_kind) then
      invalid_arg "parent cannot contain children";
    if not (child_kind_supported parent_kind child_kind) then
      invalid_arg
        (if parent_kind = Table then "table can contain only table-row"
         else if parent_kind = TableRow then
           "table-row can contain only table-cell"
         else if parent_kind = Tree then "tree accepts only row containers"
         else if child_kind = Root then "runtime root cannot be nested"
         else
           Printf.sprintf "unsupported child kind: parent=%s child=%s"
             (Lui_wire_schema.node_kind_name parent_kind)
             (Lui_wire_schema.node_kind_name child_kind))
  | _ ->
    if not (child_supported application parent child) then
      invalid_arg "unsupported child kind");
  if Hashtbl.mem application.runtime_parents child then
    invalid_arg "child is already attached";
  if index < 0 || index > List.length current then
    invalid_arg "child index is out of bounds";
  if descendant application child parent then
    invalid_arg "child insertion would create a cycle";
  Hashtbl.replace application.runtime_children parent
    (insert_at current index child);
  Hashtbl.replace application.runtime_parents child parent;
  application.runtime_extension_dirty := true;
  enqueue application (insert_child_op parent child index)

let move_child application parent child index =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  let current = children application parent in
  (match find_child_index current child with
  | Some current_index ->
    if index < 0 || index >= List.length current then
      invalid_arg "child index is out of bounds";
    Hashtbl.replace application.runtime_children parent
      (move_at current current_index index);
    application.runtime_extension_dirty := true
  | None -> invalid_arg "child is not attached to parent");
  enqueue application (move_child_op parent child index)

let bind_prop scope application node property source =
  Signal.own scope
    (Signal.observe source
       (fun value -> set_prop application node property value))

let bind_extension_prop scope application node property source =
  Signal.own scope
    (Signal.observe source
       (fun value -> set_extension_prop application node property value))

let remove_handler application node handler_id =
  let node = canonical_node application node in
  match Hashtbl.find_opt application.event_handlers node with
  | Some handlers ->
    let remaining =
      List.filter
        (fun handler -> handler_id <> handler.handler_id)
        handlers
    in
    application.runtime_handler_count :=
      !(application.runtime_handler_count)
      - (List.length handlers - List.length remaining);
    if remaining = [] then Hashtbl.remove application.event_handlers node
    else Hashtbl.replace application.event_handlers node remaining
  | None -> ()

let on_event scope application node callback =
  let node = canonical_node application node in
  require_node application node;
  let handler_id =
    incr application.next_handler_id;
    !(application.next_handler_id)
  in
  let handler = { handler_id; handler_callback = callback } in
  let handlers =
    match Hashtbl.find_opt application.event_handlers node with
    | Some current -> current
    | None -> []
  in
  Hashtbl.replace application.event_handlers node (handlers @ [ handler ]);
  incr application.runtime_handler_count;
  Signal.on_dispose scope
    (fun () -> remove_handler application node handler_id)

let dispatch application event =
  let node = canonical_node application (event_node event) in
  (match event with
  | ExtensionEvent (_event_node, identifier, name, values) ->
    let extension_schema = require_extension_schema application node in
    if identifier <> extension_schema.extension_identifier then
      invalid_arg "extension event identifier mismatch";
    if
      not
        (Lui_extension.event_payload_supported extension_schema name
           values)
    then invalid_arg "invalid extension event payload"
  | _ ->
    let kind = require_standard_node_kind application node in
    let properties =
      match Hashtbl.find_opt application.runtime_properties node with
      | Some current -> current
      | None -> Property_map.empty
    in
    if
      not
        (event_supported_for_properties kind properties event)
    then invalid_arg "event is unsupported by node kind");
  (match Hashtbl.find_opt application.event_handlers node with
  | Some handlers ->
    List.iter
      (fun handler ->
         Signal.enqueue_effect application.runtime_scheduler (fun () ->
             handler.handler_callback event))
      handlers;
    true
  | None -> true)

let validate_extension_nodes application =
  let properties = application.runtime_extension_properties in
  Hashtbl.iter
    (fun node _identifier ->
       let extension_schema = require_extension_schema application node in
       let values =
         match Hashtbl.find_opt properties node with
         | Some current -> current
         | None -> String_map.empty
       in
       if
         not
           (Lui_extension.properties_supported extension_schema values)
       then invalid_arg "extension properties are incomplete";
       if
         Lui_extension.is_tweak application.runtime_extension_registry
           extension_schema.extension_identifier
         && List.length (children application node) <> 1
       then invalid_arg "platform tweak requires exactly one child")
    application.runtime_extension_nodes

let handler_count application = !(application.runtime_handler_count)

let dynamic_segment_count application =
  !(application.runtime_dynamic_segment_count)

let mounted_count application =
  Hashtbl.length application.mounted_nodes
  + Hashtbl.length application.runtime_extension_nodes

let record_diagnostics application status operation_count
    pending_operation_count =
  let signal_diagnostics =
    Signal.last_stabilization application.runtime_scheduler
  in
  application.runtime_diagnostics :=
    {
      flush_status = status;
      flush_generation = !(application.runtime_generation);
      flush_operation_count = operation_count;
      flush_pending_operation_count = pending_operation_count;
      flush_mounted_node_count = mounted_count application;
      flush_handler_count = !(application.runtime_handler_count);
      flush_dynamic_segment_count =
        !(application.runtime_dynamic_segment_count);
      flush_signal_generation = signal_diagnostics.stabilization_generation;
      flush_signal_round_count = signal_diagnostics.stabilization_rounds;
      flush_signal_effect_count = signal_diagnostics.stabilization_effects;
      flush_signal_dirty_task_count =
        signal_diagnostics.stabilization_dirty_tasks;
    };
  true

let apply_pending_batch application batch operation_count next_generation =
  try
    if not (application.runtime_backend.apply_batch batch) then
      invalid_arg "backend rejected patch batch";
    application.pending_ops := [];
    application.runtime_generation := next_generation;
    record_diagnostics application Applied operation_count 0
  with Invalid_argument message ->
    ignore
      (record_diagnostics application Rejected operation_count
         (List.length !(application.pending_ops)));
    invalid_arg message

let flush application =
  Signal.stabilize application.runtime_scheduler;
  if !(application.runtime_extension_dirty) then begin
    application.runtime_extension_dirty := false;
    validate_extension_nodes application
  end;
  let operations = List.rev !(application.pending_ops) in
  if operations = [] then record_diagnostics application NoBatch 0 0
  else begin
    let next_generation = !(application.runtime_generation) + 1 in
    let batch = { generation = next_generation; ops = operations } in
    apply_pending_batch application batch (List.length operations)
      next_generation
  end

let diagnostics application = !(application.runtime_diagnostics)

let generation application = !(application.runtime_generation)

let child_count application node = List.length (children application node)

let find_dynamic_segment_index segments segment_id =
  let rec loop segments index =
    match segments with
    | [] -> None
    | head :: rest ->
      if segment_id = head.dynamic_segment_id then Some index
      else loop rest (index + 1)
  in
  loop segments 0

let register_dynamic_segment application parent =
  let parent = canonical_node application parent in
  require_node application parent;
  let segment =
    {
      dynamic_segment_id =
        (incr application.next_dynamic_segment_id;
         !(application.next_dynamic_segment_id));
      dynamic_segment_parent = parent;
      dynamic_segment_base = ref (child_count application parent);
      dynamic_segment_size = ref 0;
      dynamic_segment_active = ref true;
    }
  in
  let current =
    match Hashtbl.find_opt application.dynamic_segments parent with
    | Some segments -> segments
    | None -> []
  in
  Hashtbl.replace application.dynamic_segments parent (current @ [ segment ]);
  incr application.runtime_dynamic_segment_count;
  segment

let dynamic_segment_index segment local_index =
  if not !(segment.dynamic_segment_active) then
    invalid_arg "dynamic segment is inactive";
  let size = !(segment.dynamic_segment_size) in
  if local_index < 0 || local_index >= size then
    invalid_arg "dynamic segment index is out of bounds";
  !(segment.dynamic_segment_base) + local_index

let dynamic_segment_insert_index segment local_index =
  if not !(segment.dynamic_segment_active) then
    invalid_arg "dynamic segment is inactive";
  let size = !(segment.dynamic_segment_size) in
  if local_index < 0 || local_index > size then
    invalid_arg "dynamic segment insert index is out of bounds";
  !(segment.dynamic_segment_base) + local_index

let resize_dynamic_segment application segment delta =
  if not !(segment.dynamic_segment_active) then
    invalid_arg "dynamic segment is inactive";
  let parent =
    canonical_node application segment.dynamic_segment_parent
  in
  let segments =
    match Hashtbl.find_opt application.dynamic_segments parent with
    | Some registered -> registered
    | None -> invalid_arg "dynamic segment is not registered"
  in
  let segment_index =
    match find_dynamic_segment_index segments segment.dynamic_segment_id with
    | Some index -> index
    | None -> invalid_arg "dynamic segment is not registered"
  in
  let next_size = !(segment.dynamic_segment_size) + delta in
  if next_size < 0 then
    invalid_arg "dynamic segment size cannot be negative";
  segment.dynamic_segment_size := next_size;
  List.iteri
    (fun index current ->
       if index > segment_index then
         current.dynamic_segment_base :=
           !(current.dynamic_segment_base) + delta)
    segments

let unregister_dynamic_segment application segment =
  if !(segment.dynamic_segment_active) then begin
    if !(segment.dynamic_segment_size) <> 0 then
      invalid_arg "cannot unregister a non-empty dynamic segment";
    let parent =
      canonical_node application segment.dynamic_segment_parent
    in
    (match Hashtbl.find_opt application.dynamic_segments parent with
    | Some segments ->
      let remaining =
        List.filter
          (fun current ->
             current.dynamic_segment_id <> segment.dynamic_segment_id)
          segments
      in
      if remaining = [] then
        Hashtbl.remove application.dynamic_segments parent
      else Hashtbl.replace application.dynamic_segments parent remaining;
      if List.length remaining < List.length segments then
        decr application.runtime_dynamic_segment_count
    | None -> ());
    segment.dynamic_segment_active := false
  end
