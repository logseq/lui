module Json = Lui_virtual_json

type binding = { node : int; lease : int }
type release_error = Stale_receipt | Owner_retired | Unsupported
type capability = Shared_viewport_retention_v1
type receipt_status = Pinned | Focused | Released | Stale | Missing_target | Retired
type row = { source_node : int; generation : int; row_node : int; incarnation : int }
type receipt = {
  envelope : string; status : receipt_status; owner_node : int; epoch : int;
  ticket_id : int; proof : int; rows : row list; geometry : int; pins : int;
  requirements : string list;
}
type owner = {
  scheduler : Signal.scheduler;
  mutable retired : bool;
  mutable serial : int;
  mutable owner_binding : binding option;
  mutable publisher : (int -> string -> string -> unit) option;
  mutable replacing_owner : bool;
  sources : (string list, source) Hashtbl.t;
  tickets : (int, retention) Hashtbl.t;
}
and source = {
  owner : owner; path : string list;
  binding_state : binding option Signal.state;
  mutable bound : binding option;
  mutable generation : int;
  mutable rows : (string * int) list;
  mutable listeners : (int * (unit -> unit)) list;
  mutable adopt : int list -> unit;
  mutable replacing_source : bool;
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
  owner_binding = None; publisher = None; sources = Hashtbl.create 8;
  replacing_owner = false;
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
let notify owner =
  Option.iter (fun publish ->
    let retained = List.map (fun retention -> Json.Object [
      "ticket", Json.Int retention.id;
      "path", Json.Array (List.map (fun value -> Json.String value) retention.source.path);
      "key", Json.String retention.key]) (tickets owner) in
    let releases = List.filter_map (fun retention -> Option.map (fun receipt ->
      Json.Object ["ticket", Json.Int retention.id; "receipt", Json.String receipt.envelope])
      retention.releasing) (tickets owner) in
    match owner.owner_binding with
    | None -> ()
    | Some binding -> publish binding.lease (Json.encode (Json.Array retained))
        (Json.encode (Json.Array releases))) owner.publisher;
  let listeners = Hashtbl.fold (fun _ source result ->
    List.rev_append source.listeners result) owner.sources [] in
  List.iter (fun (_, notify) -> notify ()) listeners
let source owner path =
  live owner;
  match Hashtbl.find_opt owner.sources path with
  | Some source -> source
  | None ->
    let source = { owner; path; binding_state = Signal.state owner.scheduler None;
      bound = None; generation = 0; rows = []; listeners = []; adopt = (fun _ -> ());
      replacing_source = false } in
    Hashtbl.add owner.sources path source; source
let root_source owner ~key = source owner [Json.nonempty key]
let child_source ~parent ~row_key ~key =
  source parent.owner (parent.path @ [Json.nonempty row_key; Json.nonempty key])
let binding source = Signal.value source.binding_state
let ticket retention = retention.id
let receipt retention = Signal.value retention.receipt_state
let receipt_status receipt = receipt.status
let retain source ~key =
  live source.owner;
  let retention = { source; key = Json.nonempty key; id = fresh source.owner;
    receipt_state = Signal.state source.owner.scheduler None; latest = None;
    releasing = None; active = true } in
  Hashtbl.add source.owner.tickets retention.id retention;
  notify source.owner;
  retention
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
    owner.owner_binding <- None; owner.publisher <- None;
    Hashtbl.iter (fun _ source ->
      source.bound <- None; source.generation <- 0; source.rows <- [];
      publish_state owner source.binding_state None;
      Signal.dispose_signal (binding source);
      source.listeners <- []; source.adopt <- (fun _ -> ())) owner.sources
  end

let chain path key = match path with
  | [] -> []
  | name :: rest ->
    let rec loop prefix = function
      | [] -> [prefix, key]
      | parent_key :: child :: rest -> (prefix, parent_key) :: loop (prefix @ [parent_key; child]) rest
      | _ -> invalid_arg "invalid shared virtual source path"
    in loop [name] rest
let current_rows retention =
  let owner = retention.source.owner in
  List.map (fun (path, key) ->
    let source = Hashtbl.find owner.sources path in
    let bound = Option.get source.bound in
    bound.node, source.generation, List.assoc key source.rows)
    (chain retention.source.path retention.key)
let current retention receipt =
  let owner = retention.source.owner in
  match owner.owner_binding with
  | Some bound when retention.active && not owner.retired
      && bound.node = receipt.owner_node && bound.lease = receipt.epoch
      && retention.id = receipt.ticket_id ->
    (try List.map (fun row -> row.source_node, row.generation, row.row_node) receipt.rows
       = current_rows retention && List.for_all (fun row -> row.incarnation > 0) receipt.rows
     with Not_found | Invalid_argument _ -> false)
  | _ -> false
let request_release retention receipt =
  if retention.source.owner.retired then Error Owner_retired
  else if retention.source.owner.owner_binding = None then Error Unsupported
  else if not (current retention receipt)
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
  let rows = List.map (fun row ->
    let fields = Json.object_ ["source"; "generation"; "row"; "incarnation"] row in
    let positive name = Json.positive (List.assoc name fields) in
    {source_node = positive "source"; generation = positive "generation";
      row_node = positive "row"; incarnation = positive "incarnation"}) (Json.array (field "rows")) in
  let requirements = Json.strings (field "requirements") in
  if List.sort_uniq String.compare requirements <> List.sort String.compare requirements
     || List.exists (fun requirement -> not (List.mem requirement ["attached"; "visible"; "focus"])) requirements
  then invalid_arg "invalid virtual receipt requirements";
  {envelope; status; owner_node = Json.positive (field "owner"); epoch = Json.positive (field "epoch");
   ticket_id = Json.positive (field "ticket"); proof = Json.positive (field "proof"); rows;
   geometry = Json.positive (field "geometry"); pins = Json.positive (field "pins"); requirements}

module Internal = struct
  let bind_owner owner ~node ~publish =
    live owner;
    if owner.owner_binding <> None && not owner.replacing_owner then invalid_arg "shared virtual owner already bound";
    let binding = {node; lease = fresh owner} in
    Hashtbl.iter (fun _ retention ->
      retention.releasing <- None; set_receipt retention None) owner.tickets;
    owner.owner_binding <- Some binding; owner.publisher <- Some publish;
    notify owner; binding
  let unbind_owner owner binding =
    if Option.fold ~none:false ~some:(fun current -> current.lease = binding.lease) owner.owner_binding then begin
      owner.owner_binding <- None; owner.publisher <- None;
      Hashtbl.iter (fun _ retention ->
        retention.releasing <- None; set_receipt retention None) owner.tickets;
      Hashtbl.iter (fun _ source ->
        source.bound <- None; source.generation <- 0; source.rows <- [];
        source.adopt <- (fun _ -> ());
        publish_state owner source.binding_state None) owner.sources;
      true
    end else false
  let bind_source source ~node ~owner_node =
    live source.owner;
    if source.bound <> None && not source.replacing_source then invalid_arg "shared virtual source already bound";
    (match source.owner.owner_binding with
     | Some owner when owner.node = owner_node -> ()
     | _ -> invalid_arg "shared virtual source requires its bound owner");
    let bound = {node; lease = fresh source.owner} in
    source.bound <- Some bound; source.generation <- 0; source.rows <- [];
    publish_state source.owner source.binding_state (Some bound);
    bound
  let unbind_source source binding =
    if Option.fold ~none:false ~some:(fun current -> current.lease = binding.lease) source.bound then begin
      source.bound <- None; source.generation <- 0; source.rows <- [];
      source.adopt <- (fun _ -> ());
      publish_state source.owner source.binding_state None;
      Hashtbl.iter (fun _ retention -> retention.releasing <- None; set_receipt retention None)
        source.owner.tickets;
      true
    end else false
  let owner_binding source = source.owner.owner_binding
  let source_path source = Json.encode_strings source.path
  let retained_keys source =
    List.concat_map (fun retention ->
      List.filter_map (fun (path, key) -> if path = source.path then Some key else None)
        (chain retention.source.path retention.key)) (tickets source.owner)
    |> List.sort_uniq String.compare
  let on_change source notify =
    let id = fresh source.owner in
    source.listeners <- (id, notify) :: source.listeners;
    fun () -> source.listeners <- List.filter (fun (other, _) -> other <> id) source.listeners
  let commit_rows source ~generation rows =
    source.generation <- generation; source.rows <- rows
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
    let changed = Hashtbl.fold (fun _ source changed ->
      let previous = source.bound in
      source.bound <- binding source.bound;
      source.rows <- List.map (fun (key, row) -> key, node row) source.rows;
      if source.bound = previous then changed else source :: changed) owner.sources [] in
    (* Every ancestor row is canonical before observers see a binding change. *)
    List.iter (fun source -> publish_state owner source.binding_state source.bound) changed
  let replacing_owner owner =
    let previous = owner.replacing_owner in
    owner.replacing_owner <- true;
    fun () -> owner.replacing_owner <- previous
  let replacing_source source =
    let previous = source.replacing_source in
    source.replacing_source <- true;
    fun () -> source.replacing_source <- previous
  let checkpoint owner =
    let binding = owner.owner_binding and publisher = owner.publisher in
    let sources = Hashtbl.fold (fun _ source saved ->
      (source, source.bound, source.generation, source.rows, source.listeners, source.adopt) :: saved)
      owner.sources [] in
    let receipts = Hashtbl.fold (fun _ retention saved ->
      (retention, retention.latest, retention.releasing) :: saved) owner.tickets [] in
    fun () ->
      owner.owner_binding <- binding; owner.publisher <- publisher;
      List.iter (fun (retention, latest, releasing) ->
        retention.releasing <- releasing; set_receipt retention latest) receipts;
      List.iter (fun (source, bound, generation, rows, listeners, adopt) ->
        source.bound <- bound; source.generation <- generation; source.rows <- rows;
        source.listeners <- listeners; source.adopt <- adopt;
        publish_state owner source.binding_state bound) sources
  let accept_receipt owner ~node ~ticket envelope =
    let receipt = decode_receipt envelope in
    if receipt.owner_node <> node || receipt.ticket_id <> ticket then
      invalid_arg "virtual receipt routing mismatch";
    match Hashtbl.find_opt owner.tickets ticket, owner.owner_binding with
    | Some retention, Some bound when bound.node = node && bound.lease = receipt.epoch
        && Option.fold ~none:true ~some:(fun latest -> receipt.proof >= latest.proof) retention.latest ->
      if receipt.status = Released then begin
        match retention.releasing with
        | Some proof when current retention receipt && proof.proof = receipt.proof
            && proof.rows = receipt.rows && proof.geometry = receipt.geometry
            && proof.requirements = receipt.requirements && receipt.pins >= proof.pins ->
          (* Adopt the complete path before publishing cold-key removal. *)
          List.iter (fun row -> Hashtbl.iter (fun _ source ->
            match source.bound with
            | Some bound when bound.node = row.source_node -> source.adopt [row.row_node]
            | _ -> ()) owner.sources) receipt.rows;
          retention.active <- false; retention.releasing <- None;
          Hashtbl.remove owner.tickets ticket;
          set_receipt retention (Some receipt);
          Signal.dispose_signal (Signal.value retention.receipt_state); notify owner
        | _ -> ()
      end else if receipt.status = Pinned || receipt.status = Focused then begin
        if current retention receipt && List.mem "attached" receipt.requirements
            && (receipt.status <> Focused || List.mem "focus" receipt.requirements) then
          begin
            let superseded = Option.fold ~none:false
              ~some:(fun pending -> pending.proof <> receipt.proof) retention.releasing in
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
