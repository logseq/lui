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
    let style element name value =
      Lui_web_util.set_style
        (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
        name value
    in
    let rows = ref [||] in
    let last_token = ref None in
    let pending_token = ref None in
    let pending_lookup = ref None in
    let pending_frame = ref None in
    let disposed = ref false in
    let last_range = ref None in
    (* Baseline: mounted at top and not yet at bottom — the first
       computed edge state only emits on a real transition, so a
       mount-time top position does not falsely unpin the tail-follow
       before the initial scroll lands. *)
    let last_edges = ref (Some (true, false)) in
    let last_edge_offset = ref (-1.) in
    let emit event = ignore (!(renderer.web_event_handler) event) in
    let property = Store.property renderer.web_store node in
    let text prop fallback =
      match property prop with
      | Some (StringValue value) -> value
      | _ -> fallback
    in
    (* The list IS the scroll container when scroll anchoring or
       visible-range tracking is in play; plain lists stay in flow. *)
    if
      property TrackVisibleRange = Some (BoolValue true)
      || property ScrollAnchor <> None
      || property ScrollTarget <> None
    then begin
      style root "overflow" "auto";
      style root "min-height" "0";
      style root "min-width" "0"
    end;
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
        end;
        let off = W.Element.scrollTop root in
        let edges =
          ( off <= 2.
          , off +. float_of_int (W.Element.clientHeight root)
            >= float_of_int (W.Element.scrollHeight root) -. 2. )
        in
        (* Only real offset transitions emit. When the bottom edge is
           lost while the offset is unchanged, the cause is geometry
           growth — re-anchor the tail so pinned transcripts keep
           following; user-unpinned positions are preserved because
           their offset does change. *)
        (match !last_edges with
         | Some (_, true)
           when (not (snd edges)) && !last_edge_offset = off ->
             W.Element.setScrollTop root
               (float_of_int (W.Element.scrollHeight root)
                -. float_of_int (W.Element.clientHeight root))
         | _ ->
             if off <> !last_edge_offset then begin
               last_edge_offset := off;
               if !last_edges <> Some edges then begin
                 last_edges := Some edges;
                 emit (ScrollEdges (node, fst edges, snd edges))
               end
             end)
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
    (* Persistent scroll intent, like the virtual widget: recomputes
       the target's live geometry on each attempt and retries on
       scroll/frame boundaries until the aligned edge is reached, the
       token is superseded, the row proves absent after committed
       children populate, or the settle budget elapses. *)
    let attempt () =
      match !pending_lookup with
      | None -> ()
      | Some (token, target_key, anchor, animated) -> (
          let target =
            Array.find_opt
              (fun id ->
                Store.property renderer.web_store id KeyValue
                = Some (StringValue target_key))
              !rows
          in
          match target with
          | None ->
              if Array.length !rows > 0 then begin
                pending_lookup := None;
                emit (ScrollCompleted (node, token, "missing-target"))
              end
          | Some target ->
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
                match anchor with
                | "center" -> top -. ((viewport -. height) /. 2.)
                | "bottom" -> top -. viewport +. height
                | _ -> top
              in
              let destination =
                max 0.
                  (min position
                     (float_of_int (W.Element.scrollHeight root) -. viewport))
              in
              (* Definitive landing: the scroller reaches the clamped
                 destination for the requested anchor — one-sided edge
                 tests accept targets on the wrong side of the viewport
                 and unmeasured (zero-height) rows can never satisfy
                 them. *)
              let landed =
                W.DomRect.height rect > 0.5
                && abs_float (W.Element.scrollTop root -. destination)
                   < 1.
              in
              if landed then begin
                pending_lookup := None;
                emit (ScrollCompleted (node, token, "succeeded"))
              end
              else
                scroll_to root
                  (scroll_options ~top:destination
                     ~behavior:(if animated then "smooth" else "instant")))
    in
    let rec request () =
      match property ScrollToken with
      | Some (IntValue token) when !last_token <> Some token ->
          last_token := Some token;
          cancel_frame ();
          (match !pending_lookup with
           | Some (prev, _, _, _) ->
               emit (ScrollCompleted (node, prev, "cancelled"))
           | None -> ());
          pending_lookup :=
            Some
              (token, text ScrollTarget "", text ScrollAnchor "top",
               property ScrollAnimated = Some (BoolValue true));
          attempt ();
          settle 0
      | _ -> ()
    and settle frames =
      pending_frame :=
        Some
          (Webapi.requestCancellableAnimationFrame (fun _ ->
               pending_frame := None;
               if (not !disposed) && !pending_lookup <> None then begin
                 range ();
                 attempt ();
                 if !pending_lookup <> None then
                   if frames >= 120 then begin
                     let (token, _, _, _) = Option.get !pending_lookup in
                     pending_lookup := None;
                     emit (ScrollCompleted (node, token, "cancelled"))
                   end
                   else settle (frames + 1)
               end))
    in
        rows := Array.of_list (collect node []);
    (* A lookup deferred while children committed re-runs the request:
       the target may now exist (retry) or be confirmed absent. *)

    let refresh structural =
      if not !disposed then begin
        if structural then rows := Array.of_list (collect node []);
        request ();
        attempt ();
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
