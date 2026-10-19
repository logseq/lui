external set_timeout : (unit -> unit) -> int -> unit = "setTimeout"
  [@@mel.scope "window"]

let location_search : string = [%mel.raw "window.location.search"]

let main host =
  let renderer = Lui_web.create host in
  let app =
    Lui_app.create (Lui_web.backend renderer)     (Model.initial
        ~tall:(String.contains location_search 't')
        ~list_mode:(String.contains location_search 'l')
        ~debug:(String.contains location_search 'd')
        ~plain:(String.contains location_search 'v')
        ~replay:(String.contains location_search 'r'))
      Model.update
      View.view
  in
  ignore
    (Lui_web.set_event_handler renderer (fun event ->
       ignore (Lui_app.dispatch_event app event);
       Lui_app.flush app));
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  Lui_web.mount renderer (Lui_app.root_node app) host;
  let rec tick () =
    set_timeout (fun () ->
      ignore (Lui_app.send app Model.Tick);
      ignore (Lui_app.flush app);
      tick ()) 120
  in
  tick ();
  true
