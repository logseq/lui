(ns todos.app
  (:require [signal.core]
            [lui.app :as app]
            [todos.model :as model]
            [todos.view :as view]))

(defn create [backend]
  (app/create backend (model/initial) model/update view/todos-view))

(defn model [application]
  (app/model application))
