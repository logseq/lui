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
    style spacer "position" "relative";
    style spacer "width" "100%";
    W.Element.appendChild (W.Element.asNode spacer) root;
    let rows = ref [||] in
    let sequence = ref Lui_sequence.empty in
    let positions = Hashtbl.create 16 in
    let mounted = Hashtbl.create 16 in
    let disposed = ref false in
    let updating = ref false in
    let render_ref = ref (fun () -> ()) in
    let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
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
    let render () =
      if (not !disposed) && not !updating then begin
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
            Option.iter
              (Lui_web_focus.update_tree_roving renderer)
              (Store.tree_ancestor renderer node))
      end
    in
    render_ref := render;
    let cleanup = V.did_mount virtualizer in
    let refresh () =
      if not !disposed then begin
        update_rows ();
        V.set_options virtualizer (make_options ());
        if connected root then V.will_update virtualizer;
        render ()
      end
    in
    let on_focus _ = refresh () in
    W.Element.addEventListener "focusin" on_focus root;
    W.Element.addEventListener "focusout" on_focus root;
    let dispose () =
      disposed := true;
      cleanup ();
      W.Element.removeEventListener "focusin" on_focus root;
      W.Element.removeEventListener "focusout" on_focus root;
      Hashtbl.remove renderer.web_virtual_lists node
    in
    Hashtbl.replace renderer.web_virtual_lists node
      {
        refresh_virtual = refresh;
        resize_virtual_row =
          (fun id ->
            Option.iter
              (fun index -> V.resize_item virtualizer index (estimate index))
              (Hashtbl.find_opt positions id));
        dispose_virtual = dispose;
        virtual_row_live = (fun id -> Hashtbl.mem mounted id);
        virtual_live_rows =
          (fun () ->
            Hashtbl.fold (fun id _ rows -> id :: rows) mounted []
            |> List.sort (fun a b ->
                Int.compare (Hashtbl.find positions a)
                  (Hashtbl.find positions b)));
      };
    refresh ()
  end
