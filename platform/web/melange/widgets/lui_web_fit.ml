open Lui_web_types

module W = Webapi.Dom

external number : string -> float = "parseFloat" [@@mel]

let pixels style name =
  let value = number (W.CssStyleDeclaration.getPropertyValue name style) in
  if Float.is_finite value then value else 0.

let children root =
  let collection = W.Element.children root in
  let rec collect index result =
    match W.HtmlCollection.item index collection with
    | Some child -> collect (index + 1) (child :: result)
    | None -> List.rev result
  in
  collect 0 []

let attach renderer node root =
  let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
  let window = W.HtmlDocument.defaultView document in
  let pending = ref None in
  let disposed = ref false in
  let managed = ref [] in
  let restore child was_inert =
    W.Element.removeAttribute "data-lui-fit-hidden" child;
    W.Element.removeAttribute "data-lui-fit-probe" child;
    if not was_inert then W.Element.removeAttribute "inert" child
  in
  let resize_observer = ref None in
  let update () =
    match window with
    | None -> ()
    | Some window ->
        let candidates = children root in
        List.iter
          (fun (child, was_inert) ->
            if not (List.exists (( == ) child) candidates) then
              begin
                restore child was_inert;
                match !resize_observer with
                | Some observer -> Webapi.ResizeObserver.unobserve observer child
                | None -> ()
              end)
          !managed;
        managed :=
          List.map
            (fun child ->
              let was_inert =
                match List.find_opt (fun (old, _) -> old == child) !managed with
                | Some (_, was_inert) -> was_inert
                | None ->
                    (match !resize_observer with
                     | Some observer -> Webapi.ResizeObserver.observe observer child
                     | None -> ());
                    W.Element.hasAttribute "inert" child
              in
              (child, was_inert))
            candidates;
        let vertical =
          W.Element.getAttribute "data-orientation" root = Some "vertical"
        in
        let style = W.Window.getComputedStyle root window in
        let available =
          if vertical then
            float_of_int (W.Element.clientHeight root)
            -. pixels style "padding-top" -. pixels style "padding-bottom"
          else
            float_of_int (W.Element.clientWidth root)
            -. pixels style "padding-left" -. pixels style "padding-right"
        in
        let focused = W.HtmlDocument.activeElement document in
        let fits child =
          W.Element.setAttribute "data-lui-fit-probe" "" child;
          let bounds = W.Element.getBoundingClientRect child in
          let child_style = W.Window.getComputedStyle child window in
          let size =
            if vertical then
              max (W.DomRect.height bounds)
                (float_of_int (W.Element.scrollHeight child))
              +. pixels child_style "margin-top"
              +. pixels child_style "margin-bottom"
            else
              max (W.DomRect.width bounds)
                (float_of_int (W.Element.scrollWidth child))
              +. pixels child_style "margin-left"
              +. pixels child_style "margin-right"
          in
          W.Element.removeAttribute "data-lui-fit-probe" child;
          size <= available +. 0.5
        in
        let rec choose = function
          | [] -> None
          | [last] -> Some last
          | child :: rest -> if fits child then Some child else choose rest
        in
        let selected = choose candidates in
        List.iter
          (fun (child, was_inert) ->
            if (match selected with Some selected -> selected == child | None -> false)
            then restore child was_inert
            else begin
              (match focused with
               | Some active
                 when W.Element.contains (W.Element.asNode active) child ->
                   if not (W.Element.hasAttribute "tabindex" root) then
                     W.Element.setAttribute "tabindex" "-1" root;
                   Lui_web_util.focus_element_without_scroll root
               | _ -> ());
              W.Element.setAttribute "data-lui-fit-hidden" "" child;
              W.Element.setAttribute "inert" "" child
            end)
          !managed
  in
  let schedule () =
    if not !disposed && !pending = None then
      pending :=
        Some
          (Webapi.requestCancellableAnimationFrame (fun _ ->
               pending := None;
               if not !disposed then update ()))
  in
  let observer = Webapi.ResizeObserver.make (fun _ -> schedule ()) in
  resize_observer := Some observer;
  Webapi.ResizeObserver.observe observer root;
  let mutations = W.MutationObserver.make (fun _ _ -> schedule ()) in
  W.MutationObserver.observe (W.Element.asNode root)
    [%mel.obj
      { childList = true; subtree = true; characterData = true;
        attributes = true;
        attributeFilter = [| "style"; "class"; "data-orientation" |] }]
    mutations;
  let on_resize _ = schedule () in
  (match window with
   | Some window -> W.Window.addEventListener "resize" on_resize window
   | None -> ());
  let previous_cleanup = Hashtbl.find_opt renderer.web_cleanups node in
  Hashtbl.replace renderer.web_cleanups node (fun () ->
      disposed := true;
      (match !pending with
       | Some frame -> Webapi.cancelAnimationFrame frame
       | None -> ());
      Webapi.ResizeObserver.disconnect observer;
      W.MutationObserver.disconnect mutations;
      (match window with
       | Some window -> W.Window.removeEventListener "resize" on_resize window
       | None -> ());
      List.iter (fun (child, was_inert) -> restore child was_inert) !managed;
      (match previous_cleanup with Some cleanup -> cleanup () | None -> ()));
  schedule ()
