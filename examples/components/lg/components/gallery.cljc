(ns components.gallery
  (:require [lui.macros :refer [defui]]))

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
