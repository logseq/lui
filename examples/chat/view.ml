open Lui_elements

let view _context model_s send =
  Lui_ai.view ~messages:(model_s >|= Model.items)
    ~draft:(model_s >|= Model.draft)
    ~generating:(model_s >|= Model.generating)
    ~attachments:(model_s >|= fun _ -> [])
    ~placeholder:"Message LUI chat"
    ~on_input:(on_input send (fun s -> Model.Input s))
    ~on_send:(press send Model.Send)
    ~on_stop:(press send Model.Stop) ()
