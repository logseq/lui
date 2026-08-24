(ns components.gallery
  (:require [lui.macros :refer [defui]]
            [lui.badge]
            [lui.progress :as progress]
            [lui.separator]
            [lui.skeleton]
            [lui.text-field :as text-field]))

(defui button-gallery [disabled-source toggle-disabled]
  [:column {:gap 24 :padding 32}
   [:text "Button"]
   [:button
    {:variant "outline" :on-press toggle-disabled}
    "Toggle disabled"]
   [:row {:gap 12}
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

(defui badge-gallery []
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Badge"]
   [:row {:gap 8}
    [:badge "Default"]
    [:badge {:variant "secondary"} "Secondary"]
    [:badge {:variant "outline"} "Outline"]
    [:badge {:variant "success"} "Success"]
    [:badge {:variant "warning"} "Warning"]
    [:badge {:variant "error"} "Error"]
    [:badge {:round true} "Round"]]])

(defui progress-gallery [value-source value-label-source advance]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Progress"]
   [:progress {:value value-source}
    [:progress/label "Uploading files"]
    [:progress/value-label {:value value-label-source}]]
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

(defui text-field-gallery
  [value-source invalid-source disabled-source update-value toggle-invalid]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "TextField"]
   [:text-field
    [:text-field/label "Email"]
    [:text-field/input
     {:value value-source
      :type "email"
      :invalid invalid-source
      :disabled disabled-source
      :placeholder "you@example.com"
      :on-change update-value}]
    [:text-field/description "Used for account notifications."]
    [:text-field/error-message "Enter a valid email address."]]
   [:button
    {:variant "outline" :on-press toggle-invalid}
    "Toggle invalid"]
   [:text-field
    [:text-field/label "Notes"]
    [:text-field/text-area
     {:value value-source
      :placeholder "Add notes"
      :min-lines 2
      :max-lines 5
      :disabled disabled-source
      :on-change update-value}]
    [:text-field/description
     "This TextArea shares the same Signal to demonstrate local patches."]]])

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

(defui component-gallery
  [disabled-source toggle-disabled card-copy
   value-source invalid-source update-value toggle-invalid
   checked-source update-toggle
   progress-source progress-label-source advance-progress]
  [:column
   [button-gallery disabled-source toggle-disabled]
   [toggle-button-gallery
    checked-source disabled-source update-toggle toggle-disabled]
   [badge-gallery]
   [separator-gallery]
   [skeleton-gallery]
   [spinner-gallery]
   [icon-gallery]
   [progress-gallery progress-source progress-label-source advance-progress]
   [surface-gallery card-copy]
   [collection-gallery]
   [text-field-gallery
    value-source invalid-source disabled-source update-value toggle-invalid]
   [toggle-gallery checked-source disabled-source update-toggle]])
