(ns components.gallery
  (:require [lui.macros :refer [defui]]
            [lui.card :as card]
            [lui.progress :as progress]
            [lui.switch :as switch]
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
     {:variant "destructive"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Destructive"]
    [:button
     {:variant "outline"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Outline"]
    [:button
     {:variant "secondary"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Secondary"]
    [:button
     {:variant "ghost"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Ghost"]
    [:button
     {:variant "link"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "Link"]]
   [:row {:gap 12}
    [:button
     {:size "sm" :disabled disabled-source :on-press (fn [_event] true)}
     "Small"]
    [:button
     {:disabled disabled-source :on-press (fn [_event] true)}
     "Default"]
    [:button
     {:size "lg" :disabled disabled-source :on-press (fn [_event] true)}
     "Large"]
    [:button
     {:size "icon"
      :disabled disabled-source
      :on-press (fn [_event] true)}
     "+"]]])

(defui card-gallery [copy-source]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Card"]
   [:card
    [:card/header
     [:card/title "Account"]
     [:card/description "Manage your profile settings."]]
    [:card/content
     [:paragraph {:value copy-source}]]
    [:card/footer
     [:button {:on-press (fn [_event] true)} "Save changes"]]]])

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

(defui toggle-gallery
  [checked-source indeterminate-source invalid-source disabled-source
   update-toggle toggle-indeterminate toggle-invalid]
  [:column {:gap 24 :padding 32}
   [:heading {:level 2} "Checkbox and Switch"]
   [:row {:gap 12}
    [:checkbox
     {:checked checked-source
      :indeterminate indeterminate-source
      :disabled disabled-source
      :accessibility-label "Enable notifications"
      :on-change update-toggle}]
    [:paragraph "Native Checkbox with checked and indeterminate Signals"]]
   [:switch
    {:checked checked-source
     :disabled disabled-source
     :invalid invalid-source
     :on-change update-toggle}
    [:switch/control
     [:switch/thumb]]
    [:switch/label "Background sync"]
    [:switch/description
     "The retained control keeps its identity while the Signal changes."]
    [:switch/error-message "Background sync is currently unavailable."]]
   [:row {:gap 12}
    [:button
     {:variant "outline" :on-press toggle-indeterminate}
     "Toggle indeterminate"]
    [:button
     {:variant "outline" :on-press toggle-invalid}
     "Toggle switch invalid"]]])

(defui component-gallery
  [disabled-source toggle-disabled card-copy
   value-source invalid-source update-value toggle-invalid
   checked-source indeterminate-source toggle-invalid-source
   update-toggle toggle-indeterminate toggle-toggle-invalid
   progress-source progress-label-source advance-progress]
  [:column
   [button-gallery disabled-source toggle-disabled]
   [badge-gallery]
   [separator-gallery]
   [progress-gallery progress-source progress-label-source advance-progress]
   [card-gallery card-copy]
   [text-field-gallery
    value-source invalid-source disabled-source update-value toggle-invalid]
   [toggle-gallery
    checked-source indeterminate-source toggle-invalid-source disabled-source
    update-toggle toggle-indeterminate toggle-toggle-invalid]])
