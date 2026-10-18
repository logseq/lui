open Lui_elements

module Model = Model
module Attachment = Attachment
module Transcript = Transcript
module Composer = Composer

let view ?key ?viewport ?(content_width = 768) ?header ?placeholder
    ?picker ?render_item ?item_actions ?on_retry ?on_load_full
    ?on_reach_top ?on_remove_attachment ?on_picked ?on_attach
    ?composer_controls ?composer_trailing_controls ?status ~messages
    ~draft ~attachments ~generating ~on_input ~on_send ?on_stop () : t =
  let strip =
    reactive
      (fun (atts : Model.attachment list) ->
         row ~gap:8
           (List.map
              (fun (a : Model.attachment) ->
                 Attachment.chip a
                   ~on_remove:
                     (Option.map
                        (fun f -> fun ev -> ignore ev; f a.Model.attachment_id)
                        on_remove_attachment)
                   ())
              atts))
      attachments
  in
  column ?key ~grow:1.0 ~cross:`stretch
    (Option.to_list header
     @ [ Transcript.transcript ~messages ?viewport ~content_width
           ?render_item ?item_actions ?on_retry ?on_load_full
           ?on_reach_top ()
       ; Composer.composer ~draft ~generating ?placeholder
           ~attachments:strip
           ~attachments_visible:
             (reactive (fun l -> l <> []) attachments)
           ?controls:composer_controls
           ?trailing_controls:composer_trailing_controls ?status ?picker
           ?on_picked ?on_attach ~on_input ~on_send ?on_stop () ])
