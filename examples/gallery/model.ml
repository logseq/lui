(* Component gallery model: pure data + reducer. *)

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
}

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
