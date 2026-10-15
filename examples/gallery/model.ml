(* Component gallery model: pure data + reducer. *)

type todo_item = {
  todo_id : int;
  todo_title : string;
  todo_done : bool;
}

type block = {
  block_id : int;
  block_text : string;
}

type t = {
  disabled : bool;
  field_value : string;
  checked : bool;
  progress : float;
  active_step : int;
  density : string;
  volume : float;
  environment : string;
  picker_query : string;
  open_picker : string;
  document : string;
  document_action : string;
  avatar_image : int;
  media_surface : int;
  tab : string;
  bottom_tab : string;
  dialog_open : bool;
  sheet_open : bool;
  toast_open : bool;
  toast_message : string;
  accordion_open : bool;
  split_fraction : float;
  (* Combine (composite) demos *)
  combine_dialog_open : bool;
  combine_sheet_open : bool;
  combine_menu_open : bool;
  composer_files : Lui_picked_files.file list;
  composer_request : int;
  composer_completion : int;
  composer_source : Lui_elements.file_picker_source;
  composer_feedback : string;
  split_panes : Lui_split.Model.t;
  (* Milestone 8 macro demos *)
  count : int;
  todo_draft : string;
  todo_items : todo_item list;
  todo_next_id : int;
  blocks : block list;
  block_next_id : int;
  block_edits : int;
  virtual_count : int;
  virtual_last : string;
  editor_text : string;
}

let gallery_split_state =
  let open Lui_split.Model in
  create ~focused:"editor"
    (Split
       {
         split_id = "gallery-root";
         split_orientation = `horizontal;
         split_ratio = 0.62;
         split_first =
           Leaf
             (pane ~pane_id:"editor" ~selected:"welcome"
                [
                  tab ~tab_id:"welcome" ~title:"Welcome" ();
                  tab ~tab_id:"notes" ~title:"Notes.md" ~dirty:true ();
                  tab ~tab_id:"repl" ~title:"REPL" ~closable:false ();
                ]);
         split_second =
           Leaf
             (pane ~pane_id:"sidebar" ~selected:"outline"
                [
                  tab ~tab_id:"outline" ~title:"Outline" ();
                  tab ~tab_id:"backlinks" ~title:"Backlinks" ();
                ]);
       })

let move_todo_up items id =
  let rec loop acc = function
    | [] -> List.rev acc
    | [ x ] -> List.rev (x :: acc)
    | prev :: (cur :: rest as tail) ->
      if cur.todo_id = id then List.rev_append (cur :: acc) (prev :: rest)
      else loop (prev :: acc) tail
  in
  loop [] items

let starter_editor_text =
  "The editor demo below keeps the document in the reducer:\n\
   every keystroke dispatches SetEditorText, and the stats line and\n\
   preview re-render from the same signal."

type action =
  | ToggleDisabled
  | SetFieldValue of string
  | SetChecked of bool
  | AdvanceProgress
  | AdvanceStep
  | SetDensity of string
  | SetVolume of float
  | OpenPicker of string
  | SetPickerQuery of string
  | SelectEnvironment of string
  | ClosePicker
  | CommitPickerQuery
  | SelectDocument of string
  | OpenDocument of string
  | PerformContextAction of string
  | ToggleAvatarImage
  | SelectTab of string
  | SelectBottomTab of string
  | OpenDialog
  | CloseDialog
  | OpenSheet
  | CloseSheet
  | ShowToasts
  | UpdateToast
  | CloseToasts
  | SetAccordionOpen of bool
  | SetSplitFraction of float
  | OpenCombineDialog
  | CloseCombineDialog
  | OpenCombineSheet
  | CloseCombineSheet
  | OpenCombineMenu
  | CloseCombineMenu
  | ComposerRequest of Lui_elements.file_picker_source
  | ComposerPicked of Lui_picked_files.t
  | ComposerCancelled
  | ComposerRemove of string
  | ComposerSend
  | SplitPanes of Lui_split.Model.action
  | CounterIncrement
  | CounterDecrement
  | CounterReset
  | SetTodoDraft of string
  | AddTodo
  | ToggleTodo of int
  | MoveTodoUp of int
  | DeleteTodo of int
  | LoadBlocks
  | ClearBlocks
  | EditBlock
  | InsertBlock
  | SetVirtualCount of int
  | PressVirtualRow of int
  | SetEditorText of string

let initial =
  {
    disabled = false;
    field_value = "";
    checked = false;
    progress = 0.3;
    active_step = 1;
    density = "comfortable";
    volume = 0.35;
    environment = "Production";
    picker_query = "";
    open_picker = "none";
    document = "Quarterly report.md";
    document_action = "Selected Quarterly report.md";
    avatar_image = 0;
    media_surface = 1;
    tab = "overview";
    bottom_tab = "home";
    dialog_open = false;
    sheet_open = false;
    toast_open = false;
    toast_message = "Saved";
    accordion_open = false;
    split_fraction = 0.35;
    combine_dialog_open = false;
    combine_sheet_open = false;
    combine_menu_open = false;
    composer_files = [];
    composer_request = 0;
    composer_completion = 0;
    composer_source = `files;
    composer_feedback = "";
    split_panes = gallery_split_state;
    count = 0;
    todo_draft = "";
    todo_items = [];
    todo_next_id = 1;
    blocks = [];
    block_next_id = 0;
    block_edits = 0;
    virtual_count = 0;
    virtual_last = "none";
    editor_text = starter_editor_text;
  }

let update model action =
  match action with
  | ToggleDisabled -> { model with disabled = not model.disabled }
  | SetFieldValue value -> { model with field_value = value }
  | SetChecked checked -> { model with checked }
  | AdvanceProgress ->
    {
      model with
      progress =
        (if model.progress >= 1.0 then 0.0 else model.progress +. 0.1);
    }
  | AdvanceStep ->
    {
      model with
      active_step = (if model.active_step >= 3 then 0 else model.active_step + 1);
    }
  | SetDensity density -> { model with density }
  | SetVolume volume -> { model with volume }
  | OpenPicker picker -> { model with open_picker = picker }
  | SetPickerQuery query ->
    { model with picker_query = query; open_picker = "combobox" }
  | SelectEnvironment environment ->
    {
      model with
      environment;
      picker_query = environment;
      open_picker = "none";
    }
  | ClosePicker -> { model with open_picker = "none" }
  | CommitPickerQuery ->
    if model.picker_query = "" then { model with open_picker = "none" }
    else
      { model with environment = model.picker_query; open_picker = "none" }
  | SelectDocument document ->
    { model with document; document_action = "Selected " ^ document }
  | OpenDocument document ->
    { model with document_action = "Opened " ^ document }
  | PerformContextAction action ->
    { model with document_action = "Context action: " ^ action }
  | ToggleAvatarImage ->
    { model with avatar_image = if model.avatar_image = 0 then 1 else 0 }
  | SelectTab tab -> { model with tab }
  | SelectBottomTab tab -> { model with bottom_tab = tab }
  | OpenDialog -> { model with dialog_open = true }
  | CloseDialog -> { model with dialog_open = false }
  | OpenSheet -> { model with sheet_open = true }
  | CloseSheet -> { model with sheet_open = false }
  | ShowToasts -> { model with toast_open = true; toast_message = "Saved" }
  | UpdateToast -> { model with toast_message = "Updated" }
  | CloseToasts -> { model with toast_open = false }
  | SetAccordionOpen open_ -> { model with accordion_open = open_ }
  | SetSplitFraction fraction -> { model with split_fraction = fraction }
  | OpenCombineDialog -> { model with combine_dialog_open = true }
  | CloseCombineDialog -> { model with combine_dialog_open = false }
  | OpenCombineSheet -> { model with combine_sheet_open = true }
  | CloseCombineSheet -> { model with combine_sheet_open = false }
  | OpenCombineMenu -> { model with combine_menu_open = true }
  | CloseCombineMenu -> { model with combine_menu_open = false }
  | ComposerRequest source ->
    if model.composer_request <> model.composer_completion then model
    else { model with composer_request = model.composer_request + 1;
      composer_source = source; composer_feedback = "" }
  | ComposerPicked batch ->
    if batch.request <> `Int model.composer_request
       || model.composer_request = model.composer_completion then model
    else
      let seen = Hashtbl.create 8 in
      List.iter (fun (file : Lui_picked_files.file) -> Hashtbl.replace seen file.path ()) model.composer_files;
      let count = ref (List.length model.composer_files) in
      let skipped = ref batch.failures in
      let added = List.filter (fun (file : Lui_picked_files.file) ->
        if Hashtbl.mem seen file.path then false
        else if !count >= 8 then (incr skipped; false)
        else (Hashtbl.add seen file.path (); incr count; true)) batch.files in
      { model with composer_files = model.composer_files @ added;
        composer_completion = model.composer_request;
        composer_feedback = if !skipped = 0 then "" else
          Printf.sprintf "%d attachment(s) could not be added (limit 8, 50 MiB each)." !skipped }
  | ComposerCancelled ->
    { model with composer_completion = model.composer_request }
  | ComposerRemove path ->
    { model with composer_files = List.filter
      (fun (file : Lui_picked_files.file) -> file.path <> path) model.composer_files }
  | ComposerSend ->
    { model with composer_files = []; field_value = ""; composer_feedback = "" }
  | SplitPanes action ->
    { model with split_panes = Lui_split.Model.update model.split_panes action }
  | CounterIncrement -> { model with count = model.count + 1 }
  | CounterDecrement -> { model with count = model.count - 1 }
  | CounterReset -> { model with count = 0 }
  | SetTodoDraft todo_draft -> { model with todo_draft }
  | AddTodo ->
    let title = String.trim model.todo_draft in
    if title = "" then model
    else
      {
        model with
        todo_items =
          model.todo_items
          @ [
              {
                todo_id = model.todo_next_id;
                todo_title = title;
                todo_done = false;
              }
            ];
        todo_draft = "";
        todo_next_id = model.todo_next_id + 1;
      }
  | ToggleTodo id ->
    {
      model with
      todo_items =
        List.map
          (fun (item : todo_item) ->
             if item.todo_id = id then { item with todo_done = not item.todo_done }
             else item)
          model.todo_items;
    }
  | MoveTodoUp id -> { model with todo_items = move_todo_up model.todo_items id }
  | DeleteTodo id ->
    {
      model with
      todo_items =
        List.filter (fun (item : todo_item) -> item.todo_id <> id) model.todo_items;
    }
  | LoadBlocks ->
    if model.blocks <> [] then model
    else
      {
        model with
        blocks =
          List.init 10_000 (fun i ->
              {
                block_id = i;
                block_text = Printf.sprintf "block %d content" i;
              });
        block_next_id = 10_000;
      }
  | ClearBlocks -> if model.blocks = [] then model else { model with blocks = [] }
  | EditBlock ->
    (match model.blocks with
     | [] -> model
     | _ ->
       let target = List.length model.blocks / 2 in
       {
         model with
         block_edits = model.block_edits + 1;
         blocks =
           List.mapi
             (* Unedited blocks keep their record identity so the keyed
                source republish only touches the edited row. *)
             (fun i (b : block) ->
                if i = target then
                  {
                    b with
                    block_text =
                      Printf.sprintf "block %d content (edit %d)" b.block_id
                        model.block_edits;
                  }
                else b)
             model.blocks;
       })
  | InsertBlock ->
    let id = model.block_next_id in
    let rec go i acc = function
      | rest when i <= 0 ->
        List.rev_append acc ({ block_id = id; block_text = Printf.sprintf "inserted block %d" id } :: rest)
      | [] -> List.rev ({ block_id = id; block_text = Printf.sprintf "inserted block %d" id } :: acc)
      | b :: rest -> go (i - 1) (b :: acc) rest
    in
    {
      model with
      blocks = go (List.length model.blocks / 2) [] model.blocks;
      block_next_id = id + 1;
    }
  | SetVirtualCount virtual_count -> { model with virtual_count }
  | PressVirtualRow row ->
    { model with virtual_last = Printf.sprintf "row %d" row }
  | SetEditorText editor_text -> { model with editor_text }

let progress_label model =
  Printf.sprintf "Progress fraction: %.1f" model.progress

let density_comfortable model = model.density = "comfortable"

let density_compact model = model.density = "compact"

let volume_label model = Printf.sprintf "Volume: %.2f" model.volume

let select_open model = model.open_picker = "select"

let combobox_open model = model.open_picker = "combobox"

let production_selected model = model.environment = "Production"

let staging_selected model = model.environment = "Staging"

let environment_visible model environment =
  let query = String.lowercase_ascii model.picker_query in
  query = ""
  || let haystack = String.lowercase_ascii environment in
     let qlen = String.length query in
     let hlen = String.length haystack in
     let rec contains i =
       i <= hlen - qlen
       && (String.sub haystack i qlen = query || contains (i + 1))
     in
     qlen <= hlen && contains 0

let production_visible model = environment_visible model "Production"

let staging_visible model = environment_visible model "Staging"

let report_selected model = model.document = "Quarterly report.md"

let checklist_selected model = model.document = "Launch checklist.md"

let overview_tab_selected model = model.tab = "overview"

let activity_tab_selected model = model.tab = "activity"

let home_bottom_tab_selected model = model.bottom_tab = "home"

let search_bottom_tab_selected model = model.bottom_tab = "search"

let settings_bottom_tab_selected model = model.bottom_tab = "settings"

let tab_content model =
  if activity_tab_selected model then "Recent retained updates"
  else "Signal updates remain local"

let toast_description model =
  if model.toast_message = "Updated" then
    "Draft remains the same retained toast"
  else "Draft saved locally"

let tab_index model = if activity_tab_selected model then 1 else 0

let bottom_tab_index model =
  if search_bottom_tab_selected model then 1
  else if settings_bottom_tab_selected model then 2
  else 0

let disabled model = model.disabled
let field_value model = model.field_value
let checked model = model.checked
let progress model = model.progress
let active_step model = model.active_step
let density model = model.density
let volume model = model.volume
let environment model = model.environment
let picker_query model = model.picker_query
let open_picker model = model.open_picker
let document model = model.document
let document_action model = model.document_action
let avatar_image model = model.avatar_image
let media_surface model = model.media_surface
let tab model = model.tab
let bottom_tab model = model.bottom_tab
let dialog_open model = model.dialog_open
let sheet_open model = model.sheet_open
let toast_open model = model.toast_open
let toast_message model = model.toast_message
let accordion_open model = model.accordion_open
let split_fraction model = model.split_fraction
let combine_dialog_open model = model.combine_dialog_open
let combine_sheet_open model = model.combine_sheet_open
let combine_menu_open model = model.combine_menu_open

let count model = model.count
let todo_draft model = model.todo_draft
let todo_items model = model.todo_items
let blocks model = model.blocks
let virtual_count model = model.virtual_count
let virtual_last model = model.virtual_last
let editor_text model = model.editor_text

let todo_summary model =
  let remaining =
    List.length
      (List.filter (fun (item : todo_item) -> not item.todo_done) model.todo_items)
  in
  Printf.sprintf "%d remaining / %d total" remaining
    (List.length model.todo_items)

let blocks_summary model =
  if model.blocks = [] then "no blocks loaded"
  else Printf.sprintf "%d blocks mounted" (List.length model.blocks)

let virtual_summary model =
  if model.virtual_count = 0 then "virtual list empty — load rows to mount"
  else
    Printf.sprintf "%d logical rows · last pressed: %s" model.virtual_count
      model.virtual_last

let editor_stats model =
  let lines = ref 1 and words = ref 0 and in_word = ref false in
  String.iter
    (fun c ->
       if c = '\n' then incr lines;
       match c with
       | '0' .. '9' | 'a' .. 'z' | 'A' .. 'Z' | '\128' .. '\255' ->
         if not !in_word then begin
           incr words;
           in_word := true
         end
       | _ -> in_word := false)
    model.editor_text;
  Printf.sprintf "%d chars · %d words · %d lines" (String.length model.editor_text)
    !words !lines
