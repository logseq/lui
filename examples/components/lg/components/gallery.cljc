(ns components.gallery
  (:require [lui.macros :refer [defui]]
            [lui.badge]
            [lui.separator]
            [lui.skeleton]))

(defui button-gallery [disabled-source toggle-disabled]
  [:column {:gap 24 :padding 32}
   [:text "Button"]
   [:button
    {:variant "outline" :on-press toggle-disabled}
    "Toggle disabled"]
   [:if {:test disabled-source}
    [:paragraph "Controls are disabled."]]
   [:grid {:columns 2 :gap 12}
    [:button {:disabled disabled-source :on-press (fn [_event] true)} "Default"]
    [:button
     {:variant "primary"
      :icon "download"
      :disabled disabled-source
      :on-press (fn [_event] true)
      :on-hold toggle-disabled}
     "Primary"]
    [:button
     {:variant "secondary"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Secondary"]
    [:button
     {:variant "outline"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Outline"]
    [:button
     {:variant "ghost"
      :selected true
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Selected"]
    [:button
     {:variant "destructive"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Destructive"]]
   [:row {:gap 12}
    [:button
     {:size "sm" :disabled disabled-source :on-press (fn [_event] true)}
     "Small"]
    [:button
     {:disabled disabled-source :on-press (fn [_event] true)}
     "Default"]
    [:button
     {:size "lg"
      :icon "chevron-right"
      :icon-placement "trailing"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Large"]
    [:button
     {:size "icon"
      :icon "plus"
      :label "New note"
      :disabled disabled-source
      :on-press (fn [_event] true)}]]
   [:paragraph
    "Press Primary for a normal action; hold it for 350 ms to toggle disabled state."]])

(defui surface-gallery [copy-source]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Stack, Panel, and Card"]
   [:grid {:columns 2 :gap 16}
    [:panel {:padding 16}
     [:column {:gap 8}
      [:text "Panel"]
      [:paragraph "A raised overlay surface with explicit content padding."]]]
    [:card
     [:column {:gap 12}
      [:text "Card"]
      [:paragraph {:value copy-source}]
      [:button {:on-press (fn [_event] true)} "Save changes"]]]]
   [:stack {:width 320 :height 96}
    [:panel {:padding 16}
     [:text "Stack base layer"]]
    [:text {:padding 16} "Overlay layer"]]])

(defui dialog-gallery [open-source open-dialog close-dialog]
  [:column {:gap 16 :padding 32}
   [:heading {:level 2} "Dialog"]
   [:button {:variant "outline" :on-press open-dialog} "Open dialog"]
   [:paragraph
    "The same model-owned conditional drives the native modal on every host."]
   [:if {:test open-source}
    [:dialog
     {:text "Rename note"
      :width 380
      :height 240
     :padding 24
      :on-dismiss close-dialog}
     [:column {:gap 16}
      [:box {:height 24}]
      [:input {:placeholder "Note name" :autofocus true}]
      [:row {:gap 8 :main "end"}
       [:button {:variant "ghost" :on-press close-dialog} "Cancel"]
       [:button {:variant "primary" :on-press close-dialog} "Save"]]]]]])

(defui edge-surface-gallery
  [drawer-open-source open-drawer close-drawer
   sheet-open-source open-sheet close-sheet]
  [:column {:gap 16 :padding 32}
   [:heading {:level 2} "Drawer and Sheet"]
   [:row {:gap 12}
    [:button {:variant "outline" :on-press open-drawer} "Open drawer"]
    [:button {:variant "outline" :on-press open-sheet} "Open sheet"]]
   [:paragraph
    "Drawer is the bottom-edge surface; Sheet is the adaptive trailing-edge surface."]
   [:if {:test drawer-open-source}
    [:drawer
     {:text "Filters"
      :height 260
      :padding 24
      :on-dismiss close-drawer}
     [:column {:gap 12}
      [:box {:height 24}]
      [:checkbox "Only unread"]
      [:switch "Compact rows"]
      [:button {:variant "primary" :on-press close-drawer} "Apply filters"]]]]
   [:if {:test sheet-open-source}
    [:sheet
     {:text "Share"
      :width 320
      :padding 24
      :on-dismiss close-sheet}
     [:column {:gap 12}
      [:box {:height 24}]
      [:paragraph "Anyone with the link can view this showcase."]
      [:input {:placeholder "Share link"}]
      [:button {:variant "primary" :on-press close-sheet} "Done"]]]]])

(defui collection-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "List and Scroll"]
   [:list {:gap 8 :cross "stretch" :max-width 480}
    [:card {:padding 16} [:text "List item one"]]
    [:card {:padding 16} [:text "List item two"]]
    [:card {:padding 16} [:text "List item three"]]]
   [:scroll {:width 320 :height 160}
    [:list {:gap 8 :cross "stretch"}
     [:card {:padding 16} [:text "Scrollable item one"]]
     [:card {:padding 16} [:text "Scrollable item two"]]
     [:card {:padding 16} [:text "Scrollable item three"]]
     [:card {:padding 16} [:text "Scrollable item four"]]]]])

(defui list-item-gallery
  [report-selected-source checklist-selected-source disabled-source
   action-source select-report select-checklist open-report open-checklist]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "ListItem"]
   [:list {:gap 2 :cross "stretch" :max-width 480}
    [:list-item
     {:icon "file-text"
      :selected report-selected-source
      :disabled disabled-source
      :on-press select-report
      :on-double-press open-report
      :on-submit open-report}
     "Quarterly report.md"]
    [:list-item
     {:selected checklist-selected-source
      :disabled disabled-source
      :on-press select-checklist
      :on-double-press open-checklist
      :on-submit open-checklist}
     [:row {:gap 8 :cross "center"}
      [:icon {:name "check-circle" :size "sm"}]
      [:text "Launch checklist.md"]
      [:spacer]
      [:badge {:variant "success"} "Ready"]]]
    [:list-item {:icon "music" :disabled true} "demo-track.wav"]]
   [:paragraph {:value action-source}]
   [:paragraph
    "Click selects immediately; double click and Enter run the primary action without replacing a row."]])

(defui badge-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Badge"]
   [:grid {:columns 2 :gap 8}
    [:badge "Default"]
    [:badge {:variant "secondary"} "Secondary"]
    [:badge {:variant "outline"} "Outline"]
    [:badge {:variant "success"} "Success"]
    [:badge {:variant "warning"} "Warning"]
    [:badge {:variant "error"} "Error"]
    [:badge {:round true} "Round"]]])

(defui avatar-gallery [image-source toggle-image]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Avatar"]
   [:row {:gap 12 :cross "center"}
    [:avatar {:image image-source :label "Registered profile image"} "ZN"]
    [:avatar "CT"]]
   [:button {:variant "outline" :on-press toggle-image}
    "Toggle registered image"]
   [:paragraph
    "The host owns image resources; changing the ImageId Signal retains the Avatar node."]])

(defui progress-gallery [value-source value-label-source advance]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Progress"]
   [:paragraph "Uploading files"]
   [:progress {:value value-source :width 280}]
   [:text {:value value-label-source}]
   [:button {:variant "outline" :on-press advance} "Advance progress"]])

(defui separator-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Separator"]
   [:paragraph "Horizontal"]
   [:separator]
   [:row {:gap 12 :class "lui-separator-example-row"}
    [:text "Left"]
    [:separator {:orientation "vertical"}]
    [:text "Right"]]])

(defui skeleton-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Skeleton"]
   [:column {:gap 12 :max-width 320}
    [:skeleton {:width 320 :height 16 :corner-radius 6}]
    [:skeleton {:width 240 :height 16 :corner-radius 6}]
    [:skeleton {:width 280 :height 16 :corner-radius 6}]]])

(defui spinner-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Spinner"]
   [:row {:gap 16 :cross "center"}
    [:spinner {:size "sm"}]
    [:spinner]
    [:spinner {:size "lg"}]
    [:spinner {:size "icon"}]]])

(defui icon-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Icon"]
   [:paragraph "Common actions, navigation, status, files, and media"]
   [:row {:gap 16 :cross "center"}
    [:icon {:name "search" :size "sm"}]
    [:icon {:name "check-circle"}]
    [:icon {:name "git-pull-request"}]
    [:icon {:name "folder-open"}]
    [:icon {:name "play"}]
    [:icon {:name "settings"}]
    [:icon {:name "trash" :size "lg" :foreground "destructive"}]]])

(defui text-entry-gallery [value-source disabled-source update-value]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "TextField"]
   [:text-field
    {:text value-source
     :label "Project name"
     :placeholder "Project name"
     :disabled disabled-source
     :on-input update-value}]
   [:heading {:level 2} "Input"]
   [:input
    {:text value-source
     :label "Email"
     :placeholder "you@example.com"
     :disabled disabled-source
     :on-input update-value}]
   [:heading {:level 2} "SearchField"]
   [:search-field
    {:text value-source
     :label "Search components"
     :placeholder "Search components"
     :disabled disabled-source
     :on-input update-value}]
   [:heading {:level 2} "Textarea"]
   [:textarea
    {:text value-source
     :label "Notes"
     :placeholder "Add notes"
     :disabled disabled-source
     :on-input update-value}]
   [:paragraph
    "All four controls share one Signal and patch their retained native nodes in place."]])

(defui environment-menu
  [production-selected-source staging-selected-source disabled-source
   select-production select-staging dismiss]
  [:dropdown-menu
   {:anchor "below"
    :anchor-alignment "stretch"
    :anchor-offset 6.0
    :min-width 200
    :on-dismiss dismiss}
   [:menu-item
    {:icon "check"
     :selected production-selected-source
     :disabled disabled-source
     :on-press select-production}
    "Production"]
   [:menu-item
    {:selected staging-selected-source
     :disabled disabled-source
     :on-press select-staging}
    "Staging"]
   [:menu-item {:disabled true} "Development"]])

(defui picker-gallery
  [selected-source query-source select-open-source combobox-open-source
   production-selected-source staging-selected-source disabled-source
   open-select open-combobox update-query submit-query dismiss
   select-production select-staging]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Select, Combobox, and DropdownMenu"]
   [:stack
    [:select
     {:text selected-source
      :disabled disabled-source
      :on-press open-select
      :on-dismiss dismiss}]
    [:if {:test select-open-source}
     [environment-menu
      production-selected-source staging-selected-source disabled-source
      select-production select-staging dismiss]]]
   [:stack
    [:combobox
     {:text query-source
      :placeholder "Search environments"
      :disabled disabled-source
      :on-input update-query
      :on-submit submit-query
      :on-press open-combobox
      :on-dismiss dismiss}]
    [:if {:test combobox-open-source}
     [environment-menu
      production-selected-source staging-selected-source disabled-source
      select-production select-staging dismiss]]]
   [:paragraph
    "Selection, query, and menu visibility are shared Signals; opening and closing mounts only the retained menu segment."]])

(defui toggle-gallery [checked-source disabled-source update-toggle]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Checkbox and Switch"]
   [:checkbox
    {:checked checked-source
     :disabled disabled-source
     :on-toggle update-toggle}
    "Enable notifications"]
   [:switch
    {:checked checked-source
     :disabled disabled-source
     :on-toggle update-toggle}
    "Background sync"]
   [:paragraph
    "Both native controls share one Signal and patch in place."]])

(defui value-control-gallery
  [checked-source comfortable-source compact-source volume-source
   volume-label-source disabled-source update-toggle select-comfortable
   select-compact update-volume]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Toggle, RadioGroup, and Slider"]
   [:toggle
    {:checked checked-source
     :disabled disabled-source
     :on-toggle update-toggle}
    "Bold formatting"]
   [:radio-group {:label "Content density"}
    [:radio
     {:checked comfortable-source
      :disabled disabled-source
      :on-change select-comfortable}
     "Comfortable"]
    [:radio
     {:checked compact-source
      :disabled disabled-source
      :on-change select-compact}
     "Compact"]]
   [:paragraph {:value volume-label-source}]
   [:slider
    {:value volume-source
     :disabled disabled-source
     :label "Volume"
     :on-change update-volume}]
   [:paragraph
    "All controls are model-owned Signals and retain their native node identity."]])

(defui toggle-button-gallery
  [selected-source disabled-source update-selected toggle-disabled]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "ToggleButton"]
   [:row {:gap 12}
    [:toggle-button
     {:variant "outline"
      :size "sm"
      :icon "edit"
      :selected selected-source
      :disabled disabled-source
      :on-toggle update-selected
      :on-hold toggle-disabled}
     "Controlled"]
    [:toggle-button
     {:variant "ghost"
      :disabled disabled-source
      :on-toggle (fn [_event] true)}
     "Backend-owned"]
    [:toggle-button
     {:size "icon"
      :icon "check"
      :label "Toggle approval"
      :disabled disabled-source
      :on-toggle (fn [_event] true)}]]
   [:paragraph
    "Controlled selection follows one Signal; backend-owned selection survives unrelated patches."]])

(defui action-group-gallery
  [selected-source disabled-source update-selected toggle-disabled]
  [:column {:gap 16 :padding 32}
   [:heading {:level 2} "ButtonGroup"]
   [:button-group {:accessibility-label "Document actions"}
    [:button
     {:icon "save" :disabled disabled-source :on-press toggle-disabled}
     "Save"]
    [:toggle-button
     {:icon "check"
      :selected selected-source
      :disabled disabled-source
      :on-toggle update-selected}
     "Pin"]]
   [:heading {:level 2} "ToggleGroup"]
   [:toggle-group {:accessibility-label "View options"}
    [:toggle-button
     {:selected selected-source
      :disabled disabled-source
      :on-toggle update-selected}
     "Controlled"]
    [:toggle-button
     {:disabled disabled-source :on-toggle (fn [_event] true)}
     "Multi-select"]
    [:button
     {:variant "outline"
      :selected selected-source
      :disabled disabled-source
      :on-press toggle-disabled}
     "Action chip"]]
   [:paragraph
    "Groups own native layout and focus navigation; each child owns its event and selection state."]])

(defui navigation-gallery
  [overview-selected-source activity-selected-source disabled-source
   select-overview select-activity]
  [:column {:gap 16 :padding 32}
   [:heading {:level 2} "Breadcrumb"]
   [:breadcrumb {:accessibility-label "Component path"}
    [:text
     {:foreground "muted-foreground" :on-press select-overview}
     "Gallery"]
    [:icon
     {:name "chevron-right" :size "sm"
      :foreground "muted-foreground"}]
    [:text "Navigation"]]
   [:heading {:level 2} "Pagination"]
   [:pagination {:accessibility-label "Gallery pages"}
    [:button
     {:variant "ghost" :icon "chevron-left"
      :disabled disabled-source :on-press select-overview}
     "Previous"]
    [:button
     {:variant "outline" :selected overview-selected-source
      :disabled disabled-source :on-press select-overview}
     "1"]
    [:icon {:name "ellipsis" :foreground "muted-foreground"}]
    [:button
     {:variant "outline" :selected activity-selected-source
      :disabled disabled-source :on-press select-activity}
     "2"]
    [:button
     {:variant "ghost" :icon "chevron-right"
      :icon-placement "trailing" :disabled disabled-source
      :on-press select-activity}
     "Next"]]
   [:paragraph
    "Both containers are plain composition; the shared tab Signal also controls the current page."]])

(defui tabs-gallery
  [overview-selected-source activity-selected-source content-source
   disabled-source select-overview select-activity]
  [:column {:gap 16 :padding 32}
   [:heading {:level 2} "Tabs"]
   [:tabs
    [:button
     {:selected overview-selected-source
      :disabled disabled-source
      :on-press select-overview}
     "Overview"]
    [:button
     {:selected activity-selected-source
      :disabled disabled-source
      :on-press select-activity}
     "Activity"]]
   [:card {:padding 16}
    [:paragraph {:value content-source}]]
   [:paragraph
    "Tabs owns layout and platform presentation; Signals own selection and content."]])

(defui component-gallery
  [disabled-source toggle-disabled card-copy
   value-source update-value
   checked-source update-toggle
   progress-source progress-label-source advance-progress
   comfortable-source compact-source volume-source volume-label-source
   select-comfortable select-compact update-volume
   environment-source picker-query-source select-open-source
   combobox-open-source production-selected-source staging-selected-source
   open-select open-combobox update-picker-query submit-picker-query
   dismiss-picker select-production select-staging
   report-selected-source checklist-selected-source document-action-source
   select-report select-checklist open-report open-checklist
   avatar-image-source toggle-avatar-image
   overview-tab-selected-source activity-tab-selected-source
   tab-content-source select-overview-tab select-activity-tab
   dialog-open-source open-dialog close-dialog
   drawer-open-source open-drawer close-drawer
   sheet-open-source open-sheet close-sheet]
  [:column
   [button-gallery disabled-source toggle-disabled]
   [toggle-button-gallery
    checked-source disabled-source update-toggle toggle-disabled]
   [action-group-gallery
    checked-source disabled-source update-toggle toggle-disabled]
   [navigation-gallery
    overview-tab-selected-source activity-tab-selected-source disabled-source
    select-overview-tab select-activity-tab]
   [tabs-gallery
    overview-tab-selected-source activity-tab-selected-source
    tab-content-source disabled-source select-overview-tab
    select-activity-tab]
   [badge-gallery]
   [separator-gallery]
   [skeleton-gallery]
   [spinner-gallery]
   [icon-gallery]
   [progress-gallery progress-source progress-label-source advance-progress]
   [surface-gallery card-copy]
   [dialog-gallery dialog-open-source open-dialog close-dialog]
   [edge-surface-gallery
    drawer-open-source open-drawer close-drawer
    sheet-open-source open-sheet close-sheet]
   [collection-gallery]
   [list-item-gallery
    report-selected-source checklist-selected-source disabled-source
    document-action-source select-report select-checklist open-report
    open-checklist]
   [avatar-gallery avatar-image-source toggle-avatar-image]
   [text-entry-gallery value-source disabled-source update-value]
   [picker-gallery
    environment-source picker-query-source select-open-source
    combobox-open-source production-selected-source staging-selected-source
    disabled-source open-select open-combobox update-picker-query
    submit-picker-query dismiss-picker select-production select-staging]
   [toggle-gallery checked-source disabled-source update-toggle]
   [value-control-gallery
    checked-source comfortable-source compact-source volume-source
    volume-label-source disabled-source update-toggle select-comfortable
    select-compact update-volume]])
