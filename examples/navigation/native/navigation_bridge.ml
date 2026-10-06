open Lui_protocol

type route = Detail of int

let current_app = ref None
let latest_patch = ref ""
let root_mounts = ref 0
let detail_mounts = ref 0
let root_counter = ref None
let rows = ref [||]
let counter_slot = Signal.state_slot "root-counter"
let detail_slot = Signal.state_slot "detail-counter"

let view _context path_signal send =
  let open Lui_elements in
  let root context parent =
    incr root_mounts;
    Printf.eprintf "NAV root mount=%d\n%!" !root_mounts;
    Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
        Printf.eprintf "NAV root disposed\n%!");
    let count =
      Signal.state_at context.Lui_ui.ui_scheduler context.Lui_ui.ui_state_scope
        counter_slot 0
    in
    root_counter := Some count;
    rows :=
      Array.init 300 (fun index ->
          Signal.state context.Lui_ui.ui_scheduler
            (Printf.sprintf "Row %03d" index));
    column ~grow:1.
      [
        text ~value:"Navigation retention demo" [];
        text ~accessibility_identifier:"root-counter"
          ~value_signal:
            (Signal.map
               (fun n ->
                 Printf.sprintf "Root local counter: %d / mounts: %d" n
                   !root_mounts)
               (Signal.value count))
          [];
        button ~text:"Increment root"
          ~on_press:(fun _ -> Signal.update count succ)
          [];
        list ~grow:1. ~style:`plain
          (Array.to_list
             (Array.mapi
                (fun index state ->
                  list_item ~key:(string_of_int index)
                    ~accessibility_identifier:("row-" ^ string_of_int index)
                    ~text_signal:(Signal.value state)
                    ~on_press:(fun _ ->
                      ignore
                        (send
                           (Lui_navigation.Path.push (Detail index)
                              (Signal.sample path_signal))))
                    [])
                !rows));
      ]
      context parent
  in
  Lui_navigation.navigation_stack ~key:"retention-demo" ~path_signal
    ~on_path_change:(fun path ->
      Printf.eprintf "NAV native committed length=%d\n%!"
        (List.length (Lui_navigation.Path.entries path));
      ignore (send path))
    ~root
    ~destination:(fun entry context parent ->
      incr detail_mounts;
      let (Detail row) = entry.Lui_navigation.route in
      Printf.eprintf "NAV detail mount=%d id=%s row=%d\n%!" !detail_mounts
        entry.id row;
      Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
          Printf.eprintf "NAV detail disposed id=%s\n%!" entry.id);
      let count =
        Signal.state_at context.Lui_ui.ui_scheduler
          context.Lui_ui.ui_state_scope detail_slot 0
      in
      column ~gap:16 ~padding:20
        [
          text ~value:(Printf.sprintf "Detail row %03d (%s)" row entry.id) [];
          text ~accessibility_identifier:"detail-counter"
            ~value_signal:
              (Signal.map
                 (fun n -> "Detail local counter: " ^ string_of_int n)
                 (Signal.value count))
            [];
          button ~text:"Increment detail"
            ~on_press:(fun _ -> Signal.update count succ)
            [];
          button ~text:"Edit covered root counter"
            ~on_press:(fun _ ->
              Option.iter (fun state -> Signal.update state succ) !root_counter)
            [];
          button ~text:"Edit covered row"
            ~on_press:(fun _ ->
              Signal.set !rows.(row) (Printf.sprintf "Row %03d edited" row))
            [];
          button ~text:"Push same row"
            ~on_press:(fun _ ->
              ignore
                (send
                   (Lui_navigation.Path.push entry.route
                      (Signal.sample path_signal))))
            [];
          button ~text:"Programmatic pop"
            ~on_press:(fun _ ->
              ignore
                (send (Lui_navigation.Path.pop (Signal.sample path_signal))))
            [];
          button ~text:"Pop to root"
            ~on_press:(fun _ -> ignore (send Lui_navigation.Path.empty))
            [];
        ]
        context parent)
    ()

let app () = Option.get !current_app

let initialize _platform _host =
  latest_patch := "";
  let backend =
    {
      backend_profile = profile IOS SwiftUIHost;
      apply_batch =
        (fun batch ->
          Printf.eprintf "NAV patch ops=%d\n%!" (List.length batch.ops);
          latest_patch := Lui_wire.encode_batch batch;
          true);
    }
  in
  let value =
    Lui_app.create_with_extensions backend
      (Lui_navigation.registry ())
      Lui_navigation.Path.empty
      (fun _ path -> path)
      view
  in
  current_app := Some value;
  ignore (Lui_app.start value);
  ignore (Lui_app.flush value);
  !latest_patch

let dispatch event =
  latest_patch := "";
  ignore (Lui_app.dispatch_event (app ()) event);
  ignore (Lui_app.flush (app ()));
  !latest_patch

let () =
  Printexc.record_backtrace true;
  Callback.register "lui_ocaml_init" initialize;
  Callback.register "lui_ocaml_press" (fun node -> dispatch (Press node));
  Callback.register "lui_ocaml_appear" (fun node -> dispatch (Appear node));
  Callback.register "lui_ocaml_press_detail" (fun node x y modifiers button target_class ->
      dispatch
        (PressDetail (node, {x; y; modifiers; button; target_class})));
  Callback.register "lui_ocaml_pointer_down" (fun node x y modifiers button target_class ->
      dispatch
        (PointerDown (node, {x; y; modifiers; button; target_class})));
  Callback.register "lui_ocaml_pointer_up" (fun node x y modifiers button target_class ->
      dispatch
        (PointerUp (node, {x; y; modifiers; button; target_class})));
  Callback.register "lui_ocaml_pointer_enter" (fun node ->
      dispatch (PointerEnter node));
  Callback.register "lui_ocaml_pointer_leave" (fun node ->
      dispatch (PointerLeave node));
  Callback.register "lui_ocaml_context_menu_press" (fun node x y modifiers button target_class ->
      dispatch
        (ContextMenuPress (node, {x; y; modifiers; button; target_class})));
  let extension_event node identifier name json =
    Printf.eprintf "NAV host event %s %s\n%!" name json;
    dispatch
      (ExtensionEvent (node, identifier, name, Lui_json.parse_values json))
  in
  Callback.register "lui_ocaml_extension_event" extension_event;
  Callback.register "lui_ocaml_dispose" (fun () ->
      latest_patch := "";
      ignore (Lui_app.dispose (app ()));
      !latest_patch);
  Callback.register "lui_ocaml_root_node" (fun () -> Lui_app.root_node (app ()))
