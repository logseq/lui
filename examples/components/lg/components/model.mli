(* ns components.model *)

type gallery_model = { gallery_disabled : bool ; gallery_field_value : string ; gallery_checked : bool ; gallery_progress : float ; gallery_active_step : int ; gallery_density : string ; gallery_volume : float ; gallery_environment : string ; gallery_picker_query : string ; gallery_open_picker : string ; gallery_document : string ; gallery_document_action : string ; gallery_avatar_image : int ; gallery_media_surface : int ; gallery_tab : string ; gallery_bottom_tab : string ; gallery_dialog_open : bool ; gallery_sheet_open : bool ; gallery_toast_open : bool ; gallery_toast_message : string ; gallery_accordion_open : bool ; gallery_split_fraction : float }

type gallery_action =
  | ToggleDisabled
  | SetFieldValue of string
  | SetChecked of bool
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
  | AdvanceProgress
  | AdvanceStep

val initial : unit -> gallery_model

val update : gallery_model -> gallery_action -> gallery_model

val progress_label : gallery_model -> string

val density_comfortable_ : gallery_model -> bool

val density_compact_ : gallery_model -> bool

val volume_label : gallery_model -> string

val select_open_ : gallery_model -> bool

val combobox_open_ : gallery_model -> bool

val production_selected_ : gallery_model -> bool

val staging_selected_ : gallery_model -> bool

val report_selected_ : gallery_model -> bool

val checklist_selected_ : gallery_model -> bool

val overview_tab_selected_ : gallery_model -> bool

val activity_tab_selected_ : gallery_model -> bool

val home_bottom_tab_selected_ : gallery_model -> bool

val search_bottom_tab_selected_ : gallery_model -> bool

val settings_bottom_tab_selected_ : gallery_model -> bool

val tab_content : gallery_model -> string

val toast_description : gallery_model -> string

