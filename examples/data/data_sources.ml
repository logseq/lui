module Edn = Melange_edn
module C = Data_contract
module M = Lui_protocol.String_map

type component = { props : C.shape; slots : string list; view : Edn.any }
type document = {
  id : string;
  imports : string M.t;
  components : component M.t;
  view : Edn.any option;
}
type cache = (string, string * document) Hashtbl.t
type loader = from:string option -> string -> ((string * string), string) result
type graph = {
  entry : document;
  documents : (string, document) Hashtbl.t;
  links : ((string * string), string) Hashtbl.t;
}

exception Invalid_source of string

let fail message = raise (Invalid_source message)
let name = C.keyword
let vector (Edn.Any value) = match value with
  | Edn.Vector values -> Array.to_list values
  | _ -> fail "expected a vector"

let fields (Edn.Any value) = match value with
  | Edn.Map values -> C.index (Array.to_list (Array.map (fun (key, value) -> name key, value) values))
  | _ -> fail "expected a map"

let required key fields = match M.find_opt key fields with
  | Some value -> value | None -> fail ("missing :" ^ key)

let only allowed fields = M.iter (fun key _ ->
  if not (List.mem key allowed) then fail ("unknown field :" ^ key)) fields

let cache () = Hashtbl.create 16

let parse ~id source =
  try
    if String.length source > 1_048_576 then fail "source exceeds 1 MiB";
    let data = match Edn.of_edn_string_all source with
      | [data] -> data | _ -> fail "expected exactly one EDN document"
    in
    let imports, components, view = match data with
      | Edn.Any (Edn.Map _) ->
          let document = fields data in
          only ["version"; "imports"; "components"; "view"] document;
          (match required "version" document with
          | Edn.Any (Edn.Int 1L) -> () | _ -> fail "unsupported view version");
          let imports = match M.find_opt "imports" document with
            | None -> M.empty
            | Some data -> M.mapi (fun alias value ->
                if String.contains alias '/' then fail "import aliases cannot contain /";
                match value with Edn.Any (Edn.String path) -> path | _ -> fail "import path must be a string") (fields data)
          in
          let components = match M.find_opt "components" document with
            | None -> M.empty
            | Some data -> M.mapi (fun key value ->
                if String.contains key '/' then fail "local component names cannot contain /";
                let definition = fields value in
                only ["props"; "slots"; "view"] definition;
                let props = match M.find_opt "props" definition with
                  | None -> C.record [] | Some data -> C.of_edn data
                in
                (match props with C.Record _ -> () | _ -> fail "component :props must be a record schema");
                let slots = match M.find_opt "slots" definition with
                  | None -> [] | Some data -> List.map name (vector data)
                in
                ignore (C.index (List.map (fun name -> name, ()) slots));
                {props; slots; view = required "view" definition}) (fields data)
          in
          imports, components, M.find_opt "view" document
      | _ -> M.empty, M.empty, Some data
    in
    Ok {id; imports; components; view}
  with
  | Invalid_source message | C.Invalid_contract message | Edn.Parse_error message -> Error (id ^ ": " ^ message)

let single entry =
  let documents = Hashtbl.create 1 in
  Hashtbl.add documents entry.id entry;
  {entry; documents; links = Hashtbl.create 1}

let load_graph ?cache:parsed_cache ~load ~entry () =
  let parsed_cache = match parsed_cache with Some cache -> cache | None -> cache () in
  let documents = Hashtbl.create 16 and links = Hashtbl.create 16 in
  let sources = Hashtbl.create 16 and bytes = ref 0 in
  let rec visit stack from path =
    let id, source = match load ~from path with
      | Ok value -> value | Error error -> fail error
    in
    if List.mem id stack then fail ("import cycle: " ^ String.concat " -> " (List.rev (id :: stack)));
    match Hashtbl.find_opt documents id with
    | Some document ->
        if Hashtbl.find sources id <> source then fail (id ^ ": source changed while linking");
        document
    | None ->
        if Hashtbl.length documents >= 256 then fail "import graph exceeds 256 files";
        bytes := !bytes + String.length source;
        if !bytes > 8_388_608 then fail "import graph exceeds 8 MiB";
        let document = match Hashtbl.find_opt parsed_cache id with
          | Some (previous, document) when previous = source -> document
          | _ ->
              let document = match parse ~id source with Ok value -> value | Error error -> fail error in
              if Hashtbl.length parsed_cache >= 256 then Hashtbl.clear parsed_cache;
              Hashtbl.replace parsed_cache id (source, document);
              document
        in
        Hashtbl.add documents id document;
        Hashtbl.add sources id source;
        M.iter (fun alias path ->
          let imported = visit (id :: stack) (Some id) path in
          Hashtbl.add links (id, alias) imported.id) document.imports;
        document
  in
  try
    let entry = visit [] None entry in
    Ok {entry; documents; links}
  with Invalid_source message -> Error message

let component graph document name =
  let document, name = match String.index_opt name '/' with
    | None -> document, name
    | Some separator ->
        let alias = String.sub name 0 separator in
        let name = String.sub name (separator + 1) (String.length name - separator - 1) in
        let id = match Hashtbl.find_opt graph.links (document.id, alias) with
          | Some id -> id | None -> fail (document.id ^ ": unknown import alias :" ^ alias)
        in
        Hashtbl.find graph.documents id, name
  in
  match M.find_opt name document.components with
  | Some component -> document, name, component
  | None -> fail (document.id ^ ": unknown component :" ^ name)
