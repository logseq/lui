open Lui_protocol
open Lui_web_types
module W = Webapi.Dom
module Store = Lui_web_store
module V = Lui_web_virtualizer

external connected : W.Element.t -> bool = "isConnected" [@@mel.get]

external next_element : W.Element.t -> W.Element.t Js.Nullable.t
  = "nextElementSibling"
[@@mel.get]

let install renderer node ~materialize ~unmount =
  if not (Hashtbl.mem renderer.web_virtual_lists node) then begin
    let root = Lui_web_nodes.dom_node renderer node in
    let spacer = W.Document.createElement "div" renderer.web_document in
    let style element name value =
      Lui_web_util.set_style
        (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
        name value
    in
    style root "overflow" "auto";
    style root "display" "block";
    style root "overflow-anchor" "none";
    (* A virtual scroller must never expand its flex parent past the
       viewport; min-*:0 lets grow-bound layouts shrink it to the
       remaining space so siblings (e.g. a composer) stay visible. *)
    style root "min-height" "0";
    style root "min-width" "0";
    style spacer "position" "relative";
    style spacer "width" "100%";
    W.Element.appendChild (W.Element.asNode spacer) root;
    let rows = ref [||] in
    let sequence = ref Lui_sequence.empty in
    let positions = Hashtbl.create 16 in
    let mounted = Hashtbl.create 16 in
    let disposed = ref false in
    let updating = ref false in
    let pending_render = ref false in
    let render_ref = ref (fun () -> ()) in
    let emit event = ignore (!(renderer.web_event_handler) event) in
    let property = Store.property renderer.web_store node in
    let text prop fallback =
      match property prop with
      | Some (StringValue value) -> value
      | _ -> fallback
    in
    let last_token = ref None in
    let last_range = ref None in
    (* Baseline: mounted at top and not yet at bottom — the first
       computed edge state only emits on a real transition, so a
       mount-time top position does not falsely unpin the tail-follow
       before the initial scroll lands. *)
    let last_edges = ref (Some (true, false)) in
    let last_edge_offset = ref (-1.) in
    (* Pin ownership: only an issued end-aligned scroll intent grants
       the widget a tail pin. Plain lists and unpinned user positions
       must never be re-anchored on geometry-only changes. *)
    let tail_pinned = ref false in
    (* The scrollTop most recently written programmatically, so real
       user offsets can release the pin without false positives. *)
    let prog_scroll = ref (-1.) in
        let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
    let live_rows () =
      Hashtbl.fold (fun id _ rows -> id :: rows) mounted []
      |> List.sort (fun a b ->
          Int.compare (Hashtbl.find positions a) (Hashtbl.find positions b))
    in
    (* update_tree_roving rewrites aria/tabindex on every item, but its
       inputs are only the store snapshot, the mounted row ids, and the
       focused element — scroll-driven onChange ticks leave all three
       alone, so identical inputs skip the pass entirely. *)
    let last_roving_inputs = ref None in
    let same_element a b =
      match (a, b) with
      | None, None -> true
      | Some left, Some right -> left == right
      | _ -> false
    in
    let sync_tree_roving () =
      match Store.tree_ancestor renderer node with
      | Some tree ->
          let generation = Store.generation renderer.web_store in
          let mounted_ids = live_rows () in
          let active = W.HtmlDocument.activeElement document in
          let unchanged =
            match !last_roving_inputs with
            | Some (gen, ids, last_active) ->
                gen = generation && ids = mounted_ids
                && same_element last_active active
            | None -> false
          in
          if not unchanged then begin
            last_roving_inputs := Some (generation, mounted_ids, active);
            Lui_web_focus.update_tree_roving renderer tree
          end
      | None -> last_roving_inputs := None
    in
    let focused_index () =
      match W.HtmlDocument.activeElement document with
      | None -> None
      | Some active ->
          Hashtbl.fold
            (fun id wrapper result ->
              if W.Element.contains (W.Element.asNode active) wrapper then
                Hashtbl.find_opt positions id
              else result)
            mounted None
    in
    let range_extractor range =
      let indices = V.default_range range in
      match focused_index () with
      | Some index when not (Array.exists (( = ) index) indices) ->
          let result = Array.append indices [| index |] in
          Array.sort Int.compare result;
          result
      | _ -> indices
    in
    let key = ref (fun index -> string_of_int !rows.(index)) in
    let estimate index =
      match Store.property renderer.web_store !rows.(index) HeightValue with
      | Some (IntValue height) when height > 0 -> float_of_int height
      | _ -> 32.
    in
    let update_rows () =
      match Store.node renderer.web_store node with
      | Some current when current.retained_children != !sequence ->
          sequence := current.retained_children;
          rows := Array.of_list (Lui_sequence.to_list !sequence);
          let current_rows = !rows in
          (key := fun index -> string_of_int current_rows.(index));
          Hashtbl.clear positions;
          Array.iteri (fun index id -> Hashtbl.replace positions id index) !rows
      | _ -> ()
    in
    let make_options () =
      let height =
        match Store.property renderer.web_store node HeightValue with
        | Some (IntValue height) when height > 0 -> float_of_int height
        | _ -> 300.
      in
      let gap =
        match Store.property renderer.web_store node Gap with
        | Some (IntValue value) -> float_of_int value
        | _ -> 0.
      in
      V.options ~count:(Array.length !rows)
        ~getScrollElement:(fun () -> Js.Nullable.return root)
        ~estimateSize:estimate ~getItemKey:!key ~scrollToFn:V.element_scroll
        ~observeElementRect:V.observe_element_rect
        ~observeElementOffset:V.observe_element_offset
        ~onChange:(fun _ _ -> !render_ref ())
        ~rangeExtractor:(fun range -> range_extractor range)
        ~initialRect:(V.rect ~width:400. ~height)
        ~overscan:5 ~gap ()
    in
    update_rows ();
    let virtualizer = V.make (make_options ()) in
    let pending_scroll = ref None in
    let reading_anchor =
      Lui_web_virtual_anchor.create root mounted positions virtualizer
    in
    let complete_pending outcome =
      match !pending_scroll with
      | Some (token, _, _, _, _) ->
          pending_scroll := None;
          if outcome = "missing-target" then tail_pinned := false;
          emit (ScrollCompleted (node, token, outcome))
      | None -> ()
    in
    (* Retryable scroll intent: executes immediately when the token
       lands, retries on renders while pending, completes via
       [virtualizer.range] containment, or reports missing-target
       (row absent after a few renders) / cancelled (superseded or
       unreachable). *)
    let attempt_scroll () =
      match !pending_scroll with
      | None -> ()
      | Some (token, target_key, align, behavior, tries) -> (
          let index =
            Array.find_opt
              (fun id ->
                Store.property renderer.web_store id KeyValue
                = Some (StringValue target_key))
              !rows
          in
          let index =
            Option.bind index (fun id -> Hashtbl.find_opt positions id)
          in
          (* An absent target resolves at the committed-tree boundary:
             once rows are populated a missing key reports immediately. *)
          match index with
          | None ->
              if Array.length !rows > 0 then complete_pending "missing-target"
              else
                pending_scroll :=
                  Some (token, target_key, align, behavior, tries + 1)
          | Some index -> (
              (* Real DOM geometry decides landing — scrollTop applies
                 synchronously even for "auto" jumps. A pending intent
                 survives until it lands, is superseded (cancelled), the
                 row proves absent after committed children populate
                 (missing-target), or the node disposes. scrollToIndex
                 is idempotent while pending; repeated issues converge
                 once the row is measured. *)
              let row_id = !rows.(index) in
              let landed =
                match Hashtbl.find_opt mounted row_id with
                | Some wrapper ->
                    let bounds = W.Element.getBoundingClientRect root
                    and r = W.Element.getBoundingClientRect wrapper in
                    let viewport =
                      float_of_int (W.Element.clientHeight root) in
                    let top =
                      W.Element.scrollTop root +. W.DomRect.top r
                      -. W.DomRect.top bounds
                    and height = W.DomRect.height r in
                    let position =
                      match align with
                      | "end" -> top -. viewport +. height
                      | "center" -> top -. ((viewport -. height) /. 2.)
                      | _ -> top
                    in
                    let destination =
                      max 0.
                        (min position
                           (float_of_int (W.Element.scrollHeight root)
                            -. viewport))
                    in
                    W.DomRect.height r > 0.5
                    && abs_float (W.Element.scrollTop root -. destination)
                       < 1.
                | None -> false
              in
              if landed then complete_pending "succeeded"
              else begin
                V.scroll_to_index virtualizer index
                  (V.scroll_to_index_options ~align ~behavior);
                prog_scroll := W.Element.scrollTop root;
                pending_scroll :=
                  Some (token, target_key, align, behavior, tries)
              end))
    in
    let rec render () =
      if !updating then pending_render := true
      else if not !disposed then begin
        updating := true;
        Fun.protect
          ~finally:(fun () -> updating := false)
          (fun () ->
            let items = V.items virtualizer in
            let keep = Hashtbl.create (Array.length items) in
            Array.iter
              (fun item ->
                let index = V.item_index item in
                let id = !rows.(index) in
                Hashtbl.replace keep id ();
                let wrapper =
                  match Hashtbl.find_opt mounted id with
                  | Some wrapper -> wrapper
                  | None ->
                      let wrapper =
                        W.Document.createElement "div" renderer.web_document
                      in
                      style wrapper "position" "absolute";
                      style wrapper "top" "0";
                      style wrapper "left" "0";
                      style wrapper "width" "100%";
                      (* Publish membership before initializing the row, including
                   nested virtual lists and extension event listeners. *)
                      Hashtbl.replace mounted id wrapper;
                      W.Element.appendChild
                        (W.Element.asNode (materialize id))
                        wrapper;
                      W.Element.appendChild (W.Element.asNode wrapper) spacer;
                      wrapper
                in
                W.Element.setAttribute "data-index" (string_of_int index)
                  wrapper;
                style wrapper "transform"
                  ("translateY(" ^ Js.Float.toString (V.item_start item) ^ "px)");
                if
                  connected root
                  && W.DomRect.height (W.Element.getBoundingClientRect wrapper)
                     > 0.
                then V.measure virtualizer (Js.Nullable.return wrapper))
              items;
            Hashtbl.fold
              (fun id wrapper acc ->
                if Hashtbl.mem keep id then acc else (id, wrapper) :: acc)
              mounted []
            |> List.iter (fun (id, wrapper) ->
                Hashtbl.remove mounted id;
                ignore (W.Element.removeChild (W.Element.asNode wrapper) spacer);
                unmount id);
            (* Keep native Tab order in retained order. Move siblings around a
               focused row so inserting earlier rows does not blur it. *)
            let active = W.HtmlDocument.activeElement document in
            let anchor = ref None in
            for index = Array.length items - 1 downto 0 do
              let wrapper =
                Hashtbl.find mounted !rows.(V.item_index items.(index))
              in
              let focused =
                Option.fold ~none:false
                  ~some:(fun active ->
                    W.Element.contains (W.Element.asNode active) wrapper)
                  active
              in
              let next = Js.Nullable.toOption (next_element wrapper) in
              let ordered =
                match (next, !anchor) with
                | None, None -> true
                | Some next, Some anchor -> next == anchor
                | _ -> false
              in
              (if (not focused) && not ordered then
                 match !anchor with
                 | None ->
                     W.Element.appendChild (W.Element.asNode wrapper) spacer
                 | Some anchor ->
                     ignore
                       (W.Element.insertBefore (W.Element.asNode wrapper)
                          (W.Element.asNode anchor) spacer));
              anchor := Some wrapper
            done;
            V.measure virtualizer Js.Nullable.null;
            style spacer "height"
              (Js.Float.toString (V.total_size virtualizer) ^ "px");
            sync_tree_roving ();
            if property TrackVisibleRange = Some (BoolValue true) then begin
              (* [virtualizer.range] reports the rows actually
                 intersecting the viewport, excluding overscan padding
                 and focus-retained rows, so pin detection and history
                 paging key off what the user can see. *)
              match Js.Nullable.toOption (V.item_range virtualizer) with
              | Some r ->
                  let first = V.range_start r in
                  let last = V.range_end r in
                  if !last_range <> Some (first, last) then begin
                    last_range := Some (first, last);
                    emit (VisibleRange (node, first, last))
                  end
              | None -> ()
            end
            else last_range := None);
            (match
               ( Js.Nullable.toOption (V.scroll_offset virtualizer),
                 Js.Nullable.toOption (V.scroll_rect virtualizer) ) with
             | Some off, Some rect ->
                 let bottom = off +. V.rect_height rect in
                 let edges =
                   (off <= 2., bottom >= V.total_size virtualizer -. 2.)
                 in
                 (* Only real offset transitions emit. When the bottom
                    edge is lost while the offset is unchanged, the
                    cause is geometry growth rather than user scroll —
                    re-anchor the tail so pinned transcripts keep
                    following (user-unpinned positions are preserved
                    since their offset does change). *)
                 (* A pinned tail that is no longer at the bottom while
                    the offset stands still means geometry moved, not
                    the user — re-anchor. [tail_pinned] is owned by
                    issued end-aligned intents, so plain lists and
                    user-held positions are unaffected. *)
                 let tail_lost_at_same_offset =
                   !tail_pinned && not (snd edges)
                   && (!last_edge_offset = off
                       || (!prog_scroll >= 0.
                           && abs_float (off -. !prog_scroll) < 2.))
                 in
                 if tail_lost_at_same_offset then begin
                   let dest =
                     float_of_int (W.Element.scrollHeight root)
                     -. V.rect_height rect
                   in
                   prog_scroll := dest;
                   W.Element.setScrollTop root dest
                 end
                 else if off <> !last_edge_offset then begin
                   (* Offset changes are ours while an intent is
                      pending or when they land on the last
                      programmatic write; anything else is user
                      scroll and releases the tail pin. *)
                   let programmatic =
                     !pending_scroll <> None
                     || (!prog_scroll >= 0.
                         && abs_float (off -. !prog_scroll) < 2.)
                   in
                   last_edge_offset := off;
                   if !last_edges <> Some edges then begin
                     last_edges := Some edges;
                     emit
                       (ScrollEdges (node, fst edges, snd edges))
                   end;
                   if (not programmatic) && not (snd edges) then
                     tail_pinned := false
                 end
             | _ -> ());
            (if !pending_scroll = None then
               Lui_web_virtual_anchor.restore reading_anchor
                 ~scrolled:(fun top -> prog_scroll := top));
            attempt_scroll ();
        if !pending_render then begin
          pending_render := false;
          render ()
        end
      end
    in
    render_ref := render;
    let cleanup = V.did_mount virtualizer in
    (* A scroll request supersedes any pending intent, executes
       immediately (a settled list may never render again), and keeps a
       pending intent retried on subsequent renders until the target
       row enters the visible range. *)
    let request () =
      match property ScrollToken with
      | Some (IntValue token) when !last_token <> Some token ->
          last_token := Some token;
          Lui_web_virtual_anchor.cancel reading_anchor;
          complete_pending "cancelled";
          let align =
            match text ScrollAnchor "top" with
            | "center" -> "center"
            | "bottom" -> "end"
            | _ -> "start"
          in
          let behavior =
            if property ScrollAnimated = Some (BoolValue true) then "smooth"
            else "auto"
          in
          tail_pinned := align = "end";
          pending_scroll :=
            Some (token, text ScrollTarget "", align, behavior, 0);
          attempt_scroll ()
      | _ -> ()
    in
    let refresh () =
      if not !disposed then begin
        (* Preserve measured retained identity only for a prepend. A later
           append must not keep compensating geometry for an older change. *)
        let previous_sequence = !sequence in
        let previous_first =
          if Array.length !rows = 0 then None else Some !rows.(0)
        in
        let anchor = Lui_web_virtual_anchor.capture reading_anchor in
        update_rows ();
        if previous_sequence != !sequence then begin
          Lui_web_virtual_anchor.cancel reading_anchor;
          match Option.bind previous_first (Hashtbl.find_opt positions) with
          | Some index when index > 0 ->
              Lui_web_virtual_anchor.preserve reading_anchor anchor
          | _ -> ()
        end;
        V.set_options virtualizer (make_options ());
        if connected root then V.will_update virtualizer;
        render ();
        request ();
        (* Committed-tree boundary: a pending intent whose row now
           exists (or is known absent from the committed children)
           resolves here without waiting on virtualizer renders. *)
        attempt_scroll ()
      end
    in
    let cancel_anchor _ = Lui_web_virtual_anchor.cancel reading_anchor in
    let anchor_inputs = [ "wheel"; "touchstart"; "pointerdown"; "keydown" ] in
    List.iter
      (fun event -> W.Element.addEventListener event cancel_anchor root)
      anchor_inputs;
    let on_focus _ = refresh () in
    W.Element.addEventListener "focusin" on_focus root;
    W.Element.addEventListener "focusout" on_focus root;
    let dispose () =
      disposed := true;
      cleanup ();
      Lui_web_virtual_anchor.cancel reading_anchor;
      List.iter
        (fun event -> W.Element.removeEventListener event cancel_anchor root)
        anchor_inputs;
      W.Element.removeEventListener "focusin" on_focus root;
      W.Element.removeEventListener "focusout" on_focus root;
      Hashtbl.remove renderer.web_virtual_lists node
    in
    Hashtbl.replace renderer.web_virtual_lists node
      {
        refresh_virtual = refresh;
        resize_virtual_row =
          (fun id ->
            match Hashtbl.find_opt positions id, Hashtbl.find_opt mounted id with
            | Some _, Some wrapper when connected root
                && W.DomRect.height (W.Element.getBoundingClientRect wrapper) > 0. ->
                V.measure virtualizer (Js.Nullable.return wrapper)
            | Some index, _ -> V.resize_item virtualizer index (estimate index)
            | None, _ -> ());
        dispose_virtual = dispose;
        virtual_row_live = (fun id -> Hashtbl.mem mounted id);
        virtual_live_rows = live_rows;
      };
    refresh ()
  end
