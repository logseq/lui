(* Extension fingerprint drift check.

   Host extension registries (Swift [LUIAppleExtension]/[LUIAppleTweak],
   Dart [LUIFlutterExtension]/[LUIFlutterTweak]) carry a hand-mirrored
   [fingerprint] string literal for every registered schema. The literal
   covers the full OCaml-declared schema — including the supported platform
   profiles, which the host does not know — so it cannot be recomputed on
   the host and is copied by hand. When an OCaml schema and a host literal
   drift apart, the runtime keeps working until the first extension node
   mounts, then rejects the batch ("extension fingerprint mismatch",
   "unsupported child kind") and the host renders a blank screen.

   [check_registry] catches that drift at test time: it extracts every
   canonical-format fingerprint literal embedded in a host source file and
   compares it against the fingerprint computed from the OCaml registry —
   the same string the runtime emits in [create-extension] ops. Point it at
   the host extension registration sources from a [dune runtest] case; the
   reported expected value is the corrected literal to paste back into host
   code. *)

type host_fingerprint = {
  host_identifier : string;
  host_tweak : bool;
  host_literal : string;
}

type mismatch =
  | Undeclared_identifier of host_fingerprint
  | Drifted of { declaration : host_fingerprint; expected : string }

let component_prefix = "lui-extension-v1|"
let tweak_prefix = "lui-tweak-v1|"

let find_substring source pattern start =
  let pattern_length = String.length pattern in
  let last = String.length source - pattern_length in
  let rec loop index =
    if index > last then None
    else if String.sub source index pattern_length = pattern then Some index
    else loop (index + 1)
  in
  loop (max start 0)

(* A fingerprint literal ends at the next quote or newline: host sources
   embed it as a single-line string literal, and a stale fingerprint inside
   a comment is drift worth flagging anyway. *)
let literal_end source start =
  let rec loop index =
    if index >= String.length source then index
    else
      match source.[index] with
      | '"' | '\'' | '\n' | '\r' -> index
      | _ -> loop (index + 1)
  in
  loop start

(* After the version prefix the literal embeds its own identifier as a
   length-prefixed token, e.g. "9:apple-map|". *)
let parse_identifier literal prefix_length =
  match String.index_from literal prefix_length '|' with
  | exception Not_found -> None
  | pipe ->
    let token = String.sub literal prefix_length (pipe - prefix_length) in
    (match String.index token ':' with
     | exception Not_found -> None
     | colon ->
       let name =
         String.sub token (colon + 1) (String.length token - colon - 1)
       in
       (match int_of_string_opt (String.sub token 0 colon) with
        | Some declared when declared = String.length name -> Some name
        | _ -> None))

let extract_fingerprints source =
  let collect prefix tweak =
    let prefix_length = String.length prefix in
    let rec loop start declarations =
      match find_substring source prefix start with
      | None -> declarations
      | Some position ->
        let stop = literal_end source (position + prefix_length) in
        let literal = String.sub source position (stop - position) in
        let identifier =
          match parse_identifier literal prefix_length with
          | Some name -> name
          | None -> literal
        in
        loop (position + prefix_length)
          ({
             host_identifier = identifier;
             host_tweak = tweak;
             host_literal = literal;
           }
           :: declarations)
    in
    loop 0 []
  in
  let seen = Hashtbl.create 8 in
  collect component_prefix false
  |> List.rev_append (collect tweak_prefix true)
  |> List.filter (fun declaration ->
       if Hashtbl.mem seen declaration.host_literal then false
       else begin
         Hashtbl.replace seen declaration.host_literal ();
         true
       end)

let check_registry registry source =
  List.filter_map
    (fun declaration ->
       match Lui_extension.schema registry declaration.host_identifier with
       | None -> Some (Undeclared_identifier declaration)
       | Some schema ->
         let expected =
           if Lui_extension.is_tweak registry declaration.host_identifier
           then Lui_extension.tweak_fingerprint schema
           else Lui_extension.fingerprint schema
         in
         if expected = declaration.host_literal then None
         else Some (Drifted { declaration; expected }))
    (extract_fingerprints source)

let describe_mismatch mismatch =
  match mismatch with
  | Undeclared_identifier declaration ->
    Printf.sprintf
      "%s: host fingerprint literal has no OCaml-declared schema\n  host literal: %s"
      declaration.host_identifier declaration.host_literal
  | Drifted { declaration; expected } ->
    Printf.sprintf
      "%s: fingerprint drifted from the OCaml-declared schema\n  expected (OCaml schema): %s\n  host literal:            %s"
      declaration.host_identifier expected declaration.host_literal

let describe_mismatches mismatches =
  String.concat "\n" (List.map describe_mismatch mismatches)
