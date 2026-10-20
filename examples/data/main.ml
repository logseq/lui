module P = Lui_protocol
module E = Data_view.Edn
module C = Data_view.Contract

type todo = { id : string; title : string; done_ : bool }
type model = { draft : string; items : todo list; next_id : int; split_ratio : float }

type action =
  | Draft of string
  | Add
  | Toggle of string * bool
  | Rename of string * string
  | Remove of string
  | Reverse
  | Resize of float

let string value = E.any (E.string value)
let bool value = E.any (E.bool value)

let object_ fields =
  E.any
    (E.map
       (List.map (fun (name, value) -> (E.any (E.keyword name), value)) fields))

let project model =
  object_
    [
      ("draft", string model.draft);
      ("can-add?", bool (String.trim model.draft <> ""));
      ("empty?", bool (model.items = []));
      ("split-ratio", E.any (E.float model.split_ratio));
      ( "summary",
        string
          (Printf.sprintf "%d tasks / %d done" (List.length model.items)
             (List.length (List.filter (fun item -> item.done_) model.items)))
      );
      ( "items",
        E.any
          (E.vector
             (List.map
                (fun item ->
                  object_
                    [
                      ("id", string item.id);
                      ("title", string item.title);
                      ("done?", bool item.done_);
                      ("toggle-id", string ("toggle-" ^ item.id));
                    ])
                model.items)) );
    ]

let update model = function
  | Draft draft -> { model with draft }
  | Add when String.trim model.draft = "" -> model
  | Add ->
      {
        model with
        draft = "";
        next_id = model.next_id + 1;
        items =
          {
            id = string_of_int model.next_id;
            title = String.trim model.draft;
            done_ = false;
          }
          :: model.items;
      }
  | Toggle (id, done_) ->
      {
        model with
        items =
          List.map
            (fun item -> if item.id = id then { item with done_ } else item)
            model.items;
      }
  | Rename (id, title) ->
      {
        model with
        items =
          List.map
            (fun item -> if item.id = id then { item with title } else item)
            model.items;
      }
  | Remove id ->
      { model with items = List.filter (fun item -> item.id <> id) model.items }
  | Reverse -> { model with items = List.rev model.items }
  | Resize split_ratio -> {model with split_ratio}

let model_schema = C.record [
  "draft", C.String; "can-add?", C.Bool; "empty?", C.Bool;
  "summary", C.String; "split-ratio", C.Float;
  "items", C.Vector (C.record ["id", C.String; "title", C.String; "done?", C.Bool; "toggle-id", C.String])
]

let actions = [
  {C.name = "draft"; arguments = []; events = ["input"]};
  {C.name = "add"; arguments = []; events = ["press"; "submit"]};
  {C.name = "toggle"; arguments = [C.String]; events = ["toggle"]};
  {C.name = "rename"; arguments = [C.String]; events = ["input"]};
  {C.name = "remove"; arguments = [C.String]; events = ["press"]};
  {C.name = "reverse"; arguments = []; events = ["press"]};
  {C.name = "resize"; arguments = []; events = ["ext/split-branch/ratio-changed"]}
]

let dispatch send name args event =
  let action =
    match (name, args, event) with
    | "draft", [], P.TextChanged (_, value) -> Draft value
    | "add", [], (P.Press _ | P.Submit _) -> Add
    | "toggle", [ E.Any (E.String id) ], P.ToggleChanged (_, value) ->
        Toggle (id, value)
    | "rename", [ E.Any (E.String id) ], P.TextChanged (_, value) ->
        Rename (id, value)
    | "remove", [ E.Any (E.String id) ], P.Press _ -> Remove id
    | "reverse", [], P.Press _ -> Reverse
    | "resize", [], P.ExtensionEvent (_, "split-branch", "ratio-changed", values) ->
        (match P.String_map.find_opt "ratio" values with
        | Some (P.FloatValue value) when P.is_finite value -> Resize (max 0. (min 1. value))
        | _ -> invalid_arg "invalid split ratio")
    | _ -> invalid_arg ("invalid OCaml action " ^ name)
  in
  ignore (send action)

let read path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let () =
  let root = match Sys.getenv_opt "LUI_DATA_ROOT" with Some root -> root | None -> Sys.getcwd () in
  let entry = ref (Filename.concat root "examples/data/todos.edn") in
  let mount_only = ref false and selected_profile = ref "generic" and benchmark = ref 0 in
  Arg.parse ["--mount-only", Arg.Set mount_only, "Mount without scripted events";
             "--benchmark", Arg.Set_int benchmark, "Measure cached compilation and model updates";
             "--profile", Arg.Set_string selected_profile, "generic|web|ios|macos|android|linux|windows"]
    (fun path -> entry := path) "main.exe [view.edn] [--mount-only] [--profile platform]";
  let manifest paths = String.concat "\n" (List.map (fun path -> read (Filename.concat root path)) paths) in
  let web = manifest ["platform/web/src/lui-split.js"; "examples/components/web/web_main.ml"] in
  let apple = manifest ["platform/apple/Sources/LUIAppleBackend/LUISplit.swift"; "examples/components/ios-swiftui/Sources/LUIComponentsApp/GalleryExtensions.swift"] in
  let android = manifest ["platform/android/lui/src/main/kotlin/dev/lui/LuiSplit.kt"; "examples/components/android/app/src/main/java/dev/lui/components/GalleryExtensions.kt"] in
  let extensions = Extension_schemas.registry () in
  let accent = match Lui_extension.schema extensions "gallery-accent" with
    | Some schema -> Lui_extension.tweak_fingerprint schema
    | None -> invalid_arg "gallery-accent schema is missing"
  in
  let hosts = [
    C.host (P.generic_profile ()) "";
    C.host ~registered:["gallery-accent", accent] (P.profile P.WebOS P.WebHost) web;
    C.host (P.profile P.IOS P.SwiftUIHost) apple;
    C.host (P.profile P.MacOS P.SwiftUIHost) apple;
    C.host (P.profile P.AndroidOS P.KotlinHost) android;
    C.host (P.profile P.LinuxOS P.GenericHost) "";
    C.host (P.profile P.WindowsOS P.GenericHost) ""
  ] in
  let host = match List.find_opt (fun host -> Lui_extension.operating_system_name host.C.profile.P.profile_os = !selected_profile) hosts with
    | Some host -> host | None -> invalid_arg "unknown platform profile"
  in
  let contract = C.create ~extensions ~extension_contracts:Extension_schemas.view_contracts ~model:model_schema ~actions ~hosts () in
  let load ~from path =
    try
      let path = match from with
        | Some parent when Filename.is_relative path -> Filename.concat (Filename.dirname parent) path
        | _ -> path
      in
      let path = Unix.realpath path in
      Ok (path, read path)
    with Sys_error error -> Error error | Unix.Unix_error (error, operation, path) ->
      Error (operation ^ " " ^ path ^ ": " ^ Unix.error_message error)
  in
  let timed callback =
    let start = Unix.gettimeofday () in
    let result = callback () in
    result, 1000. *. (Unix.gettimeofday () -. start)
  in
  let parse_time = if !benchmark > 0 then
    let source = read (Unix.realpath !entry) in
    let _, elapsed = timed (fun () ->
      for _ = 1 to !benchmark do
        ignore (Data_view.parse ~id:!entry source)
      done) in
    Printf.printf "root parse (in memory): %.3f ms/doc\n" (elapsed /. float !benchmark);
    true
  else false in
  let graph, load_time = timed (fun () -> Data_view.Sources.load_graph ~load ~entry:!entry ()) in
  let graph = match graph with Ok graph -> graph | Error error -> prerr_endline error; exit 2 in
  let compiled, compile_time = timed (fun () -> Data_view.compile_graph ~contract graph) in
  let document =
    match compiled with
    | Ok view -> view
    | Error error ->
        prerr_endline error;
        exit 2
  in
  if parse_time then begin
    Printf.printf "module load/parse: %.3f ms (%d modules)\n" load_time
      (Hashtbl.length graph.Data_view.Sources.documents);
    Printf.printf "static validation + plan compile: %.3f ms\n" compile_time;
    let _, elapsed = timed (fun () ->
      for _ = 1 to !benchmark do
        match Data_view.compile_graph ~contract graph with
        | Ok _ -> () | Error error -> failwith error
      done) in
    Printf.printf "cached source graph compile: %.3f ms/plan\n" (elapsed /. float !benchmark)
  end;
  let backend =
    {
      P.backend_profile = host.C.profile;
      apply_batch =
        (fun batch ->
          let creates, sets, moves, drops =
            List.fold_left
              (fun (c, s, m, d) -> function
                | P.CreateNode _ | P.CreateExtension _ -> (c + 1, s, m, d)
                | P.SetProp _ | P.SetExtensionProp _ -> (c, s + 1, m, d)
                | P.MoveChild _ -> (c, s, m + 1, d)
                | P.DropNode _ -> (c, s, m, d + 1)
                | _ -> (c, s, m, d))
              (0, 0, 0, 0) batch.P.ops
          in
          if !benchmark <= 0 then
            Printf.printf "generation=%d create=%d set=%d move=%d drop=%d\n%!"
              batch.generation creates sets moves drops;
          true);
    }
  in
  let initial = { draft = ""; items = []; next_id = 1; split_ratio = 0.5 } in
  let initial =
    if !mount_only then update (update initial (Draft "Schema-driven UI")) Add
    else initial
  in
  let app =
    Lui_app.create_with_extensions backend contract.C.extensions initial update (fun _ model send ->
        Data_view.render document ~model ~project ~dispatch:(dispatch send))
  in
  Fun.protect
    ~finally:(fun () -> ignore (Lui_app.dispose app))
    (fun () ->
      ignore (Lui_app.start app);
      ignore (Lui_app.flush app);
      if !benchmark > 0 then begin
        let _, elapsed = timed (fun () ->
          for index = 1 to !benchmark do
            ignore (Lui_app.send app (Draft (string_of_int index)));
            ignore (Lui_app.flush app)
          done) in
        Printf.printf "OCaml model update + retained render: %.3f ms/update\n"
          (elapsed /. float !benchmark)
      end;
      if not !mount_only then begin
        let branch = Hashtbl.fold (fun id identifier found ->
          if identifier = "split-branch" then Some id else found)
          (Lui_app.runtime app).Lui_runtime.runtime_extension_nodes None in
        match branch with
        | Some node ->
            ignore (Lui_app.dispatch_event app (P.ExtensionEvent (node, "split-branch", "ratio-changed", P.String_map.singleton "ratio" (P.FloatValue 0.65))));
            ignore (Lui_app.flush app);
            Printf.printf "OCaml split ratio: %.2f\n" (Lui_app.model app).split_ratio
        | None ->
        let find identifier =
          Hashtbl.fold
            (fun id props found ->
              if
                P.Property_map.find_opt P.AccessibilityIdentifier props
                = Some (P.StringValue identifier)
              then Some id
              else found)
            (Lui_app.runtime app).Lui_runtime.runtime_properties None
          |> Option.get
        in
        let emit event =
          ignore (Lui_app.dispatch_event app event);
          ignore (Lui_app.flush app)
        in
        emit (P.TextChanged (find "draft", "Explore UI as data"));
        emit (P.Press (find "add"));
        emit (P.TextChanged (find "draft", "Keep business logic in OCaml"));
        emit (P.Press (find "add"));
        emit (P.ToggleChanged (find "toggle-1", true));
        emit (P.Press (find "reverse"));
        List.iter
          (fun item ->
            Printf.printf "%s [%s] %s\n" item.id
              (if item.done_ then "x" else " ")
              item.title)
          (Lui_app.model app).items
      end)
