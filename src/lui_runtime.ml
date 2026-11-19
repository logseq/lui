(* Retained runtime: mounts a node tree, queues patch ops, and flushes
   patch batches to a backend after signal stabilization.

   The runtime is intentionally single-threaded. Every table below is a
   plain mutable Hashtbl with no domain lock: one OCaml domain (the host
   thread that runs [flush] and event dispatch) may touch an application.
   Other domains must not call into it, including from parallel signal
   schedulers. *)

open Lui_protocol

module Root_set = Set.Make (Int)

type event_handler = {
  handler_id : int;
  handler_callback : event -> unit;
}

type dynamic_segment = {
  dynamic_segment_id : int;
  dynamic_segment_parent : int;
  dynamic_segment_owner : dynamic_segment option;
  dynamic_segment_base : int ref;
  dynamic_segment_size : int ref;
  dynamic_segment_active : bool ref;
  dynamic_segment_exclusive : bool;
  dynamic_segment_on_property :
    (property -> wire_value option -> unit) option ref;
}

type flush_status =
  | NotFlushed
  | NoBatch
  | Applied
  | Rejected

(* Last value sent to the host or delivered to handlers for one control.
   [None] means the channel is still at the unset default ("" / false / 0.0),
   so a mount-time report of that default is an echo. A later edit that
   returns to the default is not: it differs from the last recorded value. *)
type echo_state = {
  echo_text : string option;
  echo_toggle : bool option;
  echo_value : float option;
}

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

type journal_table =
  | Mounted_nodes | Extension_nodes | Properties | Extension_properties
  | Children | Parents | Pending_creates | Elision_ghosts | Elision_root
  | Elision_members | Elision_edges | Echo | Event_handlers | Dynamic_segments
  | Reload_keys | Node_aliases | Alias_targets | Virtual_sources | Virtual_owners
  | Virtual_receipts | Virtual_state | Segment_base | Segment_size
  | Segment_active | Segment_on_property | Pending_operation
  | Property_value of property | Extension_value of string
  | Child_position | Handler_member | Segment_member
  | Echo_text | Echo_toggle | Echo_value

type rollback_entry = {
  rollback_position : int;
  rollback_undo : unit -> unit;
  rollback_node_before : (int * bool) option;
  mutable rollback_committed : bool;
  mutable rollback_anchor : int option;
}

type rollback_journal = {
  mutable journal_entries : rollback_entry list;
  journal_versions : (journal_table * int, int) Hashtbl.t;
  mutable journal_position : int;
  mutable journal_epoch : int;
  mutable journal_enabled : bool;
  mutable journal_replaying : bool;
}

type boundary_savepoint = { savepoint_epoch : int; savepoint_position : int }

type application = {
  runtime_journal : rollback_journal;
  runtime_scheduler : Signal.scheduler;
  runtime_backend : backend;
  runtime_virtual_rows : bool;
  runtime_virtual_capabilities : Lui_virtual.capability list;
  runtime_virtual_sources : (int, Lui_virtual.source) Hashtbl.t;
  runtime_virtual_owners : (int, Lui_virtual.owner) Hashtbl.t;
  runtime_virtual_receipts : (int, Lui_virtual.owner) Hashtbl.t;
  runtime_extension_registry : Lui_extension.extension_registry;
  next_node_id : int ref;
  next_virtual_generation : int ref;
  mounted_nodes : (int, node_kind) Hashtbl.t;
  runtime_extension_nodes : (int, string) Hashtbl.t;
  (* identifiers whose schema fingerprint already went out on the wire —
     hosts resolve an empty fingerprint against their registered spec,
     so subsequent creates send "" instead of ~1.4KB each *)
  runtime_fingerprint_sent : (string, unit) Hashtbl.t;
  runtime_properties : (int, wire_value Property_map.t) Hashtbl.t;
  runtime_extension_properties : (int, wire_value String_map.t) Hashtbl.t;
  runtime_children : (int, int Lui_sequence.t) Hashtbl.t;
  runtime_parents : (int, int) Hashtbl.t;
  pending_ops : patch_op list ref; (* stored in reverse order *)
  (* Nodes with a CreateNode/CreateExtension still in [pending_ops]. Kept in
     sync with that list so same-batch drop elision does not scan it. *)
  pending_creates : (int, unit) Hashtbl.t;
  (* Same-batch drop elision: ids marked while created and dropped inside
     the open batch. [elision_root] maps an elided id to the group root it
     was marked under, [elision_members] maps each group root to its ids
     (leaves-first), [elision_edges] records a group's internal
     child -> parent links for fallback edge removal. Batch-scoped: reset
     whenever pending ops materialize. *)
  elision_ghosts : (int, unit) Hashtbl.t;
  elision_root : (int, int) Hashtbl.t;
  elision_members : (int, int list) Hashtbl.t;
  elision_edges : (int, int) Hashtbl.t;
  (* Per-node echo baselines for text / toggle / slider channels. *)
  runtime_echo : (int, echo_state) Hashtbl.t;
  runtime_generation : int ref;
  runtime_resync_required : bool ref;
  runtime_host_roots : Root_set.t ref;
  runtime_diagnostics : flush_diagnostics ref;
  next_handler_id : int ref;
  event_handlers : (int, event_handler list) Hashtbl.t;
  next_dynamic_segment_id : int ref;
  dynamic_segments : (int, dynamic_segment list) Hashtbl.t;
  runtime_reload_keys : (int, string) Hashtbl.t;
  runtime_node_aliases : (int, int) Hashtbl.t;
  runtime_alias_targets : (int, int list) Hashtbl.t;
  runtime_handler_count : int ref;
  runtime_dynamic_segment_count : int ref;
  runtime_extension_dirty : bool ref;
  (* a batch commit can synchronously emit back into the app (a DOM op
     fires focus/mount events whose listeners dispatch + flush). The
     inner flush must not batch the same still-queued ops again — the
     host's sequential-generation check throws and aborts the outer
     apply mid-op, desyncing the store. Defer: mark dirty and run one
     more pass after the outer commit unwinds. *)
  runtime_flushing : bool ref;
  runtime_flush_dirty : bool ref;
  runtime_clock : Lui_clock.t;
}

type runtime_checkpoint = {
  checkpoint_virtual_sources : (int, Lui_virtual.source) Hashtbl.t;
  checkpoint_virtual_owners : (int, Lui_virtual.owner) Hashtbl.t;
  checkpoint_virtual_receipts : (int, Lui_virtual.owner) Hashtbl.t;
  checkpoint_restore_virtual : (unit -> unit) list;
  checkpoint_nodes : int list option;
  checkpoint_generation : int;
  checkpoint_next_node_id : int;
  checkpoint_next_virtual_generation : int;
  checkpoint_mounted_nodes : (int, node_kind) Hashtbl.t;
  checkpoint_extension_nodes : (int, string) Hashtbl.t;
  checkpoint_properties : (int, wire_value Property_map.t) Hashtbl.t;
  checkpoint_extension_properties : (int, wire_value String_map.t) Hashtbl.t;
  checkpoint_children : (int, int Lui_sequence.t) Hashtbl.t;
  checkpoint_parents : (int, int) Hashtbl.t;
  checkpoint_pending_ops : patch_op list;
  checkpoint_pending_creates : (int, unit) Hashtbl.t;
  checkpoint_elision_ghosts : (int, unit) Hashtbl.t;
  checkpoint_elision_root : (int, int) Hashtbl.t;
  checkpoint_elision_members : (int, int list) Hashtbl.t;
  checkpoint_elision_edges : (int, int) Hashtbl.t;
  checkpoint_echo : (int, echo_state) Hashtbl.t;
  checkpoint_next_handler_id : int;
  checkpoint_event_handlers : (int, event_handler list) Hashtbl.t;
  checkpoint_next_dynamic_segment_id : int;
  checkpoint_dynamic_segments : (int, dynamic_segment list) Hashtbl.t;
  checkpoint_segment_values :
    (dynamic_segment * int * int * bool
     * (property -> wire_value option -> unit) option) list;
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
  render_children : (int, int Lui_sequence.t) Hashtbl.t;
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

let create_with_extensions ?virtual_rows ?(virtual_capabilities = []) scheduler backend registry =
  List.iter (fun capability ->
    if not (Lui_virtual.supports backend.backend_profile.profile_host capability) then
      invalid_arg "shared virtual viewport unsupported by this host") virtual_capabilities;
  let virtual_rows = match virtual_rows with
    | Some supported -> supported
    | None -> (match backend.backend_profile.profile_host with
      | WebHost | SwiftUIHost | KotlinHost -> true
      | GenericHost -> false) in
  Lui_extension.freeze registry;
  if virtual_capabilities <> [] && not virtual_rows then
    invalid_arg "shared virtual viewport requires virtual rows";
  {
    runtime_journal = {
      journal_entries = []; journal_versions = Hashtbl.create 16;
      journal_position = 0; journal_epoch = 0;
      journal_enabled = false; journal_replaying = false;
    };
    runtime_scheduler = scheduler;
    runtime_backend = backend;
    runtime_virtual_rows = virtual_rows;
    runtime_virtual_capabilities = virtual_capabilities;
    runtime_virtual_sources = Hashtbl.create 8;
    runtime_virtual_owners = Hashtbl.create 8;
    runtime_virtual_receipts = Hashtbl.create 8;
    runtime_extension_registry = registry;
    next_node_id = ref 0;
    next_virtual_generation = ref 0;
    mounted_nodes = Hashtbl.create 16;
    runtime_extension_nodes = Hashtbl.create 16;
    runtime_fingerprint_sent = Hashtbl.create 16;
    runtime_properties = Hashtbl.create 16;
    runtime_extension_properties = Hashtbl.create 16;
    runtime_children = Hashtbl.create 16;
    runtime_parents = Hashtbl.create 16;
    pending_ops = ref [];
    pending_creates = Hashtbl.create 16;
    elision_ghosts = Hashtbl.create 16;
    elision_root = Hashtbl.create 16;
    elision_members = Hashtbl.create 16;
    elision_edges = Hashtbl.create 16;
    runtime_echo = Hashtbl.create 16;
    runtime_generation = ref 0;
    runtime_resync_required = ref false;
    runtime_host_roots = ref Root_set.empty;
    runtime_diagnostics = ref (empty_diagnostics ());
    next_handler_id = ref 0;
    event_handlers = Hashtbl.create 16;
    next_dynamic_segment_id = ref 0;
    dynamic_segments = Hashtbl.create 16;
    runtime_reload_keys = Hashtbl.create 16;
    runtime_node_aliases = Hashtbl.create 16;
    runtime_alias_targets = Hashtbl.create 16;
    runtime_handler_count = ref 0;
    runtime_dynamic_segment_count = ref 0;
    runtime_extension_dirty = ref false;
    runtime_flushing = ref false;
    runtime_flush_dirty = ref false;
    runtime_clock = Lui_clock.create ();
  }

let clock application = application.runtime_clock

let create ?virtual_rows ?virtual_capabilities scheduler backend =
  create_with_extensions ?virtual_rows ?virtual_capabilities scheduler backend (Lui_extension.registry ())

let journal_recording application =
  let journal = application.runtime_journal in
  journal.journal_enabled && not journal.journal_replaying

let journal_record ?node_before application location undo =
  if journal_recording application then begin
    let journal = application.runtime_journal in
    let previous = Option.value ~default:0 (Hashtbl.find_opt journal.journal_versions location) in
    journal.journal_position <- journal.journal_position + 1;
    let position = journal.journal_position in
    Hashtbl.replace journal.journal_versions location position;
    let undo () =
      (* A committed later write owns this cell even across older savepoints. *)
      if Hashtbl.find_opt journal.journal_versions location = Some position then begin
        undo ();
        if previous = 0 then Hashtbl.remove journal.journal_versions location
        else Hashtbl.replace journal.journal_versions location previous
      end in
    journal.journal_entries <- {
      rollback_position = position; rollback_undo = undo;
      rollback_committed = false;
      rollback_node_before = node_before; rollback_anchor = None;
    } :: journal.journal_entries
  end

let journal_replace application slot table key value =
  if journal_recording application then begin
    let previous = Hashtbl.find_opt table key in
    let node_before = match slot with
      | Mounted_nodes | Extension_nodes ->
          Some (key, Hashtbl.mem application.mounted_nodes key ||
                     Hashtbl.mem application.runtime_extension_nodes key)
      | _ -> None in
    journal_record ?node_before application (slot, key) (fun () ->
      match previous with
      | None -> Hashtbl.remove table key
      | Some value -> Hashtbl.replace table key value)
  end;
  Hashtbl.replace table key value

let journal_remove application slot table key =
  if journal_recording application then begin
    let previous = Hashtbl.find_opt table key in
    let node_before = match slot with
      | Mounted_nodes | Extension_nodes ->
          Some (key, Hashtbl.mem application.mounted_nodes key ||
                     Hashtbl.mem application.runtime_extension_nodes key)
      | _ -> None in
    journal_record ?node_before application (slot, key) (fun () ->
      match previous with
      | None -> Hashtbl.remove table key
      | Some value -> Hashtbl.replace table key value)
  end;
  Hashtbl.remove table key

let journal_clear application slot table =
  if journal_recording application then begin
    let keys = Hashtbl.create (Hashtbl.length table) in
    Hashtbl.iter (fun key _ -> Hashtbl.replace keys key ()) table;
    Hashtbl.iter (fun (candidate, key) _ ->
      if candidate = slot then Hashtbl.replace keys key ())
      application.runtime_journal.journal_versions;
    Hashtbl.iter (fun key () -> journal_remove application slot table key) keys
  end;
  Hashtbl.clear table

let journal_ref application slot key reference value =
  if journal_recording application then begin
    let previous = !reference in
    journal_record application (slot, key) (fun () -> reference := previous)
  end;
  reference := value

let echo_state application node =
  match Hashtbl.find_opt application.runtime_echo node with
  | Some state -> state
  | None -> { echo_text = None; echo_toggle = None; echo_value = None }

let put_echo application node state =
  let write state =
    match state with
    | { echo_text = None; echo_toggle = None; echo_value = None } ->
        Hashtbl.remove application.runtime_echo node
    | _ -> Hashtbl.replace application.runtime_echo node state in
  let previous = echo_state application node in
  let record slot before after restore =
    if before <> after then
      journal_record application (slot, node) (fun () ->
        write (restore before (echo_state application node))) in
  record Echo_text previous.echo_text state.echo_text
    (fun value current -> { current with echo_text = value });
  record Echo_toggle previous.echo_toggle state.echo_toggle
    (fun value current -> { current with echo_toggle = value });
  record Echo_value previous.echo_value state.echo_value
    (fun value current -> { current with echo_value = value });
  write state

let journal_capture application slot key capture =
  if journal_recording application then
    journal_record application (slot, key) (capture ())

let journal_restore_pending application operations =
  let previous = !(application.pending_ops) in
  journal_record application (Pending_operation, 0) (fun () ->
    application.pending_ops := previous);
  application.pending_ops := operations

let restore_identity application identity previous =
  identity := if journal_recording application then max !identity previous else previous

module Journal_map (Values : Map.S) = struct
  let replace application table_slot value_slot table node (desired : wire_value Values.t) =
    if not (Hashtbl.mem table node) then
      journal_replace application table_slot table node Values.empty;
    if journal_recording application then begin
      let previous = Hashtbl.find table node in
      ignore (Values.merge (fun key before after ->
        if before <> after then
          journal_record application (value_slot key, node) (fun () ->
            match Hashtbl.find_opt table node with
            | None -> ()
            | Some current ->
                let restored = match before with
                  | None -> Values.remove key current
                  | Some value -> Values.add key value current in
                Hashtbl.replace table node restored);
        None) previous desired)
    end;
    Hashtbl.replace table node desired

  let remove application table_slot value_slot table node =
    replace application table_slot value_slot table node Values.empty;
    journal_remove application table_slot table node
end

module Journal_properties = Journal_map (Property_map)
module Journal_extension_properties = Journal_map (String_map)

let journal_properties application =
  Journal_properties.replace application Properties (fun property -> Property_value property)
    application.runtime_properties

let journal_extension_properties application =
  Journal_extension_properties.replace application Extension_properties
    (fun property -> Extension_value property) application.runtime_extension_properties

let insert_list index value values =
  let rec insert index = function
    | rest when index = 0 -> value :: rest
    | [] -> [value]
    | first :: rest -> first :: insert (index - 1) rest in
  insert index values

let journal_member ?(new_member = false) application slot table parent identify identity =
  if journal_recording application then begin
    let previous = Option.value ~default:[] (Hashtbl.find_opt table parent) in
    let rec find index = function
      | [] -> None
      | value :: _ when identify value = identity -> Some (index, value)
      | _ :: rest -> find (index + 1) rest in
    let previous = if new_member then None else find 0 previous in
    journal_record application (slot, identity) (fun () ->
      if Hashtbl.mem application.mounted_nodes parent
         || Hashtbl.mem application.runtime_extension_nodes parent then begin
        let current = Option.value ~default:[] (Hashtbl.find_opt table parent) in
        let current = List.filter (fun value -> identify value <> identity) current in
        let restored = match previous with
          | None -> current
          | Some (index, value) -> insert_list index value current in
        if restored = [] then Hashtbl.remove table parent
        else Hashtbl.replace table parent restored
      end)
  end

let journal_list application slot table parent identify desired =
  if journal_recording application then begin
    let previous = Option.value ~default:[] (Hashtbl.find_opt table parent) in
    let positions = Hashtbl.create (List.length previous) in
    List.iteri (fun index value -> Hashtbl.replace positions (identify value) index) previous;
    let desired_positions = Hashtbl.create (List.length desired) in
    List.iteri (fun index value ->
      let identity = identify value in
      Hashtbl.replace desired_positions identity index;
      if Hashtbl.find_opt positions identity <> Some index then
        journal_member application slot table parent identify identity) desired;
    List.iter (fun value ->
      let identity = identify value in
      if not (Hashtbl.mem desired_positions identity) then
        journal_member application slot table parent identify identity) previous
  end;
  if desired = [] then Hashtbl.remove table parent
  else Hashtbl.replace table parent desired

let journal_child ?parent:target application child =
  if journal_recording application then begin
    let previous = Option.bind (Hashtbl.find_opt application.runtime_parents child) (fun parent ->
      Option.bind (Hashtbl.find_opt application.runtime_children parent) (fun children ->
        Option.map (fun index -> parent, index) (Lui_sequence.index children child))) in
    journal_record application (Child_position, child) (fun () ->
      let parents = List.sort_uniq Int.compare
        (Option.to_list target
         @ Option.to_list (Hashtbl.find_opt application.runtime_parents child)
         @ Option.to_list (Option.map fst previous)) in
      List.iter (fun parent ->
        Option.iter (fun children ->
          Option.iter (fun index ->
            Hashtbl.replace application.runtime_children parent (Lui_sequence.remove children index))
            (Lui_sequence.index children child))
          (Hashtbl.find_opt application.runtime_children parent))
        parents;
      Hashtbl.remove application.runtime_parents child;
      Option.iter (fun (parent, index) ->
        match Hashtbl.find_opt application.runtime_children parent with
        | Some children when Hashtbl.mem application.mounted_nodes child
                             || Hashtbl.mem application.runtime_extension_nodes child ->
            Hashtbl.replace application.runtime_children parent
              (Lui_sequence.insert children (min index (Lui_sequence.length children)) child);
            Hashtbl.replace application.runtime_parents child parent
        | _ -> ()) previous)
  end

let replace_journal_table ?nodes table source remove replace =
  let keys = match nodes with
    | Some nodes -> nodes
    | None -> List.of_seq (Hashtbl.to_seq_keys table) in
  List.iter remove keys;
  Hashtbl.iter replace source

let replace_property_table ?nodes application source =
  replace_journal_table ?nodes application.runtime_properties source
    (Journal_properties.remove application Properties (fun key -> Property_value key)
      application.runtime_properties)
    (journal_properties application)

let replace_extension_property_table ?nodes application source =
  replace_journal_table ?nodes application.runtime_extension_properties source
    (Journal_extension_properties.remove application Extension_properties
      (fun key -> Extension_value key) application.runtime_extension_properties)
    (journal_extension_properties application)

let replace_list_table ?nodes application slot table source identify =
  replace_journal_table ?nodes table source
    (fun parent -> journal_list application slot table parent identify [])
    (fun parent values -> journal_list application slot table parent identify values)

let replace_children_table ?nodes application source =
  let keys = match nodes with
    | Some nodes -> nodes
    | None -> List.of_seq (Hashtbl.to_seq_keys application.runtime_children) in
  if journal_recording application then begin
    let targets = Hashtbl.create 16 in
    Hashtbl.iter (fun parent children -> Lui_sequence.iter
      (fun child -> Hashtbl.replace targets child parent) children) source;
    let children = Hashtbl.create 16 in
    List.iter (fun parent -> Option.iter
      (Lui_sequence.iter (fun child -> Hashtbl.replace children child ()))
      (Hashtbl.find_opt application.runtime_children parent)) keys;
    Hashtbl.iter (fun child _ -> Hashtbl.replace children child ()) targets;
    Hashtbl.iter (fun child () ->
      journal_child ?parent:(Hashtbl.find_opt targets child) application child) children
  end;
  List.iter (Hashtbl.remove application.runtime_children) keys;
  Hashtbl.iter (Hashtbl.replace application.runtime_children) source

let replace_echo_table ?nodes application source =
  replace_journal_table ?nodes application.runtime_echo source
    (fun node -> put_echo application node
      { echo_text = None; echo_toggle = None; echo_value = None })
    (put_echo application)

let boundary_savepoint application =
  let journal = application.runtime_journal in
  journal.journal_enabled <- true;
  { savepoint_epoch = journal.journal_epoch; savepoint_position = journal.journal_position }

let boundary_savepoint_valid application saved =
  saved.savepoint_epoch = application.runtime_journal.journal_epoch

let commit_boundary_recovery ?anchor application saved =
  let rec commit = function
    | entry :: rest when entry.rollback_position > saved.savepoint_position ->
        entry.rollback_committed <- true;
        entry.rollback_anchor <- anchor;
        commit rest
    | _ -> () in
  commit application.runtime_journal.journal_entries

let rollback_boundary application saved =
  let journal = application.runtime_journal in
  if not (boundary_savepoint_valid application saved) then
    invalid_arg "cannot restore a stale boundary savepoint";
  let had_pending = !(application.pending_ops) <> [] in
  let discarded = Hashtbl.create 16 in
  let changed = ref true in
  while !changed do
    changed := false;
    let baseline = Hashtbl.create 16 in
    List.iter (fun entry ->
      if entry.rollback_position > saved.savepoint_position
         && (not entry.rollback_committed ||
             Option.fold ~none:false ~some:(Hashtbl.mem discarded) entry.rollback_anchor) then
        Option.iter (fun (node, existed) -> Hashtbl.replace baseline node existed)
          entry.rollback_node_before) journal.journal_entries;
    Hashtbl.iter (fun node existed ->
      if not existed && not (Hashtbl.mem discarded node) then begin
        Hashtbl.replace discarded node ();
        changed := true
      end) baseline
  done;
  let rec rollback kept = function
    | entry :: rest when entry.rollback_position > saved.savepoint_position ->
        if entry.rollback_committed &&
           not (Option.fold ~none:false ~some:(Hashtbl.mem discarded) entry.rollback_anchor)
        then rollback (entry :: kept) rest
        else begin
          entry.rollback_undo ();
          rollback kept rest
        end
    | rest -> List.rev_append kept rest in
  journal.journal_replaying <- true;
  (match rollback [] journal.journal_entries with
  | entries -> journal.journal_entries <- entries; journal.journal_replaying <- false
  | exception failure -> journal.journal_replaying <- false; raise failure);
  if had_pending || !(application.pending_ops) <> [] then begin
    application.pending_ops := [];
    Hashtbl.clear application.pending_creates;
    Hashtbl.clear application.elision_ghosts;
    Hashtbl.clear application.elision_root;
    Hashtbl.clear application.elision_members;
    Hashtbl.clear application.elision_edges;
    application.runtime_resync_required := true
  end;
  application.runtime_handler_count := Hashtbl.fold (fun _ handlers count ->
    count + List.length handlers) application.event_handlers 0;
  application.runtime_dynamic_segment_count := Hashtbl.fold (fun _ segments count ->
    count + List.length segments) application.dynamic_segments 0;
  Hashtbl.reset application.runtime_alias_targets;
  Hashtbl.iter (fun alias target ->
    let aliases = Option.value ~default:[]
      (Hashtbl.find_opt application.runtime_alias_targets target) in
    Hashtbl.replace application.runtime_alias_targets target (alias :: aliases))
    application.runtime_node_aliases;
  application.runtime_extension_dirty := true

let compact_boundary_journal application =
  let journal = application.runtime_journal in
  journal.journal_entries <- [];
  Hashtbl.reset journal.journal_versions;
  journal.journal_position <- 0;
  journal.journal_epoch <- journal.journal_epoch + 1;
  journal.journal_enabled <- false

let remove_alias application candidate =
  match Hashtbl.find_opt application.runtime_node_aliases candidate with
  | None -> ()
  | Some target ->
    journal_remove application Node_aliases application.runtime_node_aliases candidate;
    let aliases = match Hashtbl.find_opt application.runtime_alias_targets target with
      | Some aliases -> List.filter ((<>) candidate) aliases | None -> [] in
    if aliases = [] then journal_remove application Alias_targets application.runtime_alias_targets target
    else journal_replace application Alias_targets application.runtime_alias_targets target aliases

let set_alias application candidate target =
  remove_alias application candidate;
  journal_replace application Node_aliases application.runtime_node_aliases candidate target;
  let aliases = match Hashtbl.find_opt application.runtime_alias_targets target with
    | Some aliases -> aliases | None -> [] in
  journal_replace application Alias_targets application.runtime_alias_targets target (candidate :: aliases)

let remove_target_aliases application target =
  match Hashtbl.find_opt application.runtime_alias_targets target with
  | None -> ()
  | Some aliases ->
    List.iter (journal_remove application Node_aliases application.runtime_node_aliases) aliases;
    journal_remove application Alias_targets application.runtime_alias_targets target

(* Entry-sized snapshot. [Hashtbl.copy] duplicates the bucket array, which
   [Hashtbl.clear] does not shrink, so a checkpoint after a large flush
   would allocate with the historical node count. *)
let snapshot_hashtbl table =
  let saved = Hashtbl.create (Hashtbl.length table) in
  Hashtbl.iter (fun key value -> Hashtbl.replace saved key value) table;
  saved

let checkpoint ?nodes application =
  let copy table = match nodes with
    | None -> snapshot_hashtbl table
    | Some nodes ->
      let saved = Hashtbl.create (List.length nodes) in
      List.iter (fun node -> match Hashtbl.find_opt table node with
        | Some value -> Hashtbl.replace saved node value | None -> ()) nodes;
      saved in
  let segments = copy application.dynamic_segments in
  {
    checkpoint_virtual_sources = snapshot_hashtbl application.runtime_virtual_sources;
    checkpoint_virtual_owners = snapshot_hashtbl application.runtime_virtual_owners;
    checkpoint_virtual_receipts = snapshot_hashtbl application.runtime_virtual_receipts;
    checkpoint_restore_virtual = Hashtbl.fold (fun _ owner saved ->
      Lui_virtual.Internal.checkpoint owner :: saved) application.runtime_virtual_owners [];
    checkpoint_nodes = nodes;
    checkpoint_generation = !(application.runtime_generation);
    checkpoint_next_node_id = !(application.next_node_id);
    checkpoint_next_virtual_generation = !(application.next_virtual_generation);
    checkpoint_mounted_nodes = copy application.mounted_nodes;
    checkpoint_extension_nodes = copy application.runtime_extension_nodes;
    checkpoint_properties =
      copy application.runtime_properties;
    checkpoint_extension_properties =
      copy application.runtime_extension_properties;
    checkpoint_children = copy application.runtime_children;
    checkpoint_parents = copy application.runtime_parents;
    checkpoint_pending_ops = !(application.pending_ops);
    (* Pending creates are a batch-global set: restore clears the live
       table and replays this snapshot, so a subtree checkpoint must
       still keep creates that belong to other nodes in the same batch.
       The set is empty after a flush, so a local update does not copy
       the mounted tree. Echo is per-node state and follows [nodes]. *)
    checkpoint_pending_creates = snapshot_hashtbl application.pending_creates;
    (* Elision marks are batch-global too: a scoped checkpoint still keeps
       drops whose group belongs to other nodes in the same batch. *)
    checkpoint_elision_ghosts = snapshot_hashtbl application.elision_ghosts;
    checkpoint_elision_root = snapshot_hashtbl application.elision_root;
    checkpoint_elision_members = snapshot_hashtbl application.elision_members;
    checkpoint_elision_edges = snapshot_hashtbl application.elision_edges;
    checkpoint_echo = copy application.runtime_echo;
    checkpoint_next_handler_id = !(application.next_handler_id);
    checkpoint_event_handlers = copy application.event_handlers;
    checkpoint_next_dynamic_segment_id =
      !(application.next_dynamic_segment_id);
    checkpoint_dynamic_segments = segments;
    checkpoint_segment_values = Hashtbl.fold (fun _ segments values ->
      List.fold_left (fun values segment ->
        (segment, !(segment.dynamic_segment_base), !(segment.dynamic_segment_size),
         !(segment.dynamic_segment_active), !(segment.dynamic_segment_on_property))
        :: values) values segments) segments [];
    checkpoint_reload_keys = copy application.runtime_reload_keys;
    checkpoint_node_aliases = (match nodes with
      | None -> Hashtbl.copy application.runtime_node_aliases
      | Some nodes ->
        let aliases = Hashtbl.create 16 in
        List.iter (fun target -> match Hashtbl.find_opt application.runtime_alias_targets target with
          | None -> ()
          | Some candidates -> List.iter (fun candidate -> Hashtbl.replace aliases candidate target) candidates) nodes;
        aliases);
    checkpoint_handler_count = !(application.runtime_handler_count);
    checkpoint_dynamic_segment_count =
      !(application.runtime_dynamic_segment_count);
    checkpoint_extension_dirty = !(application.runtime_extension_dirty);
  }

(* Full create/set/insert batch describing all live trees, including
   ordinary app roots and independently mounted extensions. A host that has
   rejected a delta and rolled its mirror back applies this after clearing
   local state, adopting [generation] as the new baseline. *)
let resync_batch application =
  let roots = ref [] in
  let add_root node _ =
    if not (Hashtbl.mem application.runtime_parents node) then
      roots := node :: !roots
  in
  Hashtbl.iter add_root application.mounted_nodes;
  Hashtbl.iter add_root application.runtime_extension_nodes;
  let generation = max 1 !(application.runtime_generation) in
  let ops = ref [] in
  let add operation = ops := operation :: !ops in
  let rec walk node =
    (match Hashtbl.find_opt application.mounted_nodes node with
    | Some kind -> add (create_node_op node kind)
    | None -> (
      match Hashtbl.find_opt application.runtime_extension_nodes node with
      | Some identifier ->
        add (create_extension_op node identifier "")
      | None -> ()));
    (match Hashtbl.find_opt application.runtime_properties node with
    | Some props ->
      Property_map.iter
        (fun property value -> add (set_prop_op node property value))
        props
    | None -> ());
    (match Hashtbl.find_opt application.runtime_extension_properties node with
    | Some props ->
      String_map.iter
        (fun property value ->
           add (set_extension_prop_op node property value))
        props
    | None -> ());
    let kids =
      match Hashtbl.find_opt application.runtime_children node with
      | Some children -> Lui_sequence.to_list children
      | None -> []
    in
    List.iteri
      (fun index child ->
         walk child;
         add (insert_child_op node child index))
      kids
  in
  List.iter walk (List.sort Int.compare !roots);
  { generation; ops = List.rev !ops }

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
  let affected, orphans =
    match saved.checkpoint_nodes with
    | None -> None, []
    | Some nodes ->
      let created = List.init (!(application.next_node_id) - saved.checkpoint_next_node_id)
        (fun index -> saved.checkpoint_next_node_id + index + 1) in
      (* nodes created after the checkpoint may already be materialized
         in the store; the rollback wipes their runtime entries but the
         painted copies survive unless detach ops unwind them *)
      let orphans =
        List.filter
          (fun node ->
            Hashtbl.mem application.mounted_nodes node
            || Hashtbl.mem application.runtime_extension_nodes node)
          created
      in
      Some (nodes @ created), orphans
  in
  restore_identity application application.next_node_id saved.checkpoint_next_node_id;
  restore_identity application application.next_virtual_generation saved.checkpoint_next_virtual_generation;
  journal_clear application Virtual_sources application.runtime_virtual_sources;
  Hashtbl.iter (journal_replace application Virtual_sources application.runtime_virtual_sources) saved.checkpoint_virtual_sources;
  journal_clear application Virtual_owners application.runtime_virtual_owners;
  Hashtbl.iter (journal_replace application Virtual_owners application.runtime_virtual_owners) saved.checkpoint_virtual_owners;
  journal_clear application Virtual_receipts application.runtime_virtual_receipts;
  Hashtbl.iter (journal_replace application Virtual_receipts application.runtime_virtual_receipts) saved.checkpoint_virtual_receipts;
  List.iter (fun restore -> restore ()) saved.checkpoint_restore_virtual;
  let replace slot target source =
    (match affected with None -> journal_clear application slot target
    | Some nodes -> List.iter (journal_remove application slot target) nodes);
    Hashtbl.iter (fun key value -> journal_replace application slot target key value) source
  in
  replace Mounted_nodes application.mounted_nodes saved.checkpoint_mounted_nodes;
  replace Extension_nodes application.runtime_extension_nodes saved.checkpoint_extension_nodes;
  replace_property_table ?nodes:affected application saved.checkpoint_properties;
  replace_extension_property_table ?nodes:affected application saved.checkpoint_extension_properties;
  replace_children_table ?nodes:affected application saved.checkpoint_children;
  replace Parents application.runtime_parents saved.checkpoint_parents;
  journal_restore_pending application saved.checkpoint_pending_ops;
  journal_clear application Pending_creates application.pending_creates;
  Hashtbl.iter
    (fun node () -> journal_replace application Pending_creates application.pending_creates node ())
    saved.checkpoint_pending_creates;
  journal_clear application Elision_ghosts application.elision_ghosts;
  journal_clear application Elision_root application.elision_root;
  journal_clear application Elision_members application.elision_members;
  journal_clear application Elision_edges application.elision_edges;
  Hashtbl.iter
    (fun node () -> journal_replace application Elision_ghosts application.elision_ghosts node ())
    saved.checkpoint_elision_ghosts;
  Hashtbl.iter
    (fun id root -> journal_replace application Elision_root application.elision_root id root)
    saved.checkpoint_elision_root;
  Hashtbl.iter
    (fun root ids -> journal_replace application Elision_members application.elision_members root ids)
    saved.checkpoint_elision_members;
  Hashtbl.iter
    (fun child parent -> journal_replace application Elision_edges application.elision_edges child parent)
    saved.checkpoint_elision_edges;
  replace_echo_table ?nodes:affected application saved.checkpoint_echo;
  restore_identity application application.next_handler_id saved.checkpoint_next_handler_id;
  replace_list_table ?nodes:affected application Handler_member application.event_handlers
    saved.checkpoint_event_handlers (fun handler -> handler.handler_id);
  restore_identity application application.next_dynamic_segment_id
    saved.checkpoint_next_dynamic_segment_id;
  replace_list_table ?nodes:affected application Segment_member application.dynamic_segments
    saved.checkpoint_dynamic_segments (fun segment -> segment.dynamic_segment_id);
  List.iter (fun (segment, base, size, active, on_property) ->
    journal_ref application Segment_base segment.dynamic_segment_id segment.dynamic_segment_base base;
    journal_ref application Segment_size segment.dynamic_segment_id segment.dynamic_segment_size size;
    journal_ref application Segment_active segment.dynamic_segment_id segment.dynamic_segment_active active;
    journal_ref application Segment_on_property segment.dynamic_segment_id segment.dynamic_segment_on_property on_property)
    saved.checkpoint_segment_values;
  replace Reload_keys application.runtime_reload_keys saved.checkpoint_reload_keys;
  (match affected with
  | None -> journal_clear application Node_aliases application.runtime_node_aliases; journal_clear application Alias_targets application.runtime_alias_targets
  | Some nodes -> List.iter (fun node -> remove_target_aliases application node; remove_alias application node) nodes);
  Hashtbl.iter (set_alias application) saved.checkpoint_node_aliases;
  application.runtime_handler_count := saved.checkpoint_handler_count;
  application.runtime_dynamic_segment_count :=
    saved.checkpoint_dynamic_segment_count;
  application.runtime_extension_dirty := saved.checkpoint_extension_dirty;
  List.iter
    (fun node ->
      application.pending_ops :=
        Lui_protocol.DetachSubtree node :: !(application.pending_ops))
    orphans

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

let key_counts nodes reload_keys =
  let counts = Hashtbl.create 16 in
  List.iter
    (fun node ->
       match Hashtbl.find_opt reload_keys node with
       | Some key ->
           Hashtbl.replace counts key
             (1 + Option.value (Hashtbl.find_opt counts key) ~default:0)
       | None -> ())
    nodes;
  counts

let key_unique counts key = Hashtbl.find_opt counts key = Some 1

(* A keyed child that moved to a different parent is the same logical node:
   adopt it so its subtree (focus, textarea contents, mounted state)
   survives instead of being dropped and recreated. An old node can only be
   claimed once, and adoption requires the key to be unique on both sides —
   the same key can legitimately appear under two parents (e.g. a live
   block row and a read-only references row), and adopting one claimant's
   subtree would steal another's, with the winner flipping whenever
   traversal order changed. *)
let match_candidate_child (old_children : int array)
    old_keyed old_reload_keys candidate_reload_keys old_global
    old_key_counts candidate_key_counts reparented claimed index
    candidate_child =
  match Hashtbl.find_opt candidate_reload_keys candidate_child with
  | Some key -> (
      match Hashtbl.find_opt old_keyed key with
      | Some found when not (Hashtbl.mem claimed found) -> Some found
      | _ -> (
          match Hashtbl.find_opt old_global key with
          | Some adopted
            when (not (Hashtbl.mem claimed adopted))
                 && key_unique old_key_counts key
                 && key_unique candidate_key_counts key ->
              Hashtbl.replace reparented adopted ();
              Some adopted
          | _ -> None))
  | None ->
      if index < Array.length old_children then
        let position_child = old_children.(index) in
        if Hashtbl.mem old_reload_keys position_child then None
        else Some position_child
      else None

let rec collect_node_mapping application saved old_node candidate_node
    old_global old_key_counts candidate_key_counts reparented claimed
    saved_children_node_set mapping =
  if not (node_compatible application saved old_node candidate_node) then
    mapping
  else begin
    Hashtbl.replace mapping candidate_node old_node;
    Hashtbl.replace claimed old_node ();
    let old_children =
      match Hashtbl.find_opt saved.checkpoint_children old_node with
      | Some children -> Lui_sequence.to_list children
      | None -> []
    in
    let old_children_index = Array.of_list old_children in
    let candidate_children =
      match Hashtbl.find_opt application.runtime_children candidate_node with
      | Some children -> Lui_sequence.to_list children
      | None -> []
    in
    let old_reload_keys = saved.checkpoint_reload_keys in
    let candidate_reload_keys = application.runtime_reload_keys in
    let old_keyed = keyed_children old_children old_reload_keys in
    ignore (keyed_children candidate_children candidate_reload_keys);
    List.iteri
      (fun index candidate_child ->
         match
           match_candidate_child old_children_index old_keyed old_reload_keys
             candidate_reload_keys old_global old_key_counts
             candidate_key_counts reparented claimed index candidate_child
         with
         | Some matched ->
             if node_compatible application saved matched candidate_child
             then
               ignore
                 (collect_node_mapping application saved matched
                    candidate_child old_global old_key_counts
                    candidate_key_counts reparented claimed
                    saved_children_node_set mapping)
             else
               rescue_subtree application saved candidate_child old_global
                 old_key_counts candidate_key_counts reparented claimed
                 saved_children_node_set mapping
         | None ->
             rescue_subtree application saved candidate_child old_global
               old_key_counts candidate_key_counts reparented claimed
               saved_children_node_set mapping)
      candidate_children;
    mapping
  end

(* A freshly-mounted container (e.g. a block's children list appearing when
   it gains children) has no old counterpart, so no recursion reaches its
   keyed descendants — yet each descendant can still be the same logical
   node as a keyed node elsewhere in the old subtree (a row being nested
   under that block). Walk the unmapped candidate subtree and let keyed
   nodes adopt their live counterparts instead of dropping and recreating
   them (which would lose focus and textarea contents). *)
and rescue_subtree application saved candidate_node old_global
    old_key_counts candidate_key_counts reparented claimed
    saved_children_node_set mapping =
  if Hashtbl.mem mapping candidate_node then ()
  else
    let descend () =
      let children =
        match
          Hashtbl.find_opt application.runtime_children candidate_node
        with
        | Some children -> Lui_sequence.to_list children
        | None -> []
      in
      List.iter
        (fun child ->
          rescue_subtree application saved child old_global old_key_counts
            candidate_key_counts reparented claimed
            saved_children_node_set mapping)
        children
    in
    match
      Hashtbl.find_opt application.runtime_reload_keys candidate_node
    with
    | Some key -> (
        match Hashtbl.find_opt old_global key with
        | Some adopted
          when (not (Hashtbl.mem claimed adopted))
               && key_unique old_key_counts key
               && key_unique candidate_key_counts key
               && node_compatible application saved adopted candidate_node ->
            Hashtbl.replace reparented adopted ();
            ignore
              (collect_node_mapping application saved adopted candidate_node
                 old_global old_key_counts candidate_key_counts reparented
                 claimed saved_children_node_set mapping)
        | _ -> descend ())
    | None -> descend ()

let collect_subtree_nodes children_map root =
  let rec collect node acc =
    let children =
      match Hashtbl.find_opt children_map node with
      | Some current -> current
      | None -> Lui_sequence.empty
    in
    Lui_sequence.fold_left (fun acc child -> collect child acc) (node :: acc) children
  in
  List.rev (collect root [])

let checkpoint_subtree application parent root =
  let root = canonical_node application root in
  let parent = canonical_node application parent in
  checkpoint ~nodes:(parent :: collect_subtree_nodes application.runtime_children root) application

let retire_checkpoint_dynamic_segments application saved root =
  List.iter
    (fun node ->
       match Hashtbl.find_opt saved.checkpoint_dynamic_segments node with
       | Some segments ->
         List.iter
           (fun segment -> journal_ref application Segment_active
             segment.dynamic_segment_id segment.dynamic_segment_active false)
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
         | None -> Lui_sequence.empty
       in
       Hashtbl.replace base
         (map_node mapping candidate)
         (Lui_sequence.map (fun child -> map_node mapping child) children))
    candidate_nodes;
  base

let rebuild_parents children_map =
  let parents = Hashtbl.create 16 in
  Hashtbl.iter
    (fun parent children ->
       Lui_sequence.iter (fun child -> Hashtbl.replace parents child parent) children)
    children_map;
  parents

let index_map children =
  let result = Hashtbl.create 16 in
  List.iteri (fun index child -> Hashtbl.replace result child index) children;
  result

let extension_wire_fingerprint application identifier fingerprint =
  if Hashtbl.mem application.runtime_fingerprint_sent identifier then ""
  else begin
    Hashtbl.replace application.runtime_fingerprint_sent identifier ();
    fingerprint
  end

let remember_pending_create application operation =
  match operation with
  | CreateNode (node, _) | CreateExtension (node, _, _) ->
    journal_replace application Pending_creates application.pending_creates node ()
  | _ -> ()

let enqueue application operation =
  application.pending_ops := operation :: !(application.pending_ops);
  remember_pending_create application operation

(* Detach whatever the store still holds for [node] — for nodes whose
   runtime entries were already wiped (scope disposal, restore) while
   their painted copy survived. *)
let enqueue_detach application node =
  enqueue application (detach_subtree_op node)

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

let emit_child_diff application reparented parent old_children
    desired_children =
  let desired_index = index_map desired_children in
  let surviving =
    List.filter
      (fun child ->
         if Hashtbl.mem desired_index child then true
         else if Hashtbl.mem reparented child then
           (* adopted under another parent: its RemoveChild was already
              enqueued before the parent diffs, and the new parent emits the
              InsertChild *)
           false
         else begin
           enqueue application (remove_child_op parent child);
           false
         end)
      old_children
  in
  (* A placed prefix plus the unplaced old rows describes the current
     order. Prefix sums locate retained rows without shifting arrays. *)
  let positions = index_map surviving in
  let counts = Array.make (List.length surviving + 1) 0 in
  let add position delta =
    let index = ref (position + 1) in
    while !index < Array.length counts do
      counts.(!index) <- counts.(!index) + delta;
      index := !index + (!index land (- !index))
    done
  in
  let before position =
    let total = ref 0 and index = ref position in
    while !index > 0 do
      total := !total + counts.(!index);
      index := !index - (!index land (- !index))
    done;
    !total
  in
  List.iteri (fun index _ -> add index 1) surviving;
  List.iteri (fun index child ->
    match Hashtbl.find_opt positions child with
    | Some old_index ->
      if before old_index <> 0 then
        enqueue application (move_child_op parent child index);
      add old_index (-1)
    | None -> enqueue application (insert_child_op parent child index))
    desired_children

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

(* Ops are replayed post-commit: by then a node dropped in the same
   batch no longer resolves through the store or the pre-batch mirror,
   so any queued op mentioning it can never apply. A node created and
   dropped within one batch therefore cancels out entirely — its whole
   op group (including structural detach ops) is pruned and no drop op
   is emitted. Nodes dropped across batches keep their ops: pre-existing
   records resolve through the pre-batch mirror, and the store still
   needs the remove-child op that precedes a drop.

   Dropping marks the node instead of rewriting the queue: at flush the
   whole pending stream is replayed ONCE, pruning ops that mention an
   elided id and renumbering surviving structural ops around each ghost
   slot. Replaying the queue per drop (the old design) rescanned
   [pending_ops] for every dropped node and shifted a per-parent
   position table on every structural op, which made replacing a keyed
   collection before its first flush cubic in the item count. *)
let pending_create_exists application node =
  Hashtbl.mem application.pending_creates node

(* Mark every id in [ids] (leaves-first, [root] is the outermost node) as
   created-and-dropped inside the open batch. Internal child -> parent
   links that carry no dedicated remove op are kept so a fallback drop
   can still unlink the group explicitly. *)
let mark_elided_group application root ids =
  let group = Hashtbl.create (List.length ids) in
  List.iter (fun id -> Hashtbl.replace group id ()) ids;
  List.iter
    (fun id ->
       journal_replace application Elision_ghosts application.elision_ghosts id ();
       journal_replace application Elision_root application.elision_root id root;
       journal_remove application Pending_creates application.pending_creates id;
       if id <> root then
         match Hashtbl.find_opt application.runtime_parents id with
         | Some parent when Hashtbl.mem group parent ->
             journal_replace application Elision_edges application.elision_edges id parent
         | _ -> ())
    ids;
  journal_replace application Elision_members application.elision_members root ids

let enqueue_drop application node =
  if pending_create_exists application node then
    mark_elided_group application node [ node ]
  else enqueue application (drop_node_op node)

(* Implicit-order sequence over one parent's children during the replay:
   a size-augmented treap keyed by position, tracking how many of the
   children in each subtree are elided ghosts. [slot_ghosts_below]
   answers "how many ghosts sit before index i" in O(log n) — the query
   each surviving structural op needs to renumber itself. *)
type elision_slot = {
  slot_child : int;
  slot_ghost : bool;
  slot_prio : int;
  mutable slot_left : elision_slot option;
  mutable slot_right : elision_slot option;
  mutable slot_parent : elision_slot option;
  mutable slot_size : int;
  mutable slot_ghosts : int;
}

let slot_size = function None -> 0 | Some slot -> slot.slot_size
let slot_ghosts = function None -> 0 | Some slot -> slot.slot_ghosts

let slot_update slot =
  slot.slot_size <- 1 + slot_size slot.slot_left + slot_size slot.slot_right;
  slot.slot_ghosts <-
    (if slot.slot_ghost then 1 else 0) + slot_ghosts slot.slot_left
    + slot_ghosts slot.slot_right

let make_slot child ghost =
  {
    slot_child = child;
    slot_ghost = ghost;
    (* a fixed mix keeps the treap balanced for sequential node ids *)
    slot_prio = (child * 0x9E3779B1) land max_int;
    slot_left = None;
    slot_right = None;
    slot_parent = None;
    slot_size = 1;
    slot_ghosts = (if ghost then 1 else 0);
  }

(* split [root] into its first [count] elements and the rest; returned
   roots carry no parent pointer *)
let rec slot_split root count =
  match root with
  | None -> (None, None)
  | Some slot ->
    let left_size = slot_size slot.slot_left in
    if count <= left_size then begin
      let left, mid = slot_split slot.slot_left count in
      slot.slot_left <- mid;
      (match mid with Some mid -> mid.slot_parent <- Some slot | None -> ());
      slot_update slot;
      slot.slot_parent <- None;
      (left, Some slot)
    end
    else begin
      let mid, right = slot_split slot.slot_right (count - left_size - 1) in
      slot.slot_right <- mid;
      (match mid with Some mid -> mid.slot_parent <- Some slot | None -> ());
      slot_update slot;
      slot.slot_parent <- None;
      (Some slot, right)
    end

let rec slot_merge left right =
  match (left, right) with
  | None, _ ->
    (match right with Some r -> r.slot_parent <- None | None -> ());
    right
  | _, None ->
    (match left with Some l -> l.slot_parent <- None | None -> ());
    left
  | Some left, Some right ->
    if left.slot_prio > right.slot_prio then begin
      let merged = slot_merge left.slot_right (Some right) in
      left.slot_right <- merged;
      (match merged with Some m -> m.slot_parent <- Some left | None -> ());
      slot_update left;
      left.slot_parent <- None;
      Some left
    end
    else begin
      let merged = slot_merge (Some left) right.slot_left in
      right.slot_left <- merged;
      (match merged with Some m -> m.slot_parent <- Some right | None -> ());
      slot_update right;
      right.slot_parent <- None;
      Some right
    end

let slot_insert root index slot =
  let left, right = slot_split root index in
  slot_merge (slot_merge left (Some slot)) right

let slot_rank slot =
  let rank = ref (slot_size slot.slot_left) in
  let rec walk node =
    match node.slot_parent with
    | None -> ()
    | Some parent ->
      (match parent.slot_right with
       | Some right when right == node ->
           rank := !rank + slot_size parent.slot_left + 1
       | _ -> ());
      walk parent
  in
  walk slot;
  !rank

let slot_remove root slot =
  let left, rest = slot_split root (slot_rank slot) in
  let _slot, right = slot_split rest 1 in
  slot_merge left right

(* ghosts among the first [index] positions *)
let rec slot_ghosts_below root index =
  match root with
  | None -> 0
  | Some slot ->
    if index <= 0 then 0
    else
      let left_size = slot_size slot.slot_left in
      if index <= left_size then slot_ghosts_below slot.slot_left index
      else
        slot_ghosts slot.slot_left + (if slot.slot_ghost then 1 else 0)
        + slot_ghosts_below slot.slot_right (index - left_size - 1)

(* Replay the pending stream once and produce the batch to send. Ops
   that mention an elided node are pruned; structural ops that survive
   are renumbered around each ghost slot they assumed was still there.
   A ghost group whose parent's index repair is unrecoverable — an op
   removed or moved a child the batch itself never attached — falls
   back to a real drop: edge unlinks first, then drop ops leaves-first,
   appended after the original ops so "created then dropped" still
   holds. *)
let elide_pending_ops application =
  let ops = !(application.pending_ops) in
  (* ghosts forced real after their parent's repair was found unsafe *)
  let real = Hashtbl.create 8 in
  (* parents whose tracked positions an untracked remove/move broke *)
  let poisoned = Hashtbl.create 4 in
  let marked_roots = Hashtbl.create 4 in
  (* per-parent live children / currently-attached ghosts, seeded from
     the flush-time child lists and updated as the ops say *)
  let live = Hashtbl.create 8 in
  let active = Hashtbl.create 8 in
  (* (parent, child) pairs attached by a pending op — never treated as
     pre-existing children when seeding a parent's tracked order *)
  let attached = Hashtbl.create 16 in
  let ghost id =
    Hashtbl.mem application.elision_ghosts id && not (Hashtbl.mem real id)
  in
  let mark_fallback id =
    let root =
      match Hashtbl.find_opt application.elision_root id with
      | Some root -> root
      | None -> id
    in
    if not (Hashtbl.mem marked_roots root) then begin
      Hashtbl.replace marked_roots root ();
      match Hashtbl.find_opt application.elision_members root with
      | Some ids -> List.iter (fun id -> Hashtbl.replace real id ()) ids
      | None -> Hashtbl.replace real root ()
    end
  in
  let live_children parent =
    match Hashtbl.find_opt live parent with
    | Some children -> children
    | None ->
      let children = Hashtbl.create 8 in
      (match Hashtbl.find_opt application.runtime_children parent with
       | Some current ->
           Lui_sequence.iter
             (fun child -> Hashtbl.replace children child ()) current
       | None -> ());
      Hashtbl.replace live parent children;
      children
  in
  let active_ghosts parent =
    match Hashtbl.find_opt active parent with
    | Some ghosts -> ghosts
    | None ->
      let ghosts = Hashtbl.create 8 in
      Hashtbl.replace active parent ghosts;
      ghosts
  in
  let untracked_foreign parent =
    Hashtbl.replace poisoned parent ();
    match Hashtbl.find_opt active parent with
    | Some ghosts -> Hashtbl.iter (fun id () -> mark_fallback id) ghosts
    | None -> ()
  in
  (* first pass: which children does the stream attach where, and which
     parents saw a remove/move of a child it never tracked *)
  List.iter
    (fun operation ->
       match operation with
       | InsertChild (parent, child, _) ->
         if not (ghost parent) then begin
           Hashtbl.replace (live_children parent) child ();
           Hashtbl.replace attached (parent, child) ();
           if ghost child then
             if Hashtbl.mem poisoned parent then mark_fallback child
             else Hashtbl.replace (active_ghosts parent) child ()
         end
       | RemoveChild (parent, child) ->
         if not (ghost parent) then
           if Hashtbl.mem (live_children parent) child then begin
             Hashtbl.remove (live_children parent) child;
             match Hashtbl.find_opt active parent with
             | Some ghosts -> Hashtbl.remove ghosts child
             | None -> ()
           end
           else untracked_foreign parent
       | MoveChild (parent, child, _) ->
         if
           (not (ghost parent))
           && not (Hashtbl.mem (live_children parent) child)
         then untracked_foreign parent
       | _ -> ())
    (List.rev ops);
  (* second pass: prune ghost ops and renumber survivors around the
     ghost slots they assumed, seeding each parent's tracked order with
     its pre-existing children *)
  let seqs = Hashtbl.create 8 in
  let slot_of = Hashtbl.create 16 in
  let seq_children parent =
    match Hashtbl.find_opt seqs parent with
    | Some state -> state
    | None ->
      let state = ref None in
      (match Hashtbl.find_opt application.runtime_children parent with
       | Some current ->
           Lui_sequence.iter
             (fun child ->
                if not (Hashtbl.mem attached (parent, child)) then begin
                  let slot = make_slot child false in
                  state := slot_insert !state (slot_size !state) slot;
                  Hashtbl.replace slot_of child slot
                end)
             current
       | None -> ());
      Hashtbl.replace seqs parent state;
      state
  in
  let out = ref [] in
  let emit operation = out := operation :: !out in
  let drop_slot parent child =
    match Hashtbl.find_opt slot_of child with
    | Some slot ->
      let state = seq_children parent in
      state := slot_remove !state slot;
      Hashtbl.remove slot_of child;
      true
    | None -> false
  in
  let ghost_mention operation =
    match operation with
    | CreateNode (subject, _)
    | CreateExtension (subject, _, _)
    | DropNode subject
    | DetachSubtree subject
    | SetProp (subject, _, _)
    | RemoveProp (subject, _)
    | SetExtensionProp (subject, _, _)
    | RemoveExtensionProp (subject, _) -> ghost subject
    | _ -> false
  in
  List.iter
    (fun operation ->
       match operation with
       | InsertChild (parent, child, index) ->
         if ghost parent then ()
         else if ghost child then begin
           let state = seq_children parent in
           let slot = make_slot child true in
           state := slot_insert !state index slot;
           Hashtbl.replace slot_of child slot
         end
         else begin
           let state = seq_children parent in
           emit
             (insert_child_op parent child
                (index - slot_ghosts_below !state index));
           let slot = make_slot child false in
           state := slot_insert !state index slot;
           Hashtbl.replace slot_of child slot
         end
       | RemoveChild (parent, child) ->
         if ghost parent then ()
         else if ghost child then ignore (drop_slot parent child)
         else begin
           ignore (drop_slot parent child);
           emit operation
         end
       | MoveChild (parent, child, index) ->
         if ghost parent then ()
         else if ghost child then
           (match Hashtbl.find_opt slot_of child with
            | Some slot ->
              let state = seq_children parent in
              state := slot_remove !state slot;
              state := slot_insert !state index slot
            | None -> ())
         else
           (match Hashtbl.find_opt slot_of child with
            | Some slot ->
              let state = seq_children parent in
              state := slot_remove !state slot;
              emit
                (move_child_op parent child
                   (index - slot_ghosts_below !state index));
              state := slot_insert !state index slot
            | None -> emit operation)
       | _ -> if not (ghost_mention operation) then emit operation)
    (List.rev ops);
  (* fallback drops for the groups forced real above *)
  let drops = ref [] in
  Hashtbl.iter
    (fun root () ->
       let ids =
         match Hashtbl.find_opt application.elision_members root with
         | Some ids -> ids
         | None -> [ root ]
       in
       List.iter
         (fun id ->
            match Hashtbl.find_opt application.elision_edges id with
            | Some parent -> drops := remove_child_op parent id :: !drops
            | None -> ())
         ids;
       List.iter (fun id -> drops := drop_node_op id :: !drops) ids)
    marked_roots;
  journal_clear application Elision_ghosts application.elision_ghosts;
  journal_clear application Elision_root application.elision_root;
  journal_clear application Elision_members application.elision_members;
  journal_clear application Elision_edges application.elision_edges;
  List.rev !out @ List.rev !drops
let rec emit_dropped_subtree application saved removed_set node =
  if pending_create_exists application node then
    (* a node created inside this batch still needs the per-node walk so
       the elision replay can prune its whole op group *)
    emit_dropped_subtree_ops application saved removed_set node
  else
    (* one op for the whole subtree: the store unlinks the root from its
       parent (the emit_child_diff remove-child may have already done so)
       and unmounts every descendant — props, children, handlers and
       extension registrations all die with it *)
    enqueue application (detach_subtree_op node)

and emit_dropped_subtree_ops application saved removed_set node =
  let children =
    match Hashtbl.find_opt saved.checkpoint_children node with
    | Some current -> Lui_sequence.to_list current
    | None -> []
  in
  List.iter
    (fun child ->
       if Hashtbl.mem removed_set child then begin
         enqueue application (remove_child_op node child);
         emit_dropped_subtree application saved removed_set child
       end)
    children;
  enqueue_drop application node

let reconcile_forest ?range application saved parent old_roots candidate_roots =
  let parent = canonical_node application parent in
  let old_roots = List.map (canonical_node application) old_roots in
  let current_children = application.runtime_children in
  let old_nodes = List.concat_map (collect_subtree_nodes saved.checkpoint_children) old_roots in
  let candidate_nodes = List.concat_map (collect_subtree_nodes current_children) candidate_roots in
  let mapping = Hashtbl.create 16 in
  let old_global = Hashtbl.create 16 in
  List.iter
    (fun node ->
       match Hashtbl.find_opt saved.checkpoint_reload_keys node with
       | Some key -> Hashtbl.replace old_global key node
       | None -> ())
    old_nodes;
  let reparented = Hashtbl.create 8 in
  let claimed = Hashtbl.create 16 in
  let old_key_counts = key_counts old_nodes saved.checkpoint_reload_keys in
  let candidate_key_counts =
    key_counts candidate_nodes application.runtime_reload_keys
  in
  let saved_children_node_set = Hashtbl.create 16 in
  List.iter
    (fun node -> Hashtbl.replace saved_children_node_set node ())
    old_nodes;
  let rec pair old candidates =
    match old, candidates with
    | old_root :: rest, candidate_root :: candidates ->
      if Hashtbl.find_opt saved.checkpoint_reload_keys old_root
         = Hashtbl.find_opt application.runtime_reload_keys candidate_root then
        ignore (collect_node_mapping application saved old_root candidate_root
          old_global old_key_counts candidate_key_counts reparented claimed
          saved_children_node_set mapping);
      pair rest candidates
    | _ -> () in
  pair old_roots candidate_roots;
  List.iter (fun candidate_root ->
    if not (Hashtbl.mem mapping candidate_root) then
      rescue_subtree application saved candidate_root old_global
        old_key_counts candidate_key_counts reparented claimed
        saved_children_node_set mapping) candidate_roots;
  let desired_roots = List.map (map_node mapping) candidate_roots in
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
  (* Owner references are node ids inside property values, so remapping only
     their table keys would leave sources pointing at discarded candidates. *)
  Hashtbl.iter (fun node properties ->
    match Property_map.find_opt VirtualOwnerNode properties with
    | Some (IntValue owner) -> Hashtbl.replace desired_properties node
        (Property_map.add VirtualOwnerNode (IntValue (map_node mapping owner)) properties)
    | _ -> ()) desired_properties;
  let remap_virtual current saved =
    let base = snapshot_hashtbl saved in
    remove_node_keys base old_nodes;
    remap_node_values current candidate_nodes mapping base in
  let desired_virtual_sources = remap_virtual application.runtime_virtual_sources
    saved.checkpoint_virtual_sources in
  let desired_virtual_owners = remap_virtual application.runtime_virtual_owners
    saved.checkpoint_virtual_owners in
  let base_echo = Hashtbl.copy saved.checkpoint_echo in
  remove_node_keys base_echo old_nodes;
  let desired_echo =
    remap_node_values application.runtime_echo candidate_nodes mapping base_echo
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
  let siblings =
    match Hashtbl.find_opt base_children parent with
    | Some children -> Lui_sequence.to_list children
    | None -> []
  in
  let base = match range with Some (base, _) -> base | None ->
    let rec index i = function
      | [] -> i
      | child :: rest -> if List.mem child old_roots then i else index (i + 1) rest in
    index 0 siblings in
  let count = match range with Some (_, count) -> count | None -> List.length old_roots in
  let desired_parent_children =
    List.filteri (fun index _ -> index < base) siblings
    @ desired_roots
    @ List.filteri (fun index _ -> index >= base + count) siblings in
  Hashtbl.replace desired_children parent (Lui_sequence.of_list desired_parent_children);
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
  (match range with None -> () | Some _ ->
    Option.iter (Hashtbl.replace desired_segments parent)
      (Hashtbl.find_opt application.dynamic_segments parent));
  if List.exists (fun root -> Hashtbl.find_opt application.mounted_nodes root = Some Root) candidate_roots then
    invalid_arg "runtime root cannot be nested";
  journal_restore_pending application saved.checkpoint_pending_ops;
  journal_clear application Pending_creates application.pending_creates;
  Hashtbl.iter
    (fun node () -> journal_replace application Pending_creates application.pending_creates node ())
    saved.checkpoint_pending_creates;
  journal_clear application Elision_ghosts application.elision_ghosts;
  journal_clear application Elision_root application.elision_root;
  journal_clear application Elision_members application.elision_members;
  journal_clear application Elision_edges application.elision_edges;
  Hashtbl.iter
    (fun node () -> journal_replace application Elision_ghosts application.elision_ghosts node ())
    saved.checkpoint_elision_ghosts;
  Hashtbl.iter
    (fun id root -> journal_replace application Elision_root application.elision_root id root)
    saved.checkpoint_elision_root;
  Hashtbl.iter
    (fun root ids -> journal_replace application Elision_members application.elision_members root ids)
    saved.checkpoint_elision_members;
  Hashtbl.iter
    (fun child parent -> journal_replace application Elision_edges application.elision_edges child parent)
    saved.checkpoint_elision_edges;
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
               (create_extension_op candidate identifier
                  (extension_wire_fingerprint application identifier
                     fingerprint))
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
    List.rev_append
      (List.map (fun candidate -> map_node mapping candidate) candidate_nodes)
      [ parent ]
  in
  (* reparented children detach from their old parent before any insert so
     a stale actual-parent remove cannot undo the move *)
  Hashtbl.iter
    (fun node () ->
       match Hashtbl.find_opt saved.checkpoint_parents node with
       | Some old_parent ->
           enqueue application (remove_child_op old_parent node)
       | None -> ())
    reparented;
  List.iter
    (fun node ->
       let old_children =
         match Hashtbl.find_opt saved.checkpoint_children node with
         | Some children -> Lui_sequence.to_list children
         | None -> []
       in
       let new_children =
         match Hashtbl.find_opt desired_children node with
         | Some children -> Lui_sequence.to_list children
         | None -> []
       in
       emit_child_diff application reparented node old_children new_children)
    all_parents;
  List.iter
    (fun node ->
       match Hashtbl.find_opt saved.checkpoint_parents node with
       | Some old_parent ->
         if not (Hashtbl.mem removed_set old_parent) then
           emit_dropped_subtree application saved removed_set node
       | None -> emit_dropped_subtree application saved removed_set node)
    removed_nodes;
  let affected = match saved.checkpoint_nodes with
    | None -> None
    | Some nodes -> Some (nodes @ candidate_nodes) in
  let replace slot target source =
    (match affected with None -> journal_clear application slot target
    | Some nodes -> List.iter (journal_remove application slot target) nodes);
    Hashtbl.iter (fun key value -> journal_replace application slot target key value) source
  in
  replace Mounted_nodes application.mounted_nodes desired_standard;
  replace Extension_nodes application.runtime_extension_nodes desired_extensions;
  replace_property_table ?nodes:affected application desired_properties;
  journal_clear application Virtual_sources application.runtime_virtual_sources;
  Hashtbl.iter (journal_replace application Virtual_sources application.runtime_virtual_sources) desired_virtual_sources;
  journal_clear application Virtual_owners application.runtime_virtual_owners;
  Hashtbl.iter (journal_replace application Virtual_owners application.runtime_virtual_owners) desired_virtual_owners;
  replace_echo_table ?nodes:affected application desired_echo;
  replace_extension_property_table ?nodes:affected application desired_extension_properties;
  replace_children_table ?nodes:affected application desired_children;
  let new_parents = rebuild_parents desired_children in
  (match saved.checkpoint_nodes with
  | Some _ ->
    (match Hashtbl.find_opt saved.checkpoint_parents parent with
    | Some owner -> Hashtbl.replace new_parents parent owner
    | None -> ())
  | None -> ());
  replace Parents application.runtime_parents new_parents;
  replace_list_table ?nodes:affected application Handler_member application.event_handlers
    desired_handlers (fun handler -> handler.handler_id);
  replace_list_table ?nodes:affected application Segment_member application.dynamic_segments
    desired_segments (fun segment -> segment.dynamic_segment_id);
  application.runtime_handler_count :=
    (match saved.checkpoint_nodes with None -> 0 | Some _ ->
      saved.checkpoint_handler_count - Hashtbl.fold
        (fun _ handlers count -> count + List.length handlers) saved.checkpoint_event_handlers 0)
    + Hashtbl.fold
      (fun _node handlers total -> total + List.length handlers)
      desired_handlers 0;
  application.runtime_dynamic_segment_count :=
    (match saved.checkpoint_nodes with None -> 0 | Some _ ->
      saved.checkpoint_dynamic_segment_count - Hashtbl.fold
        (fun _ segments count -> count + List.length segments) saved.checkpoint_dynamic_segments 0)
    + Hashtbl.fold
      (fun _parent segments total -> total + List.length segments)
      desired_segments 0;
  replace Reload_keys application.runtime_reload_keys desired_reload_keys;
  application.runtime_extension_dirty :=
    saved.checkpoint_extension_dirty || Hashtbl.length desired_extensions > 0;
  (* Aliases established by earlier reconciles still map other branches'
     mount-time ids onto the live ids they were reconciled into — clearing
     the whole table here would orphan every dynamic segment whose parent
     was renamed before this reconcile ran. Aliases pointing into the
     replaced subtree are dead by ownership though: a mount-time
     candidate id lives only inside the branch that produced it, and its
     target sits in that branch's live subtree, so entries targeting
     old_nodes die with the branch (their owning scopes were disposed
     above). Pruning them here keeps the table bounded by the live
     branches' candidate ids instead of growing on every remount. *)
  List.iter (remove_target_aliases application) old_nodes;
  Hashtbl.iter
    (fun candidate node ->
       if candidate <> node then
         set_alias application candidate node)
    mapping;
  Hashtbl.iter (fun _ owner -> Lui_virtual.Internal.remap owner (map_node mapping))
    application.runtime_virtual_owners;
  desired_roots

let reconcile_subtree application saved parent old_root candidate_root =
  match reconcile_forest application saved parent [old_root] [candidate_root] with
  | [root] -> root
  | _ -> assert false

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
  journal_replace application Mounted_nodes application.mounted_nodes node kind;
  journal_replace application Properties application.runtime_properties node Property_map.empty;
  journal_replace application Children application.runtime_children node Lui_sequence.empty;
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
  journal_replace application Extension_nodes application.runtime_extension_nodes node identifier;
  journal_replace application Extension_properties application.runtime_extension_properties node
    String_map.empty;
  journal_replace application Children application.runtime_children node Lui_sequence.empty;
  application.runtime_extension_dirty := true;
  enqueue
    application
    (create_extension_op node identifier
       (extension_wire_fingerprint application identifier
          (Lui_extension.fingerprint extension_schema)));
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
  journal_replace application Extension_nodes application.runtime_extension_nodes node identifier;
  journal_replace application Extension_properties application.runtime_extension_properties node
    String_map.empty;
  journal_replace application Children application.runtime_children node Lui_sequence.empty;
  application.runtime_extension_dirty := true;
  enqueue
    application
    (create_extension_op node identifier
       (extension_wire_fingerprint application identifier
          (Lui_extension.tweak_fingerprint extension_schema)));
  node

let set_reload_key application node key =
  let node = canonical_node application node in
  require_node application node;
  journal_replace application Reload_keys application.runtime_reload_keys node key

let children application node =
  match
    Hashtbl.find_opt application.runtime_children
      (canonical_node application node)
  with
  | Some children -> Lui_sequence.to_list children
  | None -> invalid_arg "unknown parent"

let rec created_subtree_ids application node acc =
  if not (pending_create_exists application node) then None
  else
    let acc = node :: acc in
    match Hashtbl.find_opt application.runtime_children node with
    | None -> Some acc
    | Some children ->
      let rec loop acc kids =
        match kids with
        | [] -> Some acc
        | child :: rest -> (
          match created_subtree_ids application child acc with
          | None -> None
          | Some acc -> loop acc rest)
      in
      loop acc (Lui_sequence.to_list children)

(* Drop a same-batch subtree by marking it: the flush-time replay prunes
   the group's ops and renumbers survivors around its slots. Returns
   false when a descendant is not a pending create, in which case the
   caller keeps the per-node ops for that node. *)
and mark_created_subtree application root =
  match created_subtree_ids application root [] with
  | None -> false
  | Some ids ->
    mark_elided_group application root ids;
    (match Hashtbl.find_opt application.runtime_parents root with
     | Some parent -> (
       try unlink_child application parent root
       with Invalid_argument _ ->
         journal_remove application Parents application.runtime_parents root)
     | None -> ());
    List.iter
      (fun id -> if id <> root then unmount_node application id) ids;
    journal_replace application Children application.runtime_children root Lui_sequence.empty;
    unmount_node application root;
    true

and drop_subtree application node =
  let node = canonical_node application node in
  if
    Hashtbl.mem application.mounted_nodes node
    || Hashtbl.mem application.runtime_extension_nodes node
  then
    if pending_create_exists application node then begin
      if not (mark_created_subtree application node) then
        (* some descendant is not a pending create: keep the per-node ops
           so each created node still marks itself for the replay *)
        drop_subtree_ops application node
    end
    else begin
      (* the detach op carries the unlink with it — the store drops the
         subtree whatever parent still records the root *)
      (match Hashtbl.find_opt application.runtime_parents node with
       | Some parent ->
           (try unlink_child application parent node
            with Invalid_argument _ ->
              journal_remove application Parents application.runtime_parents node)
       | None -> ());
      unmount_subtree application node;
      enqueue application (detach_subtree_op node)
    end

and drop_subtree_ops application node =
  let node = canonical_node application node in
  if
    Hashtbl.mem application.mounted_nodes node
    || Hashtbl.mem application.runtime_extension_nodes node
  then begin
    (* A branch teardown can reach a node the runtime already detached
       elsewhere (segment children get re-linked during reconciles and
       outer drops); detach it from whatever parent still records it
       instead of aborting the drop. *)
    (match Hashtbl.find_opt application.runtime_parents node with
     | Some parent ->
         (try remove_child application parent node
          with Invalid_argument _ ->
            journal_remove application Parents application.runtime_parents node)
     | None -> ());
    (match Hashtbl.find_opt application.runtime_children node with
     | Some children ->
         let kids = Lui_sequence.to_list children in
         journal_replace application Children application.runtime_children node Lui_sequence.empty;
         List.iter
           (fun child ->
              journal_remove application Parents application.runtime_parents child;
              enqueue application (remove_child_op node child);
              drop_subtree application child)
           kids;
     | None -> ());
    drop_node application node
  end

and unmount_subtree application node =
  (* local teardown of a whole subtree: same state teardown as
     drop_subtree but with the single detach op emitted by the caller *)
  (match Hashtbl.find_opt application.runtime_children node with
   | Some children ->
       List.iter
         (fun child ->
            journal_remove application Parents application.runtime_parents child;
            unmount_subtree application child)
         (Lui_sequence.to_list children)
   | None -> ());
  unmount_node application node

and unmount_node application node =
  (match Hashtbl.find_opt application.dynamic_segments node with
  | Some segments ->
    List.iter
      (fun segment -> journal_ref application Segment_active
        segment.dynamic_segment_id segment.dynamic_segment_active false)
      segments;
    application.runtime_dynamic_segment_count :=
      !(application.runtime_dynamic_segment_count) - List.length segments;
    journal_remove application Dynamic_segments application.dynamic_segments node
  | None -> ());
  (* Aliases targeting a dropped node belong to the branch that died
     with it; clearing them keeps the table bounded (they would resolve
     to a dead id anyway). *)
  remove_target_aliases application node;
  journal_remove application Mounted_nodes application.mounted_nodes node;
  journal_remove application Extension_nodes application.runtime_extension_nodes node;
  journal_remove application Properties application.runtime_properties node;
  journal_remove application Virtual_sources application.runtime_virtual_sources node;
  journal_remove application Virtual_owners application.runtime_virtual_owners node;
  journal_remove application Extension_properties application.runtime_extension_properties node;
  journal_remove application Children application.runtime_children node;
  journal_remove application Parents application.runtime_parents node;
  journal_remove application Reload_keys application.runtime_reload_keys node;
  put_echo application node { echo_text = None; echo_toggle = None; echo_value = None };
  application.runtime_extension_dirty := true

and drop_node application node =
  let node = canonical_node application node in
  require_node application node;
  if Hashtbl.mem application.runtime_parents node then
    invalid_arg "cannot drop an attached node";
  if children application node <> [] then
    invalid_arg "cannot drop a node with children";
  unmount_node application node;
  enqueue_drop application node

and unlink_child application parent child =
  let current = Hashtbl.find application.runtime_children parent in
  match Lui_sequence.index current child with
  | Some index ->
    journal_child ~parent application child;
    Hashtbl.replace application.runtime_children parent
      (Lui_sequence.remove current index);
    Hashtbl.remove application.runtime_parents child;
    application.runtime_extension_dirty := true
  | None -> invalid_arg "child is not attached to parent"

and remove_child application parent child =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  unlink_child application parent child;
  enqueue application (remove_child_op parent child)

let note_sent_echo application node property value =
  let state = echo_state application node in
  let state =
    match (property, value) with
    | TextValue, StringValue text -> { state with echo_text = Some text }
    | (Checked | Expanded | Selected), BoolValue flag ->
      { state with echo_toggle = Some flag }
    | (ProgressValue | FirstPaneWidth), FloatValue number ->
      { state with echo_value = Some number }
    | _ -> state
  in
  put_echo application node state

let note_removed_echo application node property =
  let state = echo_state application node in
  let state =
    match property with
    | TextValue -> { state with echo_text = None }
    | Checked | Expanded | Selected -> { state with echo_toggle = None }
    | ProgressValue | FirstPaneWidth -> { state with echo_value = None }
    | _ -> state
  in
  put_echo application node state

let note_reported_echo application node event =
  let state = echo_state application node in
  let state =
    match event with
    | TextChanged (_, text) -> { state with echo_text = Some text }
    | ToggleChanged (_, flag) -> { state with echo_toggle = Some flag }
    | ValueChanged (_, number) -> { state with echo_value = Some number }
    | _ -> state
  in
  put_echo application node state

let notify_segment_property application node property value =
  match Hashtbl.find_opt application.dynamic_segments node with
  | None -> ()
  | Some segments -> List.iter (fun segment ->
      if !(segment.dynamic_segment_active) then
        Option.iter (fun notify -> notify property value)
          !(segment.dynamic_segment_on_property)) segments

let ignored_property application property =
  Lui_wire_schema.property_web_only property &&
  match application.runtime_backend.backend_profile.profile_host with
  | SwiftUIHost | KotlinHost -> true
  | WebHost | GenericHost -> false

let set_prop application node property value =
  if ignored_property application property then () else begin
  let value = normalize_property_value property value in
  if property = FocusWithinEnabled then
    (match application.runtime_backend.backend_profile.profile_host with
     | WebHost -> ()
     | SwiftUIHost | KotlinHost | GenericHost ->
         invalid_arg "focus-within observation is unsupported by backend profile");
  let node = canonical_node application node in
  let kind = require_standard_node_kind application node in
  if property = ShrinkValue then
    (match application.runtime_backend.backend_profile.profile_host with
     | WebHost -> ()
     | GenericHost | SwiftUIHost | KotlinHost ->
         invalid_arg "shrink is unsupported by backend profile");
  if not (property_supported kind property) then
    invalid_arg
      (Printf.sprintf
         "property is unsupported by node kind: kind=%s prop=%s node=%d key=%s"
         (Lui_wire_schema.node_kind_name kind)
         (Lui_wire_schema.property_name property) node
         (Option.value
           (Hashtbl.find_opt application.runtime_reload_keys node)
           ~default:"-"));
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
    notify_segment_property application node property (Some value);
    (* A segment callback may have updated another property on this node. *)
    let current = Option.value
      (Hashtbl.find_opt application.runtime_properties node) ~default:Property_map.empty in
    journal_properties application node
      (Property_map.add property value current);
    note_sent_echo application node property value;
    enqueue application (set_prop_op node property value)
  end
  end

let remove_prop application node property =
  if ignored_property application property then () else begin
  let node = canonical_node application node in
  let kind = require_standard_node_kind application node in
  if not (property_supported kind property) then
    invalid_arg "property is unsupported by node kind";
  let current =
    match Hashtbl.find_opt application.runtime_properties node with
    | Some values -> values
    | None -> Property_map.empty
  in
  if Property_map.mem property current then begin
    notify_segment_property application node property None;
    let current = Option.value
      (Hashtbl.find_opt application.runtime_properties node) ~default:Property_map.empty in
    journal_properties application node
      (Property_map.remove property current);
    note_removed_echo application node property;
    enqueue application (remove_prop_op node property)
  end
  end

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
    journal_extension_properties application node
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
  journal_extension_properties application node
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

(* A node stays live while the runtime knows it — reconciles and restores
   rebuild [mounted_nodes] wholesale, so a cached node id can fall out of the
   table without [drop_node] ever running. Remount paths check this before
   re-linking children under a parent that is already gone. *)
let node_live application node =
  let node = canonical_node application node in
  Hashtbl.mem application.mounted_nodes node
  || Hashtbl.mem application.runtime_extension_nodes node

(* [node]'s currently recorded parent, canonicalized on both sides. A
   reconcile can re-home a live node under a different parent while the
   scope that mounted it still owns teardown: the recorded parent is how
   the runtime tells that node belongs to another branch now. *)
let recorded_parent application node =
  let node = canonical_node application node in
  match Hashtbl.find_opt application.runtime_parents node with
  | Some parent -> Some (canonical_node application parent)
  | None -> None

(* Check the proposed edge before mutating ownership. Standalone-only trees
   retain their existing nesting behavior. Shared rows contain ordinary content. *)
let validate_flat_virtual_insertion application parent child =
  if application.runtime_virtual_capabilities <> [] then begin
    let property node property =
      match Hashtbl.find_opt application.runtime_properties node with
      | Some properties -> Property_map.mem property properties
      | None -> false in
    let is_virtual node =
      Hashtbl.find_opt application.mounted_nodes node = Some VirtualList in
    let rec ancestors node =
      let virtual_row = is_virtual node in
      let shared_row = virtual_row && property node VirtualOwnerNode in
      let shared_owner = property node VirtualViewportEpoch in
      match Hashtbl.find_opt application.runtime_parents node with
      | None -> virtual_row, shared_row, shared_owner
      | Some parent ->
        let outer_virtual, outer_shared, outer_owner = ancestors parent in
        virtual_row || outer_virtual, shared_row || outer_shared,
        shared_owner || outer_owner in
    let under_virtual, under_shared, under_owner = ancestors parent in
    if under_virtual || under_owner then begin
      let rec validate node =
        if (under_virtual && is_virtual node
            && (under_shared || property node VirtualOwnerNode))
           || property node VirtualViewportEpoch then
          invalid_arg "shared virtual owners must be independent and their rows flat";
        List.iter validate (children application node) in
      validate child
    end
  end

let insert_child application parent child index =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  let current = Hashtbl.find application.runtime_children parent in
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
      invalid_arg
        (Printf.sprintf "unsupported child kind: parent=%s child=%s"
           (match
              ( Hashtbl.find_opt application.mounted_nodes parent,
                Hashtbl.find_opt application.runtime_extension_nodes parent )
            with
           | Some kind, _ -> Lui_wire_schema.node_kind_name kind
           | None, Some id -> "ext:" ^ id
           | None, None -> "?")
           (match
              ( Hashtbl.find_opt application.mounted_nodes child,
                Hashtbl.find_opt application.runtime_extension_nodes child )
            with
           | Some kind, _ -> Lui_wire_schema.node_kind_name kind
           | None, Some id -> "ext:" ^ id
           | None, None -> "?")));
  if Hashtbl.mem application.runtime_parents child then
    invalid_arg "child is already attached";
  if index < 0 || index > Lui_sequence.length current then
    invalid_arg "child index is out of bounds";
  if descendant application child parent then
    invalid_arg "child insertion would create a cycle";
  validate_flat_virtual_insertion application parent child;
  journal_child ~parent application child;
  Hashtbl.replace application.runtime_children parent (Lui_sequence.insert current index child);
  Hashtbl.replace application.runtime_parents child parent;
  application.runtime_extension_dirty := true;
  enqueue application (insert_child_op parent child index)

let remove_child_at application parent child index =
  let current = Hashtbl.find application.runtime_children parent in
  if Lui_sequence.get current index <> child then
    invalid_arg "child index does not match";
  journal_child ~parent application child;
  Hashtbl.replace application.runtime_children parent (Lui_sequence.remove current index);
  Hashtbl.remove application.runtime_parents child;
  application.runtime_extension_dirty := true;
  enqueue application (remove_child_op parent child)

let move_child_at application parent child current_index index =
  let current = Hashtbl.find application.runtime_children parent in
  if Lui_sequence.get current current_index <> child then
    invalid_arg "child index does not match";
  if index < 0 || index >= Lui_sequence.length current then
    invalid_arg "child index is out of bounds";
  journal_child ~parent application child;
  Hashtbl.replace application.runtime_children parent
    (Lui_sequence.insert (Lui_sequence.remove current current_index) index child);
  application.runtime_extension_dirty := true;
  enqueue application (move_child_op parent child index)

let move_child application parent child index =
  let parent = canonical_node application parent in
  let child = canonical_node application child in
  require_node application parent;
  require_node application child;
  let current = children application parent in
  (match find_child_index current child with
  | Some current_index ->
    move_child_at application parent child current_index index
  | None -> invalid_arg "child is not attached to parent")

(* A bound-property observer enqueued in the current stabilization round can
   outlive its node: a dyn remount dropped mid-round disposes the scope lazily,
   so the callback still fires on a stale id. Live nodes keep their writes;
   dropped ones are skipped rather than failing on the host's behalf. *)
let bind_prop_map ?(protect = fun action -> action ()) scope application node property convert source =
  Signal.own scope
    (Signal.observe source (fun value ->
         protect (fun () ->
           if node_live application node then
             set_prop application node property (convert value))))

let bind_prop ?protect scope application node property source =
  bind_prop_map ?protect scope application node property Fun.id source

let bind_extension_prop ?(protect = fun action -> action ()) scope application node property source =
  Signal.own scope
    (Signal.observe source (fun value ->
         protect (fun () ->
           if node_live application node then
             set_extension_prop application node property value)))

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
    journal_member application Handler_member application.event_handlers node
      (fun handler -> handler.handler_id) handler_id;
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
  journal_member ~new_member:true application Handler_member application.event_handlers node
    (fun handler -> handler.handler_id) handler_id;
  Hashtbl.replace application.event_handlers node (handlers @ [ handler ]);
  incr application.runtime_handler_count;
  Signal.on_dispose scope
    (fun () -> remove_handler application node handler_id)

(* A change event is an echo only when it repeats the value last sent to the
   host or last delivered to handlers. Unset channels use the platform
   default ("" / false / 0.0) so a freshly mounted control re-reporting that
   default is suppressed, but a later edit back to the default is not. *)
let event_is_value_echo application node event =
  let state = echo_state application node in
  match event with
  | TextChanged (_, text) ->
    (match state.echo_text with Some current -> current = text | None -> text = "")
  | ToggleChanged (_, checked_value) ->
    (match state.echo_toggle with
    | Some current -> current = checked_value
    | None -> not checked_value)
  | ValueChanged (_, value) ->
    (match state.echo_value with
    | Some current -> current = value
    | None -> value = 0.0)
  | _ -> false

let dispatch application event =
  let node = canonical_node application (event_node event) in
  if not (node_live application node) then
    (* a DOM element can receive an in-flight event after being unmounted
       mid-dispatch (e.g. a capture-phase handler re-renders); ignore it *)
    false
  else
    let suppressed =
      match event with
    | ExtensionEvent (_event_node, identifier, name, values) ->
      let extension_schema = require_extension_schema application node in
      if identifier <> extension_schema.extension_identifier then
        invalid_arg "extension event identifier mismatch";
      if
        not
          (Lui_extension.event_payload_supported extension_schema name
             values)
      then invalid_arg "invalid extension event payload";
      false
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
      then invalid_arg "event is unsupported by node kind";
      event_is_value_echo application node event
  in
  if suppressed then true
  else begin
    note_reported_echo application node event;
    match Hashtbl.find_opt application.event_handlers node with
    | Some handlers ->
      List.iter
        (fun handler ->
           Signal.enqueue_effect application.runtime_scheduler (fun () ->
               let current = Option.value
                 (Hashtbl.find_opt application.event_handlers node) ~default:[] in
               if node_live application node
                  && List.exists (fun registered -> registered == handler) current
               then handler.handler_callback event))
        handlers;
      true
    | None -> true
  end

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

let virtual_source_property = function
  | VirtualTotalCount | VirtualGeneration | VirtualIndices | VirtualScrollIndex
  | VirtualOwnerNode | VirtualOwnerEpoch | VirtualRowKeys -> true
  | _ -> false

let validate_virtual_list application node =
  let node = canonical_node application node in
  if Hashtbl.find_opt application.mounted_nodes node = Some VirtualList then begin
    let children = children application node in
    (match Hashtbl.find_opt application.dynamic_segments node with
     | Some segments -> List.iter (fun segment ->
         if segment.dynamic_segment_exclusive
            && (List.length segments <> 1
                || !(segment.dynamic_segment_base) <> 0
                || !(segment.dynamic_segment_size) <> List.length children) then
           invalid_arg "virtual_rows must exclusively own the virtual-list children") segments
     | None -> ());
    let values = Option.value
      (Hashtbl.find_opt application.runtime_properties node) ~default:Property_map.empty in
    let metadata = [VirtualTotalCount; VirtualGeneration; VirtualIndices; VirtualScrollIndex] in
    if List.exists (fun property -> Property_map.mem property values) metadata then begin
      let integer property = match Property_map.find_opt property values with
        | Some (IntValue value) -> value
        | _ -> invalid_arg "virtual-list source metadata is incomplete" in
      let total = integer VirtualTotalCount in
      let generation = integer VirtualGeneration in
      let target = match Property_map.find_opt VirtualScrollIndex values with
        | None -> None
        | Some (IntValue value) -> Some value
        | Some _ -> invalid_arg "invalid virtual-list scroll index" in
      let indices = match Property_map.find_opt VirtualIndices values with
        | Some (StringValue encoded) ->
          (match virtual_indices_of_string encoded with
           | Some indices -> indices
           | None -> invalid_arg "invalid virtual-list sparse indices")
        | _ -> invalid_arg "virtual-list source metadata is incomplete" in
      if total < 0 || generation <= 0
         || Option.fold ~none:false ~some:(fun target -> target < -1 || target >= total) target
         || List.length indices <> List.length children
         || List.exists (fun index -> index >= total) indices then
        invalid_arg "virtual-list source metadata does not match its children"
    end
  end

let validate_virtual_list_operations application operations =
  let parents = Hashtbl.create 4 in
  List.iter (function
    | SetProp (node, property, _) | RemoveProp (node, property)
      when virtual_source_property property -> Hashtbl.replace parents node ()
    | InsertChild (parent, _, _) | RemoveChild (parent, _) | MoveChild (parent, _, _) ->
      Hashtbl.replace parents parent ()
    | _ -> ()) operations;
  Hashtbl.iter (fun parent () -> validate_virtual_list application parent) parents

let validate_shared_virtual application operations =
  let shared_property = function
    | VirtualViewportEpoch | VirtualRetentions | VirtualRetentionReleases
    | VirtualOwnerNode | VirtualOwnerEpoch | VirtualRowKeys -> true
    | _ -> false in
  if application.runtime_virtual_capabilities = [] then
    (* Standalone updates must stay proportional to their dirty scope. *)
    List.iter (function
      | SetProp (_, property, _) when shared_property property ->
        invalid_arg "shared virtual viewport capability was not negotiated"
      | _ -> ()) operations
  else begin
  let open Lui_virtual_json in
  let values node = Option.value
    (Hashtbl.find_opt application.runtime_properties node) ~default:Property_map.empty in
  let integer properties property = match Property_map.find_opt property properties with
    | Some (IntValue value) when value > 0 -> value
    | _ -> invalid_arg "incomplete shared virtual binding" in
  let encoded properties property = match Property_map.find_opt property properties with
    | Some (StringValue value) -> value
    | _ -> invalid_arg "incomplete shared virtual metadata" in
  let rec descendant node ancestor =
    node = ancestor || match Hashtbl.find_opt application.runtime_parents node with
      | Some parent -> descendant parent ancestor
      | None -> false in
  let sources = Hashtbl.create 8 in
  let enabled () =
    if not (List.mem Lui_virtual.Shared_viewport_retention_v1 application.runtime_virtual_capabilities) then
      invalid_arg "shared virtual viewport capability was not negotiated" in
  Hashtbl.iter (fun node properties ->
    if List.exists (fun property -> Property_map.mem property properties)
        [VirtualViewportEpoch; VirtualRetentions; VirtualRetentionReleases] then begin
      enabled ();
      Option.iter (fun parent -> validate_flat_virtual_insertion application parent node)
        (Hashtbl.find_opt application.runtime_parents node);
      ignore (integer properties VirtualViewportEpoch);
      let tickets = Hashtbl.create 8 in
      List.iter (fun record ->
        let fields = object_ ["ticket"; "key"] record in
        let ticket = positive (List.assoc "ticket" fields) in
        if Hashtbl.mem tickets ticket then fail ();
        Hashtbl.add tickets ticket ();
        ignore (nonempty (string (List.assoc "key" fields))))
        (array (decode (encoded properties VirtualRetentions)));
      let releases = Hashtbl.create 8 in
      List.iter (fun record ->
        let fields = object_ ["ticket"; "receipt"] record in
        let ticket = positive (List.assoc "ticket" fields) in
        if not (Hashtbl.mem tickets ticket) || Hashtbl.mem releases ticket then fail ();
        Hashtbl.add releases ticket ();
        let receipt = object_ ["version"; "status"; "owner"; "epoch"; "ticket";
          "proof"; "rows"; "geometry"; "pins"; "requirements"]
          (decode (string (List.assoc "receipt" fields))) in
        if List.assoc "owner" receipt <> Int node
           || List.assoc "ticket" receipt <> Int ticket
           || List.assoc "epoch" receipt <> Int (integer properties VirtualViewportEpoch)
        then fail ();
        (match array (List.assoc "rows" receipt) with
         | [_] -> ()
         | _ -> fail ())) (array (decode (encoded properties VirtualRetentionReleases)))
    end;
    if List.exists (fun property -> Property_map.mem property properties)
        [VirtualOwnerNode; VirtualOwnerEpoch; VirtualRowKeys] then begin
      enabled ();
      let owner = integer properties VirtualOwnerNode in
      let epoch = integer properties VirtualOwnerEpoch in
      if Hashtbl.find_opt application.mounted_nodes owner <> Some Scroll
         || integer (values owner) VirtualViewportEpoch <> epoch
         || not (descendant node owner) then
        invalid_arg "shared virtual source is outside its bound owner";
      if Hashtbl.find_opt application.mounted_nodes node <> Some VirtualList then
        invalid_arg "shared virtual source must bind a virtual-list";
      if Hashtbl.mem sources owner then
        invalid_arg "shared virtual owner permits only one source list";
      Hashtbl.add sources owner node;
      Option.iter (fun parent -> validate_flat_virtual_insertion application parent node)
        (Hashtbl.find_opt application.runtime_parents node);
      let keys = vector (encoded properties VirtualRowKeys) in
      if List.length keys <> List.length (children application node)
         || not (Property_map.mem VirtualGeneration properties) then
        invalid_arg "shared virtual row keys do not match sparse children";
      validate_virtual_list application node
    end) application.runtime_properties;
  Hashtbl.iter (fun _ source ->
    List.iter (fun child -> validate_flat_virtual_insertion application source child)
      (children application source)) sources
  end

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

(* Exceptions consume the uncertain generation. Rejection instead schedules
   an authoritative snapshot under the generation the host still expects. *)
let apply_pending_batch application batch operation_count next_generation =
  let roots = List.fold_left (fun roots -> function
    | CreateNode (node, _) | CreateExtension (node, _, _)
    | RemoveChild (_, node) -> Root_set.add node roots
    | InsertChild (_, node, _) | DropNode node | DetachSubtree node ->
        Root_set.remove node roots
    | _ -> roots) !(application.runtime_host_roots) batch.ops in
  let committed =
    try application.runtime_backend.apply_batch batch
    with failure ->
      application.runtime_generation := next_generation;
      ignore (record_diagnostics application Rejected operation_count
        (List.length !(application.pending_ops)));
      raise failure
  in
  if committed then begin
    application.runtime_host_roots := roots;
    application.runtime_generation := next_generation;
    record_diagnostics application Applied operation_count 0
  end
  else begin
    application.runtime_resync_required := true;
    ignore (record_diagnostics application Rejected operation_count 0);
    invalid_arg "backend rejected patch batch"
  end

(* Receipt observers can synchronously cancel, release or dispose scopes.
   Publish only after signal-driven transactions have committed or rolled back,
   then settle any work the observers queued before serializing the batch. *)
let publish_virtual_receipts application =
  let pending = Hashtbl.fold (fun node owner pending -> (node, owner) :: pending)
    application.runtime_virtual_receipts [] in
  journal_clear application Virtual_receipts application.runtime_virtual_receipts;
  let rec publish = function
    | [] -> ()
    | (_, owner) :: rest as pending ->
      (try Lui_virtual.Internal.flush_receipts owner with failure ->
        List.iter (fun (node, owner) ->
          journal_replace application Virtual_receipts application.runtime_virtual_receipts node owner) pending;
        raise failure);
      publish rest in
  publish pending

let rec stabilize application =
  match Signal.stabilize application.runtime_scheduler with
  | () ->
    if Hashtbl.length application.runtime_virtual_receipts > 0 then begin
      publish_virtual_receipts application;
      stabilize application
    end
  | exception failure ->
    (* A retirement callback may fail after structural ownership committed.
       Its committed source snapshot still revokes old native proofs. *)
    publish_virtual_receipts application;
    raise failure

let normalize_pending_sizes application =
  let nodes = Hashtbl.create 8 in
  if !(application.runtime_resync_required) then
    Hashtbl.iter (fun node _ -> Hashtbl.replace nodes node ()) application.runtime_properties
  else
    List.iter (function
      | SetProp (node, property, _) | RemoveProp (node, property)
        when List.mem property size_properties -> Hashtbl.replace nodes node ()
      | _ -> ()) !(application.pending_ops);
  Hashtbl.iter (fun node () ->
    match Hashtbl.find_opt application.runtime_properties node with
    | None -> ()
    | Some properties ->
        let normalized = normalize_size_properties properties in
        List.iter (fun property ->
          match Property_map.find_opt property normalized with
          | Some value when Property_map.find_opt property properties <> Some value ->
              set_prop application node property value
          | _ -> ()) size_properties) nodes

let rec flush application =
  if !(application.runtime_flushing) then begin
    application.runtime_flush_dirty := true;
    true
  end
  else begin
    application.runtime_flushing := true;
    let flushed =
      try
        stabilize application;
        normalize_pending_sizes application;
        if !(application.runtime_extension_dirty) then begin
          validate_extension_nodes application;
          application.runtime_extension_dirty := false
        end;
        let recovering = !(application.runtime_resync_required) in
        let operations =
          if recovering then begin
            if Hashtbl.length application.elision_ghosts > 0 then
              ignore (elide_pending_ops application);
            List.rev_append
              (List.rev_map (fun node -> DetachSubtree node)
                (Root_set.elements !(application.runtime_host_roots)))
              (resync_batch application).ops
          end
          else if Hashtbl.length application.elision_ghosts = 0 then
            List.rev !(application.pending_ops)
          else elide_pending_ops application
        in
        validate_virtual_list_operations application operations;
        validate_shared_virtual application operations;
        (* detach before apply: ops queued while the backend applies
           this batch (emits re-entering through event dispatch) land
           in the next batch instead of being re-sent under a stale
           generation *)
        application.pending_ops := [];
        journal_clear application Pending_creates application.pending_creates;
        if operations = [] && not recovering then record_diagnostics application NoBatch 0 0
        else begin
          let next_generation = !(application.runtime_generation) + 1 in
          let batch = { generation = next_generation; ops = operations } in
          application.runtime_resync_required := false;
          apply_pending_batch application batch (List.length operations)
            next_generation
        end
      with e ->
        compact_boundary_journal application;
        application.runtime_flushing := false;
        raise e
    in
    compact_boundary_journal application;
    application.runtime_flushing := false;
    if !(application.runtime_flush_dirty) then begin
      application.runtime_flush_dirty := false;
      flush application
    end
    else flushed
  end

let diagnostics application = !(application.runtime_diagnostics)

let generation application = !(application.runtime_generation)

let child_count application node =
  Lui_sequence.length (Hashtbl.find application.runtime_children (canonical_node application node))

let find_dynamic_segment_index segments segment_id =
  let rec loop segments index =
    match segments with
    | [] -> None
    | head :: rest ->
      if segment_id = head.dynamic_segment_id then Some index
      else loop rest (index + 1)
  in
  loop segments 0

let rec dynamic_segment_contains owner segment =
  segment == owner || match segment.dynamic_segment_owner with
  | None -> false
  | Some parent -> dynamic_segment_contains owner parent

let register_dynamic_segment ?owner ?(exclusive = false) application parent =
  let parent = canonical_node application parent in
  require_node application parent;
  let current = Option.value
    (Hashtbl.find_opt application.dynamic_segments parent) ~default:[] in
  if List.exists (fun segment -> segment.dynamic_segment_exclusive) current then
    invalid_arg "virtual_rows must be the sole dynamic owner";
  if exclusive
     && (Hashtbl.find_opt application.mounted_nodes parent <> Some VirtualList
         || current <> [] || child_count application parent <> 0) then
    invalid_arg "virtual_rows requires an empty virtual-list parent";
  let segment =
    {
      dynamic_segment_id =
        (incr application.next_dynamic_segment_id;
         !(application.next_dynamic_segment_id));
      dynamic_segment_parent = parent;
      dynamic_segment_owner = owner;
      dynamic_segment_base = ref (match owner with None -> child_count application parent
        | Some owner -> !(owner.dynamic_segment_base) + !(owner.dynamic_segment_size));
      dynamic_segment_size = ref 0;
      dynamic_segment_active = ref true;
      dynamic_segment_exclusive = exclusive;
      dynamic_segment_on_property = ref None;
    }
  in
  let current =
    match Hashtbl.find_opt application.dynamic_segments parent with
    | Some segments -> segments
    | None -> []
  in
  (* Registrations run in reverse document order so appending within the
     last owner's range shares all preceding registrations. *)
  let registered = match owner with
    | None -> segment :: current
    | Some owner ->
      let rec seek = function
        | [] -> invalid_arg "dynamic range owner is not registered"
        | current :: rest as all -> if dynamic_segment_contains owner current then segment :: all
          else current :: seek rest in
      seek current in
  journal_member ~new_member:true application Segment_member application.dynamic_segments parent
    (fun segment -> segment.dynamic_segment_id) segment.dynamic_segment_id;
  Hashtbl.replace application.dynamic_segments parent registered;
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

(* A reconcile can rekey a segment's registration onto the node its parent
   was remapped to while the owning scope still disposes lazily, and the
   candidate alias may already be pruned. When the recorded parent no longer
   finds the entry, fall back to a table scan so the bookkeeping still
   unwinds. *)
let scan_segment_registration application segment =
  let found = ref None in
  Hashtbl.iter
    (fun _key segments ->
       match !found with
       | Some _ -> ()
       | None ->
         (match
            find_dynamic_segment_index segments segment.dynamic_segment_id
          with
          | Some index -> found := Some (segments, index)
          | None -> ()))
    application.dynamic_segments;
  !found

let segment_registration application segment =
  let parent =
    canonical_node application segment.dynamic_segment_parent
  in
  match Hashtbl.find_opt application.dynamic_segments parent with
  | Some segments ->
    (match
       find_dynamic_segment_index segments segment.dynamic_segment_id
     with
     | Some index -> Some (segments, index)
     | None -> scan_segment_registration application segment)
  | None -> scan_segment_registration application segment

let resize_dynamic_segment application segment delta =
  if not !(segment.dynamic_segment_active) then
    invalid_arg "dynamic segment is inactive";
  let segments, segment_index =
    match segment_registration application segment with
    | Some (segments, index) -> segments, index
    | None -> invalid_arg "dynamic segment is not registered"
  in
  let next_size = !(segment.dynamic_segment_size) + delta in
  if next_size < 0 then
    invalid_arg "dynamic segment size cannot be negative";
  journal_ref application Segment_size segment.dynamic_segment_id segment.dynamic_segment_size next_size;
  let rec resize_owner = function
    | None -> ()
    | Some owner ->
      journal_ref application Segment_size owner.dynamic_segment_id owner.dynamic_segment_size
        (!(owner.dynamic_segment_size) + delta);
      resize_owner owner.dynamic_segment_owner in
  resize_owner segment.dynamic_segment_owner;
  List.iteri
    (fun index current ->
       if index < segment_index && not (dynamic_segment_contains segment current) then
         journal_ref application Segment_base current.dynamic_segment_id current.dynamic_segment_base
           (!(current.dynamic_segment_base) + delta))
    segments

(* Teardown counterpart of [resize_dynamic_segment]: the registration can
   already be gone entirely (an outer reconcile dropped or rekeyed the
   parent entry, or a restore rolled the table back). Sibling bases are
   moot then, but the segment's own size still unwinds so
   [unregister_dynamic_segment] sees an empty segment. *)
let release_dynamic_segment application segment =
  if !(segment.dynamic_segment_active) then
    match segment_registration application segment with
    | Some _ -> resize_dynamic_segment application segment (-1)
    | None ->
      journal_ref application Segment_size segment.dynamic_segment_id segment.dynamic_segment_size
        (max 0 (!(segment.dynamic_segment_size) - 1))

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
      journal_member application Segment_member application.dynamic_segments parent
        (fun segment -> segment.dynamic_segment_id) segment.dynamic_segment_id;
      if remaining = [] then Hashtbl.remove application.dynamic_segments parent
      else Hashtbl.replace application.dynamic_segments parent remaining;
      if List.length remaining < List.length segments then
        decr application.runtime_dynamic_segment_count
    | None ->
      (* The parent key may no longer find the entry (rekeyed by a
         reconcile); remove by segment id wherever it lives. *)
      let found_key = ref None in
      Hashtbl.iter
        (fun key segments ->
           if
             List.exists
               (fun current ->
                  current.dynamic_segment_id
                  = segment.dynamic_segment_id)
               segments
           then found_key := Some key)
        application.dynamic_segments;
      (match !found_key with
       | Some key ->
         (match Hashtbl.find_opt application.dynamic_segments key with
          | Some segments ->
            let remaining =
              List.filter
                (fun current ->
                   current.dynamic_segment_id
                   <> segment.dynamic_segment_id)
                segments
            in
            journal_member application Segment_member application.dynamic_segments key
              (fun segment -> segment.dynamic_segment_id) segment.dynamic_segment_id;
            if remaining = [] then Hashtbl.remove application.dynamic_segments key
            else Hashtbl.replace application.dynamic_segments key remaining;
            decr application.runtime_dynamic_segment_count
          | None -> ())
       | None -> ()));
    journal_ref application Segment_active segment.dynamic_segment_id segment.dynamic_segment_active false
  end
