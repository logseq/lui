open Lui_elements

let view _context model_s send =
  let model = Signal.get model_s in
  let outcome_el =
    if model.Model.debug then
      [ text ~min_height:16
          ~value_signal:(model_s >|= fun m -> m.Model.outcome)
          ~accessibility_identifier:"scroll-outcome" [] ]
    else []
  in
  let on_scroll_completed =
    if model.Model.debug then
      Some
        (fun (ev : Lui_protocol.event) ->
           match ev with
           | Lui_protocol.ScrollCompleted (_, _, outcome) ->
               ignore (send (Model.ScrollOutcome outcome))
           | _ -> ())
    else None
  in
  if model.Model.plain then
    column ~grow:1.
      [ virtual_list ~height:400 ~grow:1.
          [ keyed
              ~source:
                (model_s >|= fun (m : Model.t) ->
                     List.init m.Model.vrows Fun.id)
              ~key:Fun.id ~cmp:Int.compare
              ~mount:(fun i_s ->
                text ~height:24
                  ~value_signal:
                    (i_s >|= fun i -> Printf.sprintf "row %d" i)
                  [])
          ]
      ]
  else
  Lui_ai.view
    ?header:
      (match outcome_el with [ el ] -> Some el | _ -> None)
    ~viewport:
      (if model.Model.list_mode then Lui_ai.Transcript.Anchored_list
       else Lui_ai.Transcript.Anchored)
    ?on_scroll_completed ~messages:(model_s >|= Model.items)
    ~draft:(model_s >|= Model.draft)
    ~generating:(model_s >|= Model.generating)
    ~attachments:(model_s >|= fun _ -> [])
    ~placeholder:"Message LUI chat"
    ~on_input:(on_input send (fun s -> Model.Input s))
    ~on_send:(press send Model.Send)
    ~on_stop:(press send Model.Stop) ()
