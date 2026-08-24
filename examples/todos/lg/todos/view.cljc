(ns todos.view
  (:require [lui.protocol :refer [TextChanged]]
            [lui.macros :refer [defui reactive event]]
            [todos.model :as model]))

(defn item-label [item]
  (str (if (:todo-done item) "[x] " "[ ] ")
       (:todo-title item)))

(defui todo-row [item-source send]
  [:row {:gap 8}
   [:text {:value (reactive item-label item-source)}]
   [:button
    {:on-press (event [item item-source]
                 (send (model/ToggleTodo (:todo-id item))))}
    "Toggle"]
   [:button
    {:on-press (event [item item-source]
                 (send (model/DeleteTodo (:todo-id item))))}
    "Delete"]])

(defui todos-view [model-source send]
  [:column {:gap 12 :padding 16}
   [:text "Todos"]
   [:row {:gap 8}
    [:text-input
     {:value (reactive :model-draft model-source)
      :on-change
      (fn [event]
        (match event
          (TextChanged _node text) (send (model/ChangeDraft text))
          _ true))}]
    [:button {:on-press (fn [_event] (send model/AddTodo))} "Add"]]
   [:scroll
    [:column {:gap 8}
     [:keyed
      {:source (reactive :model-items model-source)
       :key :todo-id
       :compare compare
       :as item-source}
      [todo-row item-source send]]]]])
