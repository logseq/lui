open Lui_protocol
open Lui_web_types
module W = Webapi.Dom
module Store = Lui_web_store

type scroll_options

external scroll_options : top:float -> behavior:string -> scroll_options = ""
[@@mel.obj]

external scroll_to : W.Element.t -> scroll_options -> unit = "scrollTo"
[@@mel.send]

let install renderer node =
  if not (Hashtbl.mem renderer.web_lists node) then begin
    let root = Lui_web_nodes.dom_node renderer node in
    let rows = ref [||] in
    let last_token = ref None in
    let pending_token = ref None in
    let pending_frame = ref None in
    let disposed = ref false in
    let last_range = ref None in
    let emit event = ignore (!(renderer.web_event_handler) event) in
    let property = Store.property renderer.web_store node in
    let text prop fallback =
      match property prop with
      | Some (StringValue value) -> value
      | _ -> fallback
    in
    let rec collect node tail =
      match Store.node renderer.web_store node with
      | Some current when Store.standard_kind_is current ListItem ->
          node :: tail
      | Some current ->
          List.fold_right collect
            (Lui_sequence.to_list current.retained_children)
            tail
      | None -> tail
    in
    let range () =
      if property TrackVisibleRange = Some (BoolValue true) then begin
        let bounds = W.Element.getBoundingClientRect root in
        let lower predicate =
          let rec search lo hi =
            if lo >= hi then lo
            else
              let mid = (lo + hi) / 2 in
              let row = Lui_web_nodes.dom_node renderer !rows.(mid) in
              if predicate (W.Element.getBoundingClientRect row) then
                search lo mid
              else search (mid + 1) hi
          in
          search 0 (Array.length !rows)
        in
        let first =
          lower (fun rect -> W.DomRect.bottom rect > W.DomRect.top bounds)
        in
        let last =
          lower (fun rect -> W.DomRect.top rect >= W.DomRect.bottom bounds)
        in
        let first, last = if first >= last then (0, 0) else (first, last) in
        if !last_range <> Some (first, last) then begin
          last_range := Some (first, last);
          emit (VisibleRange (node, first, last))
        end
      end
      else last_range := None
    in
    let cancel_frame () =
      Option.iter Webapi.cancelAnimationFrame !pending_frame;
      pending_frame := None
    in
    let complete outcome =
      match !pending_token with
      | None -> ()
      | Some token ->
          pending_token := None;
          emit (ScrollCompleted (node, token, outcome))
    in
    let request () =
      match property ScrollToken with
      | Some (IntValue token) when !last_token <> Some token -> (
          last_token := Some token;
          cancel_frame ();
          complete "superseded";
          let target_key = text ScrollTarget "" in
          let target =
            Array.find_opt
              (fun id ->
                Store.property renderer.web_store id KeyValue
                = Some (StringValue target_key))
              !rows
          in
          match target with
          | None -> emit (ScrollCompleted (node, token, "missing-target"))
          | Some target ->
              pending_token := Some token;
              let row = Lui_web_nodes.dom_node renderer target in
              let bounds = W.Element.getBoundingClientRect root in
              let rect = W.Element.getBoundingClientRect row in
              let viewport = float_of_int (W.Element.clientHeight root) in
              let top =
                W.Element.scrollTop root +. W.DomRect.top rect
                -. W.DomRect.top bounds
              in
              let height = W.DomRect.height rect in
              let position =
                match text ScrollAnchor "top" with
                | "center" -> top -. ((viewport -. height) /. 2.)
                | "bottom" -> top -. viewport +. height
                | _ -> top
              in
              let destination =
                max 0.
                  (min position
                     (float_of_int (W.Element.scrollHeight root) -. viewport))
              in
              let animated = property ScrollAnimated = Some (BoolValue true) in
              scroll_to root
                (scroll_options ~top:destination
                   ~behavior:(if animated then "smooth" else "instant"));
              let rec settle frames =
                pending_frame :=
                  Some
                    (Webapi.requestCancellableAnimationFrame (fun _ ->
                         pending_frame := None;
                         if (not !disposed) && !pending_token = Some token then begin
                           range ();
                           if
                             abs_float (W.Element.scrollTop root -. destination)
                             < 1.
                           then complete "succeeded"
                           else if frames >= 120 then complete "cancelled"
                           else settle (frames + 1)
                         end))
              in
              settle 0)
      | _ -> ()
    in
    rows := Array.of_list (collect node []);
    let refresh structural =
      if not !disposed then begin
        if structural then rows := Array.of_list (collect node []);
        request ();
        range ()
      end
    in
    let range_frame = ref None in
    let on_scroll _ =
      if !range_frame = None then
        range_frame :=
          Some
            (Webapi.requestCancellableAnimationFrame (fun _ ->
                 range_frame := None;
                 if not !disposed then range ()))
    in
    W.Element.addEventListener "scroll" on_scroll root;
    let observer = Webapi.ResizeObserver.make (fun _ -> on_scroll ()) in
    Webapi.ResizeObserver.observe observer root;
    let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
    Hashtbl.replace renderer.web_cleanups node (fun () ->
        disposed := true;
        cancel_frame ();
        Option.iter Webapi.cancelAnimationFrame !range_frame;
        Webapi.ResizeObserver.disconnect observer;
        W.Element.removeEventListener "scroll" on_scroll root;
        Hashtbl.remove renderer.web_lists node;
        complete "cancelled";
        Option.iter (fun cleanup -> cleanup ()) previous_cleanup);
    Hashtbl.replace renderer.web_lists node refresh
  end
