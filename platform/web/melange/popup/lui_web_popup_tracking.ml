module W = Webapi.Dom

type viewport
type trackers

external make_trackers : unit -> trackers = "WeakMap" [@@mel.new]
external get_tracker : trackers -> Dom.element -> (unit -> unit) option
  = "get" [@@mel.send] [@@mel.return undefined_to_opt]
external set_tracker : trackers -> Dom.element -> (unit -> unit) -> unit
  = "set" [@@mel.send]
external delete_tracker : trackers -> Dom.element -> unit
  = "delete" [@@mel.send]

external visual_viewport : W.Window.t -> viewport option = "visualViewport"
  [@@mel.get] [@@mel.return nullable]
external viewport_left : viewport -> float = "offsetLeft" [@@mel.get]
external viewport_top : viewport -> float = "offsetTop" [@@mel.get]
external viewport_width : viewport -> float = "width" [@@mel.get]
external viewport_height : viewport -> float = "height" [@@mel.get]
external viewport_listen : viewport -> string -> (Dom.event -> unit) -> unit
  = "addEventListener" [@@mel.send]
external viewport_unlisten : viewport -> string -> (Dom.event -> unit) -> unit
  = "removeEventListener" [@@mel.send]
external request_frame : W.Window.t -> (float -> unit) -> int
  = "requestAnimationFrame" [@@mel.send]
external cancel_frame : W.Window.t -> int -> unit
  = "cancelAnimationFrame" [@@mel.send]
external connected : Dom.element -> bool = "isConnected" [@@mel.get]
external parent_element : Dom.element -> Dom.element option = "parentElement"
  [@@mel.get] [@@mel.return nullable]
external listen_scroll : Dom.element -> string -> (Dom.event -> unit) -> bool -> unit
  = "addEventListener" [@@mel.send]
external unlisten_scroll : Dom.element -> string -> (Dom.event -> unit) -> bool -> unit
  = "removeEventListener" [@@mel.send]

let trackers = make_trackers ()

let stop positioner =
  match get_tracker trackers positioner with
  | None -> ()
  | Some cleanup ->
      delete_tracker trackers positioner;
      cleanup ()

let owner_window document =
  W.HtmlDocument.defaultView (W.Document.unsafeAsHtmlDocument document)

let viewport_bounds document =
  match Option.bind (owner_window document) visual_viewport with
  | Some viewport ->
      (viewport_left viewport, viewport_top viewport,
       viewport_width viewport, viewport_height viewport)
  | None ->
      let root = W.Document.documentElement document in
      (0.0, 0.0, float_of_int (W.Element.clientWidth root),
       float_of_int (W.Element.clientHeight root))

let ancestors element =
  let rec collect element result =
    match parent_element element with
    | None -> result
    | Some parent -> collect parent (parent :: result)
  in
  collect element []

let geometry element =
  let rect = W.Element.getBoundingClientRect element in
  (W.DomRect.left rect, W.DomRect.top rect,
   W.DomRect.width rect, W.DomRect.height rect)

let start ~document ~positioner ~popup ~anchor ~valid ~update ~on_invalid =
  stop positioner;
  match owner_window document with
  | None -> ()
  | Some window ->
      let active = ref true in
      let frame = ref None in
      let poll = ref None in
      let previous = ref None in
      let reveal = ref true in
      let previous_height = ref 0 in
      let chain = ancestors anchor in
      let viewport = visual_viewport window in
      let invalid () =
        not (valid ()) || not (connected anchor) || not (connected positioner)
        || let (_, _, width, height) = geometry anchor in
           (width = 0.0 && height = 0.0)
           || W.CssStyleDeclaration.getPropertyValue "visibility"
                (W.Window.getComputedStyle anchor window) = "hidden"
      in
      let refresh () =
        if !active then
          if invalid () then begin
            stop positioner;
            on_invalid ()
          end else begin
            previous := Some (geometry anchor);
            update ();
            let height = W.Element.clientHeight popup in
            if !reveal || height <> !previous_height then begin
              reveal := false;
              previous_height := height;
              let active_item =
                match W.Element.querySelector "[data-highlighted]" popup with
                | Some item -> Some item
                | None -> W.Element.querySelector ":focus" popup
              in
              match active_item with
              | None -> ()
              | Some item ->
                  let bounds = W.Element.getBoundingClientRect popup in
                  let row = W.Element.getBoundingClientRect item in
                  let delta =
                    if W.DomRect.top row < W.DomRect.top bounds then
                      W.DomRect.top row -. W.DomRect.top bounds
                    else max 0.0 (W.DomRect.bottom row -. W.DomRect.bottom bounds)
                  in
                  if delta <> 0.0 then
                    W.Element.setScrollTop popup (W.Element.scrollTop popup +. delta)
            end
          end
      in
      let schedule () =
        if !active && !frame = None then
          frame := Some (request_frame window (fun _ ->
              frame := None;
              refresh ()))
      in
      let listener _event = schedule () in
      let observer = Webapi.ResizeObserver.make (fun _ -> schedule ()) in
      let reveal_active () = reveal := true; schedule () in
      let focus_listener _event = reveal_active () in
      let highlights = W.MutationObserver.make (fun _ _ -> reveal_active ()) in
      let rec check_geometry () =
        if !active then begin
          if invalid () || !previous <> Some (geometry anchor) then schedule ();
          poll := Some (Js.Global.setTimeout ~f:check_geometry 100)
        end
      in
      let cleanup () =
        active := false;
        Option.iter (cancel_frame window) !frame;
        Option.iter Js.Global.clearTimeout !poll;
        Webapi.ResizeObserver.disconnect observer;
        W.MutationObserver.disconnect highlights;
        W.Element.removeEventListener "focusin" focus_listener popup;
        List.iter (fun ancestor ->
            unlisten_scroll ancestor "scroll" listener true) chain;
        W.Window.removeEventListener "resize" listener window;
        W.Window.removeEventListener "scroll" listener window;
        Option.iter (fun viewport ->
            viewport_unlisten viewport "resize" listener;
            viewport_unlisten viewport "scroll" listener) viewport
      in
      set_tracker trackers positioner cleanup;
      List.iter (fun ancestor ->
          listen_scroll ancestor "scroll" listener true;
          Webapi.ResizeObserver.observe observer ancestor) chain;
      Webapi.ResizeObserver.observe observer anchor;
      Webapi.ResizeObserver.observe observer popup;
      W.MutationObserver.observe (W.Element.asNode popup)
        ([%mel.obj { attributes = true; subtree = true;
                     attributeFilter = [|"data-highlighted"|] }]) highlights;
      W.Element.addEventListener "focusin" focus_listener popup;
      W.Window.addEventListener "resize" listener window;
      W.Window.addEventListener "scroll" listener window;
      Option.iter (fun viewport ->
          viewport_listen viewport "resize" listener;
          viewport_listen viewport "scroll" listener) viewport;
      schedule ();
      poll := Some (Js.Global.setTimeout ~f:check_geometry 100)
