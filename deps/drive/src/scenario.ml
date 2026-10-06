(* .drive scenario DSL: line-oriented commands driving a `driver`.
     # comment
     press <sel> | tap <sel>    — tap <sel> hits the node's reported
                                  frame center when frames exist
     tap x y | tap-at x y       — coordinate press via host-reported
                                  frames (live attach only)
     type <sel> "text"          — TextChanged
     key "cmd+p"                — ExtensionEvent on ext:key-surface (falls
                                  back to a document-level key on live
                                  attach when no key-surface node exists)
     ext <sel> <identifier> <name> '<json fields>'
     submit|dismiss|appear|long-press|double-press <sel>
     toggle <sel> true|false
     value <sel> 0.5
     poll                       — drain async actions once
     wait <sel> [seconds]       — poll until selector matches (default 5s)
     expect <sel>
     expect-absent <sel>
     expect-prop <sel> <name> <value>
     sleep <seconds>
     dump
     dump-frames                — print reported node frames

   <sel> = id:N | kind:name | ext:identifier | text:needle | prop:name=value
   Bare words without a prefix are treated as text: selectors. *)

open Lui_protocol

type failure = { line : int; message : string }

exception Script_error of string


(* Minimal tokenizer: splits on spaces but keeps quoted spans together;
   quotes may appear mid-token (e.g. kind:button&text:"Open dialog"). *)
let tokens line =
  let n = String.length line in
  let buf = Buffer.create 16 in
  let flush acc started =
    let tok = Buffer.contents buf in
    Buffer.clear buf;
    if started then tok :: acc else acc
  in
  let rec next i acc started =
    if i >= n then List.rev (flush acc started)
    else
      match line.[i] with
      | ' ' | '\t' -> next (i + 1) (flush acc started) false
      | ('"' | '\'') as q ->
        let rec find j = if j >= n || line.[j] = q then j else find (j + 1) in
        let j = find (i + 1) in
        Buffer.add_string buf (String.sub line (i + 1) (j - i - 1));
        next (min n (j + 1)) acc true
      | c ->
        Buffer.add_char buf c;
        next (i + 1) acc true
  in
  next 0 [] false

let selector tok =
  match Model.selector_of_string tok with
  | Some s -> s
  | None -> raise (Script_error ("bad selector: " ^ tok))

let node d sel = Session.resolve d sel

let string_map fields =
  List.fold_left (fun acc (k, v) -> String_map.add k v acc) String_map.empty fields

let json_to_fields json_str =
  match Yojson.Safe.from_string json_str with
  | `Assoc fields ->
    List.filter_map
      (fun (k, v) ->
        match Model.wire_value_of_json v with
        | Some w -> Some (k, w)
        | None -> None)
      fields
    |> string_map
  | _ -> String_map.empty

let wait_for (d : Session.driver) sel timeout =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec loop () =
    if Model.exists d.Session.tree sel then ()
    else if Unix.gettimeofday () > deadline then
      raise (Script_error "timeout")
    else begin
      d.Session.poll ();
      if Model.exists d.Session.tree sel then ()
      else begin
        Unix.sleepf 0.02;
        loop ()
      end
    end
  in
  loop ()

(* `tap <sel>` prefers the node's reported frame center, so scripts
   verify real geometry instead of just event routing; without frames
   (in-process/ffi drivers) it degrades to a plain press. *)
let tap_selector d fail sel =
  let n = node d (selector sel) in
  d.Session.poll ();
  match List.assoc_opt n.Model.id (d.Session.frames ()) with
  | Some (r : Model.rect) -> (
    let x = r.Model.rx +. (r.Model.rw /. 2.0) in
    let y = r.Model.ry +. (r.Model.rh /. 2.0) in
    match d.Session.tap ~x ~y with
    | Ok _ -> []
    | Error msg -> fail msg)
  | None ->
    d.Session.send_event (Press n.Model.id);
    []

let run_line ~emit (d : Session.driver) lineno line =
  let line = String.trim line in
  if line = "" || line.[0] = '#' then []
  else
    let ts = tokens line in
    let fail msg = [ { line = lineno; message = msg } ] in
    try
      match ts with
      | ("tap" | "tap-at") :: xs :: ys :: _ -> (
        match (float_of_string_opt xs, float_of_string_opt ys) with
        | Some x, Some y -> (
          match d.Session.tap ~x ~y with
          | Ok _ -> []
          | Error msg -> fail msg)
        | _ ->
          if List.hd ts = "tap-at" then fail "bad coordinates: tap-at x y"
          else tap_selector d fail xs)
      | ("press" | "tap") :: sel :: _ ->
        if List.hd ts = "tap" then tap_selector d fail sel
        else begin
          let n = node d (selector sel) in
          d.Session.send_event (Press n.Model.id);
          []
        end
      | "long-press" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (LongPress n.id);
        []
      | "double-press" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (DoublePress n.id);
        []
      | "type" :: sel :: rest ->
        let n = node d (selector sel) in
        d.Session.send_event (TextChanged (n.id, String.concat " " rest));
        []
      | "key" :: combo :: _ ->
        let surface =
          match Model.first d.Session.tree (Ext "key-surface") with
          | Some n -> n
          (* live web attach has no key-surface node; id 0 is the
             adapter's document-level fallback (a real DOM keydown
             that reaches capture listeners on document) *)
          | None ->
            { Model.id = 0; kind = ""; props = Hashtbl.create 0
            ; children = []; parent = None }
        in
        let parts = String.split_on_char '+' combo in
        let mods, key =
          match List.rev parts with
          | k :: ms -> (String.concat "," ms, k)
          | [] -> ("", combo)
        in
        let fields =
          string_map [ ("key", StringValue key); ("mods", StringValue mods) ]
        in
        d.Session.send_event (ExtensionEvent (surface.id, "key-surface", "key", fields));
        []
      | "ext" :: sel :: identifier :: name :: rest ->
        let n = node d (selector sel) in
        let fields = json_to_fields (String.concat " " rest) in
        d.Session.send_event (ExtensionEvent (n.id, identifier, name, fields));
        []
      | "change" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (Change n.id);
        []
      | "submit" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (Submit n.id);
        []
      | "dismiss" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (Dismiss n.id);
        []
      | "appear" :: sel :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (Appear n.id);
        []
      | "toggle" :: sel :: v :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (ToggleChanged (n.id, v = "true" || v = "1"));
        []
      | "value" :: sel :: v :: _ ->
        let n = node d (selector sel) in
        d.Session.send_event (ValueChanged (n.id, float_of_string v));
        []
      | "poll" :: _ ->
        d.Session.poll ();
        []
      | "goto" :: hash :: _ ->
        (* live attach only: the host adapter sets location.hash so the
           app's own hashchange router resolves the route *)
        d.Session.send_nav hash;
        []
      | ("wait" | "expect") :: sel :: rest ->
        let timeout =
          match rest with
          | v :: _ -> (try float_of_string v with _ -> 5.0)
          | [] -> (if List.hd ts = "wait" then 5.0 else 0.0)
        in
        if timeout <= 0.0 then begin
          d.Session.poll ();
          if Model.exists d.Session.tree (selector sel) then []
          else fail ("expected node: " ^ sel)
        end
        else begin
          try wait_for d (selector sel) timeout; []
          with Script_error _ -> fail ("timed out waiting for: " ^ sel)
        end
      | "expect-absent" :: sel :: _ ->
        d.Session.poll ();
        if Model.exists d.Session.tree (selector sel) then fail ("unexpected node present: " ^ sel)
        else []
      | "expect-prop" :: sel :: name :: v :: _ ->
        d.Session.poll ();
        let n = node d (selector sel) in
        (match Model.prop d.Session.tree n.id name with
         | Some (StringValue s) when s = v -> []
         | Some (BoolValue b) when string_of_bool b = v -> []
         | Some (IntValue i) when string_of_int i = v -> []
         | Some w ->
           fail
             (Printf.sprintf "prop %s on #%d = %s, want %s" name n.id
                (Model.string_of_wire_value w) v)
         | None -> fail (Printf.sprintf "no prop %s on #%d" name n.id))
      | "sleep" :: v :: _ ->
        Unix.sleepf (float_of_string v);
        []
      | "dump" :: _ ->
        emit (Model.dump d.Session.tree);
        []
      | "dump-frames" :: _ ->
        let lines =
          List.map
            (fun (id, (r : Model.rect)) ->
              Printf.sprintf "#%d %.1f,%.1f %.1fx%.1f" id r.rx r.ry r.rw
                r.rh)
            (List.sort (fun (a, _) (b, _) -> compare a b) (d.Session.frames ()))
        in
        emit (if lines = [] then "(no frames reported)" else String.concat "\n" lines);
        []
      | cmd :: _ -> fail ("unknown command: " ^ cmd)
      | [] -> []
    with
    | Script_error msg -> fail msg
    | Failure msg -> fail msg
    | e -> fail (Printexc.to_string e)

let run ?(emit = print_endline) (d : Session.driver) source =
  let failures =
    String.split_on_char '\n' source
    |> List.mapi (fun i line -> (i + 1, line))
    |> List.concat_map (fun (i, line) -> run_line ~emit d i line)
  in
  d.Session.poll ();
  failures
