(ns todos.view
  (:require [lui.protocol :refer [TextChanged MacOS IOS AndroidOS WebOS]]
            [lui.macros :refer [defui reactive event platform]]
            [todos.model :as model]))

(defn content-padding [operating-system]
  (match operating-system
    MacOS 24
    IOS 20
    AndroidOS 16
    WebOS 16
    _ 16))

(defn content-gap [operating-system]
  (match operating-system
    MacOS 14
    IOS 12
    AndroidOS 12
    _ 12))

(defn item-label [item]
  (str (if (:todo-done item) "[x] " "[ ] ")
       (:todo-title item)))

(defn summary-label [model]
  (let [items (:model-items model)
        remaining
        (count (filterv (fn [item] (not (:todo-done item))) items))]
    (str remaining " remaining / " (count items) " total")))

(defui todo-row [item-source send]
  [:row {:gap 8}
   [:text {:value (reactive item-label item-source)}]
   [:button
    {:on-press (event [item item-source]
                 (send (model/ToggleTodo (:todo-id item))))}
    "Toggle"]
   [:button
    {:on-press (event [item item-source]
                 (send (model/MoveTodoUp (:todo-id item))))}
    "Up"]
   [:button
    {:on-press (event [item item-source]
                 (send (model/DeleteTodo (:todo-id item))))}
    "Delete"]])

(defui todos-view [model-source send]
  [:column {:gap (content-gap (platform))
            :padding (content-padding (platform))}
   [:text "Todos"]
   [:row {:gap 8}
    [:text-input
     {:value (reactive :model-draft model-source)
      :placeholder "What needs to be done?"
      :accessibility-label "New todo"
      :on-change
      (fn [event]
        (match event
          (TextChanged _node text) (send (model/ChangeDraft text))
          _ true))}]
    [:button {:on-press (fn [_event] (send model/AddTodo))} "Add"]]
   [:text-area
    {:value (reactive :model-notes model-source)
     :placeholder "Notes"
     :accessibility-label "Todo notes"
     :min-lines 2
     :max-lines 5
     :on-change
     (fn [event]
       (match event
         (TextChanged _node text) (send (model/ChangeNotes text))
         _ true))}]
   [:scroll
    [:column {:gap 8}
     [:keyed
      {:source (reactive :model-items model-source)
       :key :todo-id
      :compare compare
       :as item-source}
      [todo-row item-source send]]]]
   [:text {:value (reactive summary-label model-source)}]])
