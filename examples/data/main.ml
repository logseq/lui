module P = Lui_protocol
module E = Data_view.Edn

type todo = { id : string; title : string; done_ : bool }
type model = { draft : string; items : todo list; next_id : int }

type action =
  | Draft of string
  | Add
  | Toggle of string * bool
  | Rename of string * string
  | Remove of string
  | Reverse

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

let actions = [ "draft"; "add"; "toggle"; "rename"; "remove"; "reverse" ]

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
    | _ -> invalid_arg ("invalid OCaml action " ^ name)
  in
  ignore (send action)

let read path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: main.exe view.edn [--mount-only]";
    exit 2);
  let document =
    match Data_view.compile ~actions (read Sys.argv.(1)) with
    | Ok view -> view
    | Error error ->
        prerr_endline error;
        exit 2
  in
  let backend =
    {
      P.backend_profile = P.generic_profile ();
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
          Printf.printf "generation=%d create=%d set=%d move=%d drop=%d\n%!"
            batch.generation creates sets moves drops;
          true);
    }
  in
  let mount_only =
    Array.length Sys.argv >= 3 && Sys.argv.(2) = "--mount-only"
  in
  let initial = { draft = ""; items = []; next_id = 1 } in
  let initial =
    if mount_only then update (update initial (Draft "Schema-driven UI")) Add
    else initial
  in
  let app =
    Lui_app.create backend initial update (fun _ model send ->
        Data_view.render document ~model ~project ~dispatch:(dispatch send))
  in
  Fun.protect
    ~finally:(fun () -> ignore (Lui_app.dispose app))
    (fun () ->
      ignore (Lui_app.start app);
      ignore (Lui_app.flush app);
      if not mount_only then begin
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
