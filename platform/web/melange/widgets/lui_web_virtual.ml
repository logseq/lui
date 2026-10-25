open Lui_protocol
open Lui_web_types
module W = Webapi.Dom
module Store = Lui_web_store
module V = Lui_web_virtualizer

external connected : W.Element.t -> bool = "isConnected" [@@mel.get]
external pointer_id : Dom.event -> int = "pointerId" [@@mel.get]

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
    let indexed = Hashtbl.create 16 in
    let placeholders = Hashtbl.create 16 in
    let held_rows = Hashtbl.create 2 in
    let composing_row = ref None in
    let disposed = ref false in
    let updating = ref false in
    let pending_render = ref false in
    let render_ref = ref (fun () -> ()) in
    let emit event = ignore (!(renderer.web_event_handler) event) in
    let property = Store.property renderer.web_store node in
    let logical_count () =
      match property VirtualTotalCount with
      | Some (IntValue count) -> count
      | _ -> Array.length !rows
    in
    let source_generation () =
      match property VirtualGeneration with
      | Some (IntValue generation) -> Some generation
      | _ -> None
    in
    let row_at index = Hashtbl.find_opt indexed index in
    let last_metadata = ref None in
    let last_window = ref None in
    let window_scheduled = ref false in
    let request_window = ref (fun () -> ()) in
    let schedule_window () =
      if source_generation () <> None && not !window_scheduled then begin
        window_scheduled := true;
        Webapi.requestAnimationFrame (fun _ ->
          window_scheduled := false;
          if not !disposed then !request_window ())
      end
    in
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
    let parent_scope () =
      Option.bind (Store.node renderer.web_store node)
        (fun current -> current.retained_parent)
    in
    let last_parent_scope = ref (parent_scope ()) in
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
    let row_containing element =
      Hashtbl.fold
        (fun id wrapper found ->
          if W.Element.contains (W.Element.asNode element) wrapper then Some id
          else found)
        mounted None
    in
    let pinned_rows () =
      let active = W.HtmlDocument.activeElement document in
      Hashtbl.fold
        (fun id wrapper pinned ->
          let focused = Option.fold ~none:false
            ~some:(fun active -> W.Element.contains (W.Element.asNode active) wrapper) active in
          let held = Hashtbl.fold (fun _ row found -> found || row = id) held_rows false in
          let portal = Lui_web_layers.retains_owner renderer.web_layers
            ~node:(fun target -> Store.descendant renderer.web_store.retained_nodes id target)
            ~element:(fun target -> W.Element.contains (W.Element.asNode target) wrapper) in
          if focused || held || !composing_row = Some id || portal then id :: pinned
          else pinned)
        mounted []
      |> List.filter (fun id -> Hashtbl.mem positions id)
      |> List.sort_uniq Int.compare
    in
    let range_extractor range =
      let indices = V.default_range range in
      let pins = List.filter_map (Hashtbl.find_opt positions) (pinned_rows ()) in
      Array.of_list (List.sort_uniq Int.compare (Array.to_list indices @ pins))
    in
    let key = ref (fun index -> string_of_int index) in
    let key_generation = ref None in
    let legacy_tuning name =
      match property DataAttrs with
      | Some (StringValue encoded) -> List.assoc_opt name (data_attrs_decode encoded)
      | _ -> None
    in
    let item_extent () =
      match property VirtualItemExtent with
      | Some (FloatValue extent) -> Some extent
      | _ -> Option.bind (legacy_tuning "data-item-extent") (fun value ->
          match float_of_string_opt value with
          | Some extent when is_finite extent && extent > 0. -> Some extent
          | _ -> None)
    in
    let overscan () =
      match property VirtualOverscan with
      | Some (IntValue count) -> count
      | _ -> Option.value ~default:5
          (Option.bind (legacy_tuning "data-overscan") (fun value ->
            match int_of_string_opt value with
            | Some count when count >= 0 -> Some count
            | _ -> None))
    in
    let estimated_extent = ref (item_extent ()) in
    let estimate index =
      match !estimated_extent with
      | Some extent -> extent
      | None ->
          match Option.bind (row_at index)
            (fun id -> Store.property renderer.web_store id HeightValue) with
          | Some (IntValue height) when height > 0 -> float_of_int height
          | _ -> 32.
    in
    let update_rows () =
      let metadata = (source_generation (), property VirtualIndices) in
      match Store.node renderer.web_store node with
      | Some current when current.retained_children != !sequence || !last_metadata <> Some metadata ->
          sequence := current.retained_children;
          last_metadata := Some metadata;
          rows := Array.of_list (Lui_sequence.to_list !sequence);
          Hashtbl.clear positions;
          Hashtbl.clear indexed;
          let indices =
            match property VirtualIndices with
            | Some (StringValue value) ->
                Option.value ~default:[] (virtual_indices_of_string value)
            | _ -> List.init (Array.length !rows) Fun.id
          in
          List.iteri (fun offset index ->
            let id = !rows.(offset) in
            Hashtbl.replace positions id index;
            Hashtbl.replace indexed index id) indices;
          (match source_generation () with
           | Some generation when !key_generation <> Some generation ->
               key_generation := Some generation;
               key := (fun index -> string_of_int generation ^ ":" ^ string_of_int index)
           (* Preserve function identity so window-only changes reuse the
              toolkit's logical measurements instead of rebuilding them. *)
           | Some _ -> ()
           | None ->
               last_window := None;
               key_generation := None;
               key := (fun index -> string_of_int !rows.(index)))
      | _ -> ()
    in
    let make_options () =
      estimated_extent := item_extent ();
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
      V.options ~count:(logical_count ())
        ~getScrollElement:(fun () -> Js.Nullable.return root)
        ~estimateSize:estimate ~getItemKey:!key ~scrollToFn:V.element_scroll
        ~observeElementRect:V.observe_element_rect
        ~observeElementOffset:V.observe_element_offset
        ~onChange:(fun _ _ -> !render_ref ())
        ~rangeExtractor:(fun range -> range_extractor range)
        ~initialRect:(V.rect ~width:400. ~height)
        ~overscan:(overscan ()) ~gap ()
    in
    update_rows ();
    let virtualizer = V.make (make_options ()) in
    let last_extent = ref !estimated_extent in
    let last_generation = ref (source_generation ()) in
    request_window := (fun () ->
      match source_generation () with
      | None -> last_window := None
      | Some generation ->
          let first, last =
            match Js.Nullable.toOption (V.item_range virtualizer) with
            | Some range ->
                (max 0 (V.range_start range - overscan ()),
                 min (logical_count ()) (V.range_end range + 1 + overscan ()))
            | None -> 0, 0
          in
          let pins = List.filter (fun id ->
            match Hashtbl.find_opt positions id with
            | Some index -> index < first || index >= last
            | None -> false) (pinned_rows ()) in
          let window = (generation, first, last, pins) in
          if !last_window <> Some window then begin
            last_window := Some window;
            emit (VirtualWindow (node, generation, first, last, pins))
          end);
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
            match source_generation () with
            | Some _ -> (match property VirtualScrollIndex with
                | Some (IntValue index) when index >= 0 -> Some index
                | _ -> None)
            | None ->
                Option.bind
                  (Array.find_opt (fun id ->
                    Store.property renderer.web_store id KeyValue
                    = Some (StringValue target_key)) !rows)
                  (Hashtbl.find_opt positions)
          in
          (* An absent target resolves at the committed-tree boundary:
             once rows are populated a missing key reports immediately. *)
          match index with
          | None ->
              if source_generation () <> None || Array.length !rows > 0 then complete_pending "missing-target"
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
              let landed =
                match Option.bind (row_at index) (Hashtbl.find_opt mounted) with
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
            let pending = Hashtbl.create (Array.length items) in
            let wrappers = Hashtbl.create (Array.length items) in
            Array.iter
              (fun item ->
                let index = V.item_index item in
                let wrapper =
                  match row_at index with
                  | None ->
                      Hashtbl.replace pending index ();
                      (match Hashtbl.find_opt placeholders index with
                       | Some wrapper -> wrapper
                       | None ->
                           let wrapper = W.Document.createElement "div" renderer.web_document in
                           W.Element.setAttribute "aria-hidden" "true" wrapper;
                           Hashtbl.replace placeholders index wrapper;
                           W.Element.appendChild (W.Element.asNode wrapper) spacer;
                           wrapper)
                  | Some id ->
                      Hashtbl.replace keep id ();
                      (match Hashtbl.find_opt mounted id with
                       | Some wrapper -> wrapper
                       | None ->
                           let wrapper = W.Document.createElement "div" renderer.web_document in
                           (* Publish membership before initializing nested virtual rows. *)
                           Hashtbl.replace mounted id wrapper;
                           W.Element.appendChild (W.Element.asNode (materialize id)) wrapper;
                           W.Element.appendChild (W.Element.asNode wrapper) spacer;
                           wrapper)
                in
                style wrapper "position" "absolute";
                style wrapper "top" "0";
                style wrapper "left" "0";
                style wrapper "width" "100%";
                W.Element.setAttribute "data-index" (string_of_int index) wrapper;
                style wrapper "transform"
                  ("translateY(" ^ Js.Float.toString (V.item_start item) ^ "px)");
                Hashtbl.replace wrappers index wrapper;
                if row_at index = None then
                  style wrapper "height" (Js.Float.toString (estimate index) ^ "px");
                if row_at index <> None && connected root
                   && W.DomRect.height (W.Element.getBoundingClientRect wrapper) > 0.
                then V.measure virtualizer (Js.Nullable.return wrapper))
              items;
            Hashtbl.fold
              (fun id wrapper acc -> if Hashtbl.mem keep id then acc else (id, wrapper) :: acc)
              mounted []
            |> List.iter (fun (id, wrapper) ->
                Hashtbl.remove mounted id;
                ignore (W.Element.removeChild (W.Element.asNode wrapper) spacer);
                unmount id);
            Hashtbl.fold
              (fun index wrapper acc -> if Hashtbl.mem pending index then acc else (index, wrapper) :: acc)
              placeholders []
            |> List.iter (fun (index, wrapper) ->
                Hashtbl.remove placeholders index;
                ignore (W.Element.removeChild (W.Element.asNode wrapper) spacer));
            (* Keep native Tab order in retained order. Move siblings around a
               focused row so inserting earlier rows does not blur it. *)
            let active = W.HtmlDocument.activeElement document in
            let anchor = ref None in
            for index = Array.length items - 1 downto 0 do
              let wrapper =
                Hashtbl.find wrappers (V.item_index items.(index))
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
              | None ->
                  if !last_range <> Some (0, -1) then begin
                    last_range := Some (0, -1);
                    emit (VisibleRange (node, 0, -1))
                  end
            end
            else last_range := None);
            schedule_window ();
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
        (* Sparse source revisions follow the visible row's retained identity.
           Eager lists preserve their existing prepend-only anchor behavior. *)
        let current_parent_scope = parent_scope () in
        let same_parent = current_parent_scope = !last_parent_scope in
        last_parent_scope := current_parent_scope;
        if not same_parent then Lui_web_virtual_anchor.cancel reading_anchor;
        let previous_sequence = !sequence in
        let previous_first =
          if Array.length !rows = 0 then None else Some !rows.(0)
        in
        let anchor = Lui_web_virtual_anchor.capture reading_anchor in
        update_rows ();
        let generation = source_generation () in
        let revised = generation <> !last_generation in
        if previous_sequence != !sequence || revised then begin
          Lui_web_virtual_anchor.cancel reading_anchor;
          if revised && same_parent then
            Lui_web_virtual_anchor.preserve reading_anchor anchor
          else
            match Option.bind previous_first (Hashtbl.find_opt positions) with
            | Some index when index > 0 && same_parent ->
                Lui_web_virtual_anchor.preserve reading_anchor anchor
            | _ -> ()
        end;
        V.set_options virtualizer (make_options ());
        let extent = !estimated_extent in
        if extent <> !last_extent || revised then begin
          last_extent := extent;
          last_generation := generation;
          V.reset_measurements virtualizer
        end;
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
    let refresh_scheduled = ref false in
    let schedule_refresh () =
      if not !refresh_scheduled then begin
        refresh_scheduled := true;
        Webapi.requestAnimationFrame (fun _ ->
          refresh_scheduled := false;
          if not !disposed then refresh ())
      end
    in
    let on_focus _ = schedule_refresh () in
    let target_row event =
      row_containing (Lui_web_util.event_target_to_element (W.Event.target event))
    in
    let on_down event =
      Option.iter (fun id -> Hashtbl.replace held_rows (pointer_id event) id) (target_row event);
      schedule_refresh ()
    in
    let on_up event =
      Hashtbl.remove held_rows (pointer_id event);
      schedule_refresh ()
    in
    let on_composition_start event = composing_row := target_row event; schedule_refresh () in
    let on_composition_end _ = composing_row := None; schedule_refresh () in
    let document_inputs =
      [ "pointerdown", on_down; "pointerup", on_up; "pointercancel", on_up;
        "lostpointercapture", on_up; "compositionstart", on_composition_start;
        "compositionend", on_composition_end ]
    in
    List.iter (fun (name, listener) ->
      Lui_web_layers.document_listen renderer.web_document name listener true) document_inputs;
    let stop_layers = Lui_web_layers.observe renderer.web_layers schedule_refresh in
    W.Element.addEventListener "focusin" on_focus root;
    W.Element.addEventListener "focusout" on_focus root;
    let dispose () =
      disposed := true;
      stop_layers ();
      List.iter (fun (name, listener) ->
        Lui_web_layers.document_unlisten renderer.web_document name listener true) document_inputs;
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
