open Lui_elements

type picker = {
  source : file_picker_source;
  types : string option;
  accept : string option;
  multiple : bool;
}

let request_slot = Signal.state_slot "lui-ai-picker-request"
let completion_slot = Signal.state_slot "lui-ai-picker-completion"

(* The completion token echoes the CURRENT request on Dismiss so a
   cancelled sheet releases native temp/security-scoped state; a Picked
   batch is never auto-acked — the host completes it after its async
   import through ?picker_completion. *)
let picker_node picker request completion host_completion on_picked
    on_picker_dismiss : t =
  let on_picked ev = Option.iter (fun f -> f ev) on_picked in
  let on_dismiss ev =
    Option.iter (fun f -> f ev) on_picker_dismiss;
    match ev, host_completion with
    | Lui_protocol.Dismiss _, None ->
        Signal.set completion (Signal.get_state request)
    | _ -> ()
  in
  let completion_s =
    match host_completion with
    | Some s -> s
    | None -> Signal.value completion
  in
  file_picker ~source:picker.source ?types:picker.types
    ?accept:picker.accept ~multiple:picker.multiple
    ~request_signal:(Signal.value request)
    ~completion_signal:completion_s ~on_picked ~on_dismiss []

let composer ?key ?(label = "Message") ?(placeholder = "Message")
    ?(submit_on_enter = true) ?(autofocus = false)
    ?(send_label = "Send") ?(stop_label = "Stop generating")
    ?(attach_label = "Add attachment") ~draft ~generating ?send_disabled
    ?disabled_reason ?status ?attachments ?attachments_visible_signal
    ?(controls = []) ?(trailing_controls = []) ?picker ?on_picked
    ?on_picker_dismiss ?picker_completion ?on_attach ~on_input ~on_send
    ?on_stop () : t =
  scoped (fun context ->
    let context =
      Lui_ui.child_context context
        (Lui_ui.owner_name context "lui-ai-composer")
    in
    let scheduler = context.Lui_ui.ui_scheduler in
    let request =
      Signal.state_at scheduler context.ui_state_scope request_slot (`Int 0)
    in
    let completion =
      Signal.state_at scheduler context.ui_state_scope completion_slot
        (`Int 0)
    in
    let seq = ref 0 in
    let on_attach_press ev =
      incr seq;
      Signal.set request (`Int !seq);
      Option.iter (fun f -> f ev) on_attach
    in
    let attach_button =
      match picker, on_attach with
      | None, None -> []
      | _ ->
          [ button ~icon:`plus ~variant:`ghost ~size:`icon ~width:36
              ~height:36 ~label:attach_label
              ~accessibility_identifier:"lui-ai-attach"
              ~on_press:on_attach_press [] ]
    in
    let stop_button =
      match on_stop with
      | None -> []
      | Some on_stop ->
          [ if_ ~test:generating
              (button ~icon:`pause ~variant:`secondary ~width:36 ~height:36
                 ~corner_radius:18 ~label:stop_label
                 ~accessibility_identifier:"lui-ai-stop" ~on_press:on_stop
                 []) ]
    in
    let disabled_s =
      match disabled_reason with
      | Some reason ->
          Some
            (Signal.own_signal context.ui_scope
               (Signal.map (fun r -> String.trim r <> "") reason))
      | None -> None
    in
    let reason_blocked_s =
      match disabled_reason with
      | Some reason ->
          Signal.own_signal context.ui_scope
            (Signal.map (fun r -> String.trim r <> "") reason)
      | None -> Signal.constant scheduler false
    in
    let send_blocked_s =
      Signal.own_signal context.ui_scope
        (Signal.map2 (||)
           (Signal.map2 (||) generating
              (Option.value send_disabled
                 ~default:(Signal.constant scheduler false)))
           reason_blocked_s)
    in
    let feedback =
      match disabled_reason, status with
      | None, None -> None
      | reason, status ->
          Some
            (column ~cross:`stretch ~gap:2
               ((match reason with
                 | Some reason ->
                     [ if_
                         ~test:
                           (Signal.own_signal context.ui_scope
                              (Signal.map
                                 (fun r -> String.trim r <> "") reason))
                         (text ~value_signal:reason
                            ~foreground:"warning-foreground"
                            ~style_class:"caption" []) ]
                 | None -> [])
                @ Option.to_list status))
    in
    let picker_el =
      match picker with
      | Some picker ->
          [ picker_node picker request completion picker_completion
              on_picked on_picker_dismiss ]
      | None -> []
    in
    column ?key ~cross:`stretch ~gap:0
      (picker_el
       @ [ Lui_element_combine.composer ~placeholder ~label ~submit_on_enter
             ~autofocus ~send_label
             ~send_disabled_signal:send_blocked_s
             ?disabled_signal:disabled_s ~text_signal:draft
             ?attachments ?attachments_visible_signal:attachments_visible_signal
             ?feedback
             ~actions:(attach_button @ controls @ trailing_controls
                       @ stop_button)
             ~on_input ~on_submit:on_send ~on_send () ]))
