(ns components.gallery
  (:require [lui.macros :refer [defui]]
            [lui.card :as card]))

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

(defui component-gallery [disabled-source toggle-disabled card-copy]
  [:column
   [button-gallery disabled-source toggle-disabled]
   [card-gallery card-copy]])
