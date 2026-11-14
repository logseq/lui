module Json = Lui_virtual_json

type binding = { node : int; lease : int }
type release_error = Stale_receipt | Owner_retired | Unsupported
type capability = Shared_viewport_retention_v1
type receipt_status = Pinned | Focused | Released | Stale | Missing_target | Retired
type row = { source_node : int; generation : int; row_node : int; incarnation : int }
type native_receipt = {
  envelope : string; owner_node : int; epoch : int;
  ticket_id : int; proof : int; row : row; geometry : int; pins : int;
  requirements : string list;
}
(* SDK refusals carry no invented native proof or wire envelope. *)
type receipt = { status : receipt_status; native : native_receipt option }
type owner = {
  scheduler : Signal.scheduler;
  mutable retired : bool;
  mutable serial : int;
  mutable owner_binding : binding option;
  mutable publisher : (int -> string -> string -> unit) option;
  mutable schedule_receipts : (unit -> unit) option;
  mutable receipts_dirty : bool;
  mutable replacing_owner : int option;
  mutable root : source option;
  tickets : (int, retention) Hashtbl.t;
}
and source = {
  owner : owner; root_key : string;
  binding_state : binding option Signal.state;
  mutable bound : binding option;
  mutable owner_epoch : int;
  mutable generation : int;
  mutable rows : (string * int) list;
  mutable contains : (string -> bool) option;
  mutable listeners : (int * (unit -> unit)) list;
  mutable adopt : int list -> unit;
  mutable replacing_source : int option;
}
and retention = {
  source : source; key : string; id : int;
  receipt_state : receipt option Signal.state;
  mutable latest : receipt option;
  mutable releasing : receipt option;
  mutable active : bool;
}

let shared_viewport_version = 1
let supports host Shared_viewport_retention_v1 = host = Lui_protocol.SwiftUIHost
let fresh owner =
  if owner.serial = max_int then invalid_arg "shared virtual identity overflow";
  owner.serial <- owner.serial + 1;
  owner.serial
let live owner = if owner.retired then invalid_arg "shared virtual owner retired"
let create_owner () = {
  scheduler = Signal.scheduler (); retired = false; serial = 0;
  owner_binding = None; publisher = None; schedule_receipts = None;
  receipts_dirty = false; root = None;
  replacing_owner = None;
  tickets = Hashtbl.create 8;
}
let publish_state owner state value =
  Signal.set state value;
  Signal.stabilize owner.scheduler
let set_receipt retention value =
  retention.latest <- value;
  publish_state retention.source.owner retention.receipt_state value
let tickets owner = Hashtbl.fold (fun _ ticket result ->
  if ticket.active then ticket :: result else result) owner.tickets []
  |> List.sort (fun a b -> Int.compare a.id b.id)
let publish owner =
  Option.iter (fun publish ->
    let retained = List.map (fun retention -> Json.Object [
      "ticket", Json.Int retention.id;
      "key", Json.String retention.key]) (tickets owner) in
    let releases = List.filter_map (fun retention -> Option.map (fun receipt ->
      Json.Object ["ticket", Json.Int retention.id; "receipt", Json.String (Option.get receipt.native).envelope])
      retention.releasing) (tickets owner) in
    match owner.owner_binding with
    | None -> ()
    | Some binding -> publish binding.lease (Json.encode (Json.Array retained))
        (Json.encode (Json.Array releases))) owner.publisher
let notify owner =
  publish owner;
  Option.iter (fun source ->
    List.iter (fun (_, notify) -> notify ()) source.listeners) owner.root
let root_source owner ~key =
  live owner;
  let key = Json.nonempty key in
  match owner.root with
  | Some source when source.root_key = key -> source
  | Some _ -> invalid_arg "shared virtual owner permits only one root source"
  | None ->
    let source = { owner; root_key = key; binding_state = Signal.state owner.scheduler None;
      bound = None; owner_epoch = 0; generation = 0; rows = []; contains = None;
      listeners = []; adopt = (fun _ -> ());
      replacing_source = None } in
    owner.root <- Some source; source
let binding source = Signal.value source.binding_state
let ticket retention = retention.id
let receipt retention = Signal.value retention.receipt_state
let receipt_status receipt = receipt.status
let cancel_retention retention =
  if retention.active then begin
    retention.active <- false; retention.releasing <- None;
    Hashtbl.remove retention.source.owner.tickets retention.id;
    set_receipt retention None;
    Signal.dispose_signal (receipt retention);
    notify retention.source.owner
  end
let dispose_owner owner =
  if not owner.retired then begin
    owner.retired <- true;
    Hashtbl.iter (fun _ retention ->
      retention.active <- false; retention.releasing <- None; set_receipt retention None;
      Signal.dispose_signal (receipt retention)) owner.tickets;
    Hashtbl.clear owner.tickets;
    (* Clear native obligations while the owner publisher is still bound. *)
    notify owner;
    owner.owner_binding <- None; owner.publisher <- None; owner.schedule_receipts <- None;
    Option.iter (fun source ->
      source.bound <- None; source.generation <- 0; source.rows <- []; source.contains <- None;
      publish_state owner source.binding_state None;
      Signal.dispose_signal (binding source);
      source.listeners <- []; source.adopt <- (fun _ -> ())) owner.root
  end

let current_row retention =
  let source = retention.source in
  let bound = Option.get source.bound in
  if source.owner_epoch <> (Option.get source.owner.owner_binding).lease then raise Not_found;
  bound.node, source.generation, List.assoc retention.key source.rows
let current retention receipt =
  let owner = retention.source.owner in
  match owner.owner_binding with
  | Some bound when retention.active && not owner.retired
      && bound.node = receipt.owner_node && bound.lease = receipt.epoch
      && retention.id = receipt.ticket_id ->
    (try (receipt.row.source_node, receipt.row.generation, receipt.row.row_node)
       = current_row retention && receipt.row.incarnation > 0
     with Not_found | Invalid_argument _ -> false)
  | _ -> false
let refresh_receipts owner =
  let changed = ref false in
  List.iter (fun retention ->
    let source = retention.source in
    let missing = match source.bound, owner.owner_binding with
      | Some _, Some owner when source.generation > 0 && source.owner_epoch = owner.lease ->
        Option.fold ~none:false ~some:(fun contains -> not (contains retention.key)) source.contains
      | _ -> false in
    let refused = if missing then Some Missing_target else
      match retention.latest with
      | Some { status = (Pinned | Focused); native = Some proof } when not (current retention proof) -> Some Stale
      | _ -> None in
    match refused with
    | None -> ()
    | Some status ->
      if Option.is_some retention.releasing then begin
        retention.releasing <- None; changed := true
      end;
      if Option.map (fun receipt -> receipt.status) retention.latest <> Some status then
        set_receipt retention (Some {status;
          native = Option.bind retention.latest (fun receipt -> receipt.native)})) (tickets owner);
  if !changed then publish owner
let retain source ~key =
  live source.owner;
  let retention = { source; key = Json.nonempty key; id = fresh source.owner;
    receipt_state = Signal.state source.owner.scheduler None; latest = None;
    releasing = None; active = true } in
  Hashtbl.add source.owner.tickets retention.id retention;
  (* A staged source snapshot is not authoritative to observers until its
     runtime transaction has committed. Already committed snapshots can still
     answer a new retention synchronously. *)
  if not source.owner.receipts_dirty then refresh_receipts source.owner;
  notify source.owner;
  retention
let request_release retention receipt =
  if retention.source.owner.retired then Error Owner_retired
  else if retention.source.owner.owner_binding = None then Error Unsupported
  else if not (Option.fold ~none:false ~some:(current retention) receipt.native)
      || not (receipt.status = Pinned || receipt.status = Focused)
      || not (Option.fold ~none:false ~some:(fun latest -> latest == receipt) retention.latest)
  then Error Stale_receipt
  else begin
    retention.releasing <- Some receipt;
    notify retention.source.owner;
    Ok ()
  end

let decode_receipt envelope =
  let fields = Json.object_ ["version"; "status"; "owner"; "epoch"; "ticket";
    "proof"; "rows"; "geometry"; "pins"; "requirements"] (Json.decode envelope) in
  let field key = List.assoc key fields in
  if field "version" <> Json.Int 1 then invalid_arg "unsupported virtual receipt version";
  let status = match Json.string (field "status") with
    | "pinned" -> Pinned | "focused" -> Focused | "released" -> Released
    | "stale" -> Stale | "missing-target" -> Missing_target | "owner-retired" -> Retired
    | _ -> invalid_arg "invalid virtual receipt status" in
  let row = match Json.array (field "rows") with
  | [row] ->
    let fields = Json.object_ ["source"; "generation"; "row"; "incarnation"] row in
    let positive name = Json.positive (List.assoc name fields) in
    {source_node = positive "source"; generation = positive "generation";
      row_node = positive "row"; incarnation = positive "incarnation"}
  | _ -> invalid_arg "flat virtual receipt requires exactly one row" in
  let requirements = Json.strings (field "requirements") in
  if List.sort_uniq String.compare requirements <> List.sort String.compare requirements
     || List.exists (fun requirement -> not (List.mem requirement ["attached"; "visible"; "focus"])) requirements
  then invalid_arg "invalid virtual receipt requirements";
  {status; native = Some {envelope; owner_node = Json.positive (field "owner"); epoch = Json.positive (field "epoch");
   ticket_id = Json.positive (field "ticket"); proof = Json.positive (field "proof"); row;
   geometry = Json.positive (field "geometry"); pins = Json.positive (field "pins"); requirements}}

module Internal = struct
  let stage_receipts owner =
    owner.receipts_dirty <- true;
    Option.iter (fun schedule -> schedule ()) owner.schedule_receipts
  let flush_receipts owner =
    if owner.receipts_dirty then begin
      owner.receipts_dirty <- false;
      try refresh_receipts owner with failure ->
        stage_receipts owner;
        raise failure
    end
  let bind_owner owner ~node ~publish ~schedule_receipts =
    live owner;
    if Option.fold ~none:false ~some:(fun bound -> owner.replacing_owner <> Some bound.lease)
      owner.owner_binding then invalid_arg "shared virtual owner already bound";
    let binding = {node; lease = fresh owner} in
    owner.owner_binding <- Some binding; owner.publisher <- Some publish;
    owner.schedule_receipts <- Some schedule_receipts;
    stage_receipts owner;
    notify owner; binding
  let unbind_owner owner binding =
    if Option.fold ~none:false ~some:(fun current -> current.lease = binding.lease) owner.owner_binding then begin
      owner.owner_binding <- None; owner.publisher <- None;
      stage_receipts owner;
      owner.schedule_receipts <- None;
      Option.iter (fun source ->
        source.bound <- None; source.generation <- 0; source.rows <- []; source.contains <- None;
        source.adopt <- (fun _ -> ());
        publish_state owner source.binding_state None) owner.root;
      true
    end else false
  let bind_source source ~node ~owner_node =
    live source.owner;
    if Option.fold ~none:false ~some:(fun bound -> source.replacing_source <> Some bound.lease)
      source.bound then invalid_arg "shared virtual source already bound";
    (match source.owner.owner_binding with
     | Some owner when owner.node = owner_node -> source.owner_epoch <- owner.lease
     | _ -> invalid_arg "shared virtual source requires its bound owner");
    let bound = {node; lease = fresh source.owner} in
    source.bound <- Some bound; source.generation <- 0; source.rows <- []; source.contains <- None;
    stage_receipts source.owner;
    publish_state source.owner source.binding_state (Some bound);
    bound
  let unbind_source source binding =
    if Option.fold ~none:false ~some:(fun current -> current.lease = binding.lease) source.bound then begin
      source.bound <- None; source.generation <- 0; source.rows <- []; source.contains <- None;
      source.adopt <- (fun _ -> ());
      publish_state source.owner source.binding_state None;
      stage_receipts source.owner;
      true
    end else false
  let owner_binding source = source.owner.owner_binding
  let retained_keys source =
    List.map (fun retention -> retention.key) (tickets source.owner)
    |> List.sort_uniq String.compare
  let on_change source notify =
    let id = fresh source.owner in
    source.listeners <- (id, notify) :: source.listeners;
    fun () -> source.listeners <- List.filter (fun (other, _) -> other <> id) source.listeners
  let commit_rows source ~lease ~generation ~contains rows =
    match source.bound, source.owner.owner_binding with
    | Some bound, Some owner when bound.lease = lease && source.owner_epoch = owner.lease
        && generation >= source.generation ->
      source.generation <- generation; source.rows <- rows; source.contains <- Some contains;
      stage_receipts source.owner
    | _ -> ()
  let adopt_pins source ~node adopt =
    match source.bound with
    | Some bound when bound.node = node ->
      source.adopt <- adopt;
      fun () -> if Option.fold ~none:false
        ~some:(fun current -> current.lease = bound.lease) source.bound then
          source.adopt <- (fun _ -> ())
    | _ -> (fun () -> ())
  let remap owner node =
    let binding current = Option.map
      (fun bound -> {bound with node = node bound.node}) current in
    owner.owner_binding <- binding owner.owner_binding;
    Option.iter (fun source ->
      let previous = source.bound in
      source.bound <- binding source.bound;
      source.rows <- List.map (fun (key, row) -> key, node row) source.rows;
      if source.bound <> previous then publish_state owner source.binding_state source.bound) owner.root
  let replacing_owner owner =
    let previous = owner.replacing_owner in
    owner.replacing_owner <- Option.map (fun bound -> bound.lease) owner.owner_binding;
    fun () -> owner.replacing_owner <- previous
  let replacing_source source =
    let previous = source.replacing_source in
    source.replacing_source <- Option.map (fun bound -> bound.lease) source.bound;
    fun () -> source.replacing_source <- previous
  let checkpoint owner =
    let binding = owner.owner_binding and publisher = owner.publisher in
    let schedule_receipts = owner.schedule_receipts and receipts_dirty = owner.receipts_dirty in
    let root = Option.map (fun source ->
      (source, source.bound, source.owner_epoch, source.generation, source.rows,
        source.contains, source.listeners, source.adopt)) owner.root in
    let receipts = Hashtbl.fold (fun _ retention saved ->
      (retention, retention.latest, retention.releasing) :: saved) owner.tickets [] in
    fun () ->
      owner.owner_binding <- binding; owner.publisher <- publisher;
      owner.schedule_receipts <- schedule_receipts; owner.receipts_dirty <- receipts_dirty;
      Option.iter (fun (source, bound, owner_epoch, generation, rows, contains, listeners, adopt) ->
        source.bound <- bound; source.owner_epoch <- owner_epoch;
        source.generation <- generation; source.rows <- rows; source.contains <- contains;
        source.listeners <- listeners; source.adopt <- adopt) root;
      List.iter (fun (retention, latest, releasing) ->
        retention.releasing <- releasing;
        if retention.latest != latest then set_receipt retention latest) receipts;
      Option.iter (fun (source, bound, _, _, _, _, _, _) ->
        publish_state owner source.binding_state bound) root
  let accept_receipt owner ~node ~ticket envelope =
    let receipt = decode_receipt envelope in
    let native = Option.get receipt.native in
    if native.owner_node <> node || native.ticket_id <> ticket then
      invalid_arg "virtual receipt routing mismatch";
    match Hashtbl.find_opt owner.tickets ticket, owner.owner_binding with
    | Some retention, Some bound when bound.node = node && bound.lease = native.epoch
        && Option.fold ~none:true ~some:(fun latest ->
          latest.epoch <> native.epoch || latest.owner_node <> native.owner_node
          || native.proof >= latest.proof)
          (Option.bind retention.latest (fun receipt -> receipt.native)) ->
      if receipt.status = Released then begin
        match Option.bind retention.releasing (fun receipt -> receipt.native) with
        | Some proof when current retention native && proof.proof = native.proof
            && proof.row = native.row && proof.geometry = native.geometry
            && proof.requirements = native.requirements && native.pins >= proof.pins ->
          (* Adopt the physical row before publishing cold-key removal. *)
          retention.source.adopt [native.row.row_node];
          retention.active <- false; retention.releasing <- None;
          Hashtbl.remove owner.tickets ticket;
          set_receipt retention (Some receipt);
          Signal.dispose_signal (Signal.value retention.receipt_state); notify owner
        | _ -> ()
      end else if receipt.status = Pinned || receipt.status = Focused then begin
        if current retention native && List.mem "attached" native.requirements
            && (receipt.status <> Focused || List.mem "focus" native.requirements) then
          begin
            let superseded = Option.fold ~none:false
              ~some:(fun pending -> pending.proof <> native.proof)
              (Option.bind retention.releasing (fun receipt -> receipt.native)) in
            if superseded then retention.releasing <- None;
            set_receipt retention (Some receipt);
            if superseded then notify owner
          end
      end else begin
        retention.releasing <- None;
        set_receipt retention (Some receipt); notify owner
      end
    | _ -> ()
end
