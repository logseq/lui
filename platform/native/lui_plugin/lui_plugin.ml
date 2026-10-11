(* Plugin registry: name validation, ordered setup with unwind on
   failure, and service dispatch under the canonical plugin:<name>
   namespace. See lui_plugin.mli for the registry semantics. *)

type handler = string -> (string, string) result

type t = {
  name : string;
  services : (string * handler) list;
  setup : unit -> (unit, string) result;
  teardown : (unit -> unit) option;
}

let v ?(setup = fun () -> Ok ()) ?teardown name services =
  { name; services; setup; teardown }

let reserved = [ "lui" ]

let valid_name s =
  let n = String.length s in
  n > 0
  && s.[0] >= 'a' && s.[0] <= 'z'
  && String.for_all
       (fun c -> (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-')
       s

let service_name p = "plugin:" ^ p.name

(* The bare plugin name also resolves; callers may use either form. *)
let normalize_service s =
  let s = String.lowercase_ascii (String.trim s) in
  if String.length s > 7 && String.sub s 0 7 = "plugin:" then
    String.sub s 7 (String.length s - 7)
  else s

let lock = Mutex.create ()
let registry : (string, t) Hashtbl.t = Hashtbl.create 17
let order : string list ref = ref []

let with_lock f =
  Mutex.lock lock;
  match f () with
  | r ->
    Mutex.unlock lock;
    r
  | exception e ->
    Mutex.unlock lock;
    raise e

(* Unwind one plugin bound during the current [use] call. *)
let unbind p =
  (match p.teardown with
   | Some t -> (try t () with _ -> ())
   | None -> ());
  Hashtbl.remove registry p.name;
  order := List.filter (fun n -> n <> p.name) !order

let use plugins =
  let bad =
    List.find_map
      (fun p ->
        if not (valid_name p.name) then
          Some
            (Printf.sprintf
               "invalid plugin name %S (want [a-z][a-z0-9-]*)"
               p.name)
        else if List.mem p.name reserved then
          Some (Printf.sprintf "plugin name %S is reserved" p.name)
        else None)
      plugins
  in
  match bad with
  | Some e -> Error e
  | None ->
    with_lock
      (fun () ->
        (* Duplicate detection: within the batch, and against the
           registry. The same descriptor value re-used is a no-op. *)
        let seen = Hashtbl.create (List.length plugins) in
        let rec check = function
          | [] -> Ok ()
          | p :: tl ->
            if Hashtbl.mem seen p.name then
              Error (Printf.sprintf "duplicate plugin name %S" p.name)
            else begin
              Hashtbl.add seen p.name ();
              match Hashtbl.find_opt registry p.name with
              | Some existing when existing != p ->
                Error
                  (Printf.sprintf
                     "plugin name %S is already registered" p.name)
              | Some _ | None -> check tl
            end
        in
        match check plugins with
        | Error e -> Error e
        | Ok () ->
          let rec go bound = function
            | [] -> Ok ()
            | p :: tl ->
              if Hashtbl.mem registry p.name then
                (* Idempotent: the same descriptor was bound before. *)
                go bound tl
              else begin
                match (try p.setup () with e -> Error (Printexc.to_string e)) with
                | Error e ->
                  List.iter unbind bound;
                  Error
                    (Printf.sprintf "plugin %S setup failed: %s" p.name e)
                | Ok () ->
                  Hashtbl.replace registry p.name p;
                  order := !order @ [ p.name ];
                  go (p :: bound) tl
              end
          in
          go [] plugins)

let lookup service = Hashtbl.find_opt registry (normalize_service service)

let mem ~service = with_lock (fun () -> lookup service <> None)

let call ~service ~method_ payload =
  let p = with_lock (fun () -> lookup service) in
  match p with
  | None ->
    Error
      (Printf.sprintf "unknown service %S (want plugin:<name>)" service)
  | Some p -> (
    match List.assoc_opt method_ p.services with
    | None ->
      Error
        (Printf.sprintf "unknown method %S on service %S" method_
           (service_name p))
    | Some h ->
      (try h payload
       with e ->
         Error
           (Printf.sprintf "%s.%s raised: %s" (service_name p) method_
              (Printexc.to_string e))))

let names () =
  with_lock (fun () -> List.map (fun n -> "plugin:" ^ n) !order)

let reset () =
  with_lock
    (fun () ->
      List.iter
        (fun n ->
          match Hashtbl.find_opt registry n with
          | Some p ->
            (match p.teardown with
             | Some t -> (try t () with _ -> ())
             | None -> ())
          | None -> ())
        !order;
      Hashtbl.reset registry;
      order := [])
